#!/usr/bin/env python3
"""Tests for bin/bin/logsweep. Run: python3 tools/test_logsweep.py"""
import importlib.util
import os
import re
import sys
import unittest
from importlib.machinery import SourceFileLoader

HERE = os.path.dirname(os.path.abspath(__file__))
SCRIPT = os.path.join(HERE, "..", "bin", "bin", "logsweep")
FIXTURES = os.path.join(HERE, "fixtures", "logsweep")

# bin/bin is stowed into ~/bin; never leave a __pycache__ or logsweepc there.
sys.dont_write_bytecode = True
_loader = SourceFileLoader("logsweep", SCRIPT)
_spec = importlib.util.spec_from_loader("logsweep", _loader)
ls = importlib.util.module_from_spec(_spec)
sys.modules["logsweep"] = ls  # dataclasses look the module up by name
_loader.exec_module(ls)


class DurationTest(unittest.TestCase):
    def test_units(self):
        self.assertEqual(ls.parse_duration("30m"), 1800)
        self.assertEqual(ls.parse_duration("24h"), 86400)
        self.assertEqual(ls.parse_duration("7d"), 604800)

    def test_rejects_bad_values(self):
        for bad in ("", "24", "h", "0h", "-1h", "1.5h", "1w", "24 h"):
            with self.assertRaises(ValueError, msg=bad):
                ls.parse_duration(bad)


class ArgsTest(unittest.TestCase):
    def test_defaults(self):
        args = ls.parse_args([])
        self.assertEqual(args.since, 86400)
        self.assertEqual(args.family, list(ls.FAMILIES))
        self.assertFalse(args.no_color)

    def test_family_subset_keeps_canonical_order(self):
        args = ls.parse_args(["--family", "waste,auth"])
        self.assertEqual(args.family, ["auth", "waste"])

    def test_bad_values_exit_2(self):
        for argv in (["--since", "soon"], ["--family", "auth,nope"], ["--family", ""]):
            with self.assertRaises(SystemExit) as cm, redirect_stderr(io.StringIO()):
                ls.parse_args(argv)
            self.assertEqual(cm.exception.code, 2, argv)


import json
from datetime import datetime, timedelta, timezone

REAL_LINE = json.dumps({
    "timestamp": "2026-10-04 01:35:56.304283-0400",
    "processImagePath": "/usr/libexec/opendirectoryd", "processID": 365,
    "subsystem": "com.apple.opendirectoryd", "category": "auth",
    "eventType": "logEvent",
    "eventMessage": "Authentication failed for <private> "
                    "(00000000-0000-0000-0000-000000000000): ODErrorCredentialsInvalid",
})
TRAILER = '{"count":1,"finished":1}'


class ParseEventTest(unittest.TestCase):
    def test_real_line(self):
        ev = ls.parse_event(REAL_LINE)
        self.assertEqual(ev.process, "opendirectoryd")
        self.assertEqual(ev.pid, 365)
        self.assertEqual(ev.subsystem, "com.apple.opendirectoryd")
        self.assertEqual(ev.category, "auth")
        self.assertEqual(ev.event_type, "logEvent")
        self.assertIn("<private>", ev.message)
        self.assertEqual(ev.timestamp.utcoffset(), timedelta(hours=-4))
        self.assertEqual(ev.timestamp.hour, 1)

    def test_trailer_and_blank_are_ignored_not_errors(self):
        self.assertIsNone(ls.parse_event(TRAILER))
        self.assertIsNone(ls.parse_event("   \n"))

    def test_malformed_lines_raise(self):
        for bad in ("not json", "[1,2]", '{"eventMessage":"no timestamp"}',
                    '{"timestamp":"yesterday"}', '{"timestamp":null}'):
            with self.assertRaises(ValueError, msg=bad):
                ls.parse_event(bad)

    def test_missing_optional_fields_default_to_empty(self):
        ev = ls.parse_event('{"timestamp":"2026-10-04 01:35:56.304283-0400",'
                            '"processImagePath":"/kernel","subsystem":null}')
        self.assertEqual((ev.process, ev.pid, ev.subsystem, ev.message), ("kernel", 0, "", ""))


class FakeProc:
    def __init__(self, lines, code):
        self.stdout = iter(lines)
        self._code = code
        self.killed = False

    def wait(self):
        return self._code

    def poll(self):
        return self._code

    def kill(self):
        self.killed = True


def fake_popen(lines, code=0, err="", record=None):
    def popen(cmd, stdout=None, stderr=None, text=None, errors=None):
        if record is not None:
            record.append(cmd)
        stderr.write(err)
        return FakeProc(lines, code)
    return popen


class MacLogSourceTest(unittest.TestCase):
    def test_yields_events_and_counts_skipped(self):
        src = ls.MacLogSource(popen=fake_popen([REAL_LINE + "\n", "garbage\n", TRAILER + "\n"]))
        events = list(src.events('process == "x"', 3600))
        self.assertEqual(len(events), 1)
        self.assertEqual(src.skipped, 1)

    def test_command_line(self):
        seen = []
        src = ls.MacLogSource(popen=fake_popen([], record=seen))
        list(src.events('process == "sudo"', 86400))
        self.assertEqual(seen[0], ["/usr/bin/log", "show", "--style", "ndjson",
                                   "--last", "1440m", "--predicate", 'process == "sudo"'])

    def test_nonzero_exit_raises_with_stderr_reason(self):
        err = "log: Bad predicate (Unable to parse): bogus ==\n" + TRAILER + "\n"
        src = ls.MacLogSource(popen=fake_popen([], code=64, err=err))
        with self.assertRaises(ls.SourceError) as cm:
            list(src.events("bogus ==", 60))
        self.assertIn("exited 64", str(cm.exception))
        self.assertIn("Bad predicate", str(cm.exception))
        self.assertNotIn("finished", str(cm.exception))

    def test_missing_binary_raises(self):
        def popen(*a, **k):
            raise FileNotFoundError(2, "No such file or directory")
        with self.assertRaises(ls.SourceError) as cm:
            list(ls.MacLogSource(popen=popen).events("x", 60))
        self.assertIn("/usr/bin/log", str(cm.exception))

    def test_timeout_kills_child_and_raises(self):
        class Slow(FakeProc):
            def __init__(self):
                FakeProc.__init__(self, [], -9)
                self.stdout = self._block()

            def _block(self):
                import time
                while not self.killed:
                    time.sleep(0.01)
                return
                yield

        proc = Slow()
        src = ls.MacLogSource(popen=lambda *a, **k: proc, timeout=0.05)
        with self.assertRaises(ls.SourceError) as cm:
            list(src.events("x", 60))
        self.assertTrue(proc.killed)
        self.assertIn("timed out", str(cm.exception))

    @unittest.skipUnless(sys.platform == "darwin" and os.environ.get("LOGSWEEP_LIVE"),
                         "set LOGSWEEP_LIVE=1 on macOS to query the real log")
    def test_live_query(self):
        src = ls.MacLogSource()
        for ev in src.events('process == "sudo" AND eventType == logEvent', 3600):
            self.assertEqual(ev.process, "sudo")
        self.assertEqual(src.skipped, 0)


TZ = timezone(timedelta(hours=-4))


def ev(minute, message="boom", process="proc", hour=9):
    return ls.Event(datetime(2026, 10, 4, hour, minute, 0, tzinfo=TZ),
                    process, 1, "", "", "logEvent", message)


def rule(**kw):
    base = dict(id="t.rule", family="auth", severity="medium", title="test rule",
                predicate='process == "proc"',
                match=lambda e: e.process if e.message == "boom" else None,
                advice="look into it")
    base.update(kw)
    return ls.Rule(**base)


def run_rule(r, events):
    m = ls.Matches()
    for e in events:
        m.add(r, e)
    return m.findings(r)


class ReachesTest(unittest.TestCase):
    def stamps(self, *minutes):
        return [(datetime(2026, 10, 4, 9, m, tzinfo=TZ), 1) for m in minutes]

    def test_below_threshold(self):
        self.assertFalse(ls.reaches(self.stamps(0, 1), 3, 10))

    def test_at_threshold_inside_window(self):
        self.assertTrue(ls.reaches(self.stamps(0, 5, 10), 3, 10))

    def test_enough_events_but_spread_wider_than_window(self):
        self.assertFalse(ls.reaches(self.stamps(0, 6, 12, 18), 3, 10))

    def test_burst_later_in_the_series(self):
        self.assertTrue(ls.reaches(self.stamps(0, 30, 31, 32), 3, 10))

    def test_unsorted_input(self):
        self.assertTrue(ls.reaches(self.stamps(32, 0, 31, 30), 3, 10))

    def test_weights_count_as_occurrences(self):
        one = [(datetime(2026, 10, 4, 9, 0, tzinfo=TZ), 3)]
        self.assertTrue(ls.reaches(one, 3, 10))


class RuleEvaluationTest(unittest.TestCase):
    def test_no_threshold_one_finding_per_subject(self):
        found = run_rule(rule(), [ev(0), ev(5), ev(7, process="other"), ev(9, message="fine")])
        by_subject = {f.subject: f for f in found}
        self.assertEqual(sorted(by_subject), ["other", "proc"])
        f = by_subject["proc"]
        self.assertEqual((f.count, f.first_seen.minute, f.last_seen.minute), (2, 0, 5))
        self.assertEqual((f.rule_id, f.family, f.severity, f.title, f.advice),
                         ("t.rule", "auth", "medium", "test rule", "look into it"))
        self.assertEqual(f.sample, "boom")

    def test_threshold_suppresses_quiet_subjects(self):
        r = rule(threshold=(3, 10))
        found = run_rule(r, [ev(0), ev(1), ev(2), ev(3, process="quiet")])
        self.assertEqual([f.subject for f in found], ["proc"])
        self.assertEqual(found[0].count, 3)

    def test_threshold_finding_reports_all_matches_in_window(self):
        r = rule(threshold=(3, 10))
        found = run_rule(r, [ev(0), ev(1), ev(2), ev(50)])
        self.assertEqual((found[0].count, found[0].last_seen.minute), (4, 50))

    def test_weight_sums_into_count(self):
        r = rule(threshold=(3, 10), weight=lambda e: 3)
        found = run_rule(r, [ev(0)])
        self.assertEqual(found[0].count, 3)

    def test_no_matches_no_findings(self):
        self.assertEqual(run_rule(rule(), [ev(0, message="fine")]), [])

    def test_sample_collapses_whitespace(self):
        r = rule(match=lambda e: "s")
        found = run_rule(r, [ev(0, message="  a\n   b  ")])
        self.assertEqual(found[0].sample, "a b")

    def test_family_predicate_ors_and_parenthesises(self):
        a, b = rule(predicate="A == 1"), rule(predicate="B == 2 OR C == 3")
        self.assertEqual(ls.family_predicate([a, b]), "(A == 1) OR (B == 2 OR C == 3)")


def fixture(name):
    with open(os.path.join(FIXTURES, name)) as f:
        return [ls.parse_event(line) for line in f if line.strip()]


def get_rule(rule_id):
    return next(r for r in ls.RULES if r.id == rule_id)


class RuleTableTest(unittest.TestCase):
    def test_every_rule_is_well_formed(self):
        ids = [r.id for r in ls.RULES]
        self.assertEqual(len(ids), len(set(ids)))
        for r in ls.RULES:
            self.assertIn(r.family, ls.FAMILIES, r.id)
            self.assertIn(r.severity, ls.SEVERITIES, r.id)
            self.assertTrue(r.id.startswith(r.family + "."), r.id)
            self.assertTrue(r.title and r.advice, r.id)
            # Global constraint: scoped by process or subsystem, never message alone.
            self.assertRegex(r.predicate, r"\b(process|subsystem) ==", r.id)

    def test_no_rule_matches_the_query_about_itself(self):
        # `log` records its own invocation, quoting the predicate text.
        for r in ls.RULES:
            echo = ls.Event(datetime(2026, 10, 4, 9, 0, tzinfo=TZ), "log", 1,
                            "com.apple.log", "", "logEvent",
                            "log run noninteractively, args: '--predicate' '%s' "
                            "Authentication failed 3 incorrect password attempts" % r.predicate)
            self.assertIsNone(r.match(echo), r.id)


class LoginFailureRuleTest(unittest.TestCase):
    def setUp(self):
        self.rule = get_rule("auth.login-failure")
        self.od, self.authhost = fixture("auth.login-failure.ndjson")

    def test_matches_both_real_lines_with_process_as_subject(self):
        self.assertEqual(self.rule.match(self.od), "opendirectoryd")
        self.assertEqual(self.rule.match(self.authhost), "authorizationhost")

    def test_near_misses(self):
        import dataclasses
        ok = dataclasses.replace(self.od, message="Authentication succeeded for <private>")
        other = dataclasses.replace(self.od, category="session")
        self.assertIsNone(self.rule.match(ok))
        self.assertIsNone(self.rule.match(other))

    def test_threshold_is_five_in_ten_minutes(self):
        self.assertEqual(self.rule.threshold, (5, 10))
        self.assertEqual(self.rule.severity, "medium")


class SudoFailureRuleTest(unittest.TestCase):
    def setUp(self):
        self.rule = get_rule("auth.sudo-failure")
        self.near_miss, self.failure = fixture("auth.sudo-failure.ndjson")

    def test_matches_real_failure_with_user_as_subject(self):
        self.assertEqual(self.rule.match(self.failure), "alice")

    def test_password_required_is_not_a_failure(self):
        self.assertIsNone(self.rule.match(self.near_miss))

    def test_weight_is_the_attempt_count_in_the_message(self):
        import dataclasses
        self.assertEqual(self.rule.weight(self.failure), 1)
        three = dataclasses.replace(
            self.failure,
            message=self.failure.message.replace("1 incorrect password attempt",
                                                 "3 incorrect password attempts"))
        self.assertEqual(self.rule.match(three), "alice")
        self.assertEqual(self.rule.weight(three), 3)
        self.assertEqual(len(run_rule(self.rule, [three])), 1)   # 3 attempts reach 3-in-10
        self.assertEqual(run_rule(self.rule, [self.failure]), [])  # 1 attempt does not

    def test_threshold_and_severity(self):
        self.assertEqual(self.rule.threshold, (3, 10))
        self.assertEqual(self.rule.severity, "high")


import tempfile

NOW = datetime(2026, 10, 4, 22, 0, 0, tzinfo=TZ)


class ProbeCase(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self._tmp.cleanup)
        self.root = self._tmp.name
        self.home = os.path.join(self.root, "Users", "alice")
        os.makedirs(self.home)
        self.ctx = ls.Context(now=NOW, since=86400, home=self.home, root=self.root)

    def write(self, rel, text="", hours_ago=1.0, base=None):
        path = os.path.join(base or self.root, rel)
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "w", encoding="utf-8") as f:
            f.write(text)
        self.age(path, hours_ago)
        return path

    def age(self, path, hours_ago):
        t = (NOW - timedelta(hours=hours_ago)).timestamp()
        os.utime(path, (t, t))

    def run_probe(self, probe_id):
        probe = next(p for p in ls.PROBES if p.id == probe_id)
        return probe.run(probe, self.ctx)


class ContextTest(ProbeCase):
    def test_cutoffs(self):
        self.assertEqual(self.ctx.cutoff(), NOW - timedelta(hours=24))
        self.assertEqual(self.ctx.persist_cutoff(), NOW - timedelta(days=7))
        wide = ls.Context(now=NOW, since=30 * 86400, home=self.home, root=self.root)
        self.assertEqual(wide.persist_cutoff(), NOW - timedelta(days=30))

    def test_path_joins_under_root(self):
        self.assertEqual(self.ctx.path("/var/log/install.log"),
                         os.path.join(self.root, "var/log/install.log"))


class RecentFilesTest(ProbeCase):
    def test_window_and_missing_dir(self):
        d = os.path.join(self.root, "d")
        new = self.write("d/new one.plist", hours_ago=1)
        self.write("d/old.plist", hours_ago=48)
        found = ls.recent_files([d, os.path.join(self.root, "absent")], self.ctx.cutoff())
        self.assertEqual([p for p, _ in found], [new])
        self.assertEqual(found[0][1], NOW - timedelta(hours=1))

    @unittest.skipIf(os.geteuid() == 0, "root can read anything")
    def test_unreadable_dir_raises(self):
        d = os.path.join(self.root, "locked")
        os.makedirs(d)
        os.chmod(d, 0)
        self.addCleanup(os.chmod, d, 0o700)
        with self.assertRaises(ls.ProbeError) as cm:
            ls.recent_files([d], self.ctx.cutoff())
        self.assertIn("locked", str(cm.exception))
        self.assertIn("permission denied", str(cm.exception))


class CrashReportsTest(ProbeCase):
    def test_real_filename_shapes(self):
        d = os.path.join(self.root, "reports")
        names = {
            "TypeToSiriWidgetExtension-2026-09-28-001725.ips": ("TypeToSiriWidgetExtension", "ips"),
            "AddressBookManager_2026-09-30-133324_host.diag": ("AddressBookManager", "diag"),
            "apfsd_2026-09-30-071448_host.cpu_resource.diag": ("apfsd", "cpu_resource.diag"),
            "shutdown_stall_2026-09-30-071448_host.shutdownStall": ("shutdown_stall", "shutdownStall"),
            "JetsamEvent-2026-09-29-021404.ips": ("JetsamEvent", "ips"),
            "Google Chrome Helper-2026-09-28-001725.ips": ("Google Chrome Helper", "ips"),
            "qemu-img_2026-09-30-071448_host.diag": ("qemu-img", "diag"),
            "notes.txt": ("notes", "txt"),
        }
        for n in names:
            self.write(os.path.join("reports", n))
        self.write("reports/Retired/old_2026-09-30-071448_host.diag")
        os.makedirs(os.path.join(d, "DiagnosticLogs"))
        got = {os.path.basename(r.path): (r.process, r.kind)
               for r in ls.crash_reports([d], self.ctx.cutoff())}
        self.assertEqual(got, names)

    def test_window_uses_mtime(self):
        self.write("reports/a-2026-09-28-001725.ips", hours_ago=48)
        d = os.path.join(self.root, "reports")
        self.assertEqual(ls.crash_reports([d], self.ctx.cutoff()), [])


class PersistProbesTest(ProbeCase):
    def test_launchd_plists_use_seven_day_window(self):
        self.write("Library/LaunchDaemons/us.zoom.ZoomDaemon.plist", hours_ago=72)
        self.write("Library/LaunchAgents/ancient.plist", hours_ago=24 * 30)
        self.write("Library/LaunchAgents/mine.plist", hours_ago=2, base=self.home)
        found = self.run_probe("persist.launchd-plist")
        self.assertEqual(sorted(f.subject for f in found),
                         ["mine.plist", "us.zoom.ZoomDaemon.plist"])
        f = found[0]
        self.assertEqual((f.family, f.severity, f.count), ("persist", "medium", 1))
        self.assertIn("hygiene signal", f.title)
        self.assertTrue(f.sample.endswith(f.subject))

    def test_crontab_dir_mtime(self):
        tabs = os.path.join(self.root, "usr/lib/cron/tabs")
        os.makedirs(tabs)
        self.age(tabs, 24 * 30)
        self.assertEqual(self.run_probe("persist.crontab"), [])
        self.age(tabs, 3)
        found = self.run_probe("persist.crontab")
        self.assertEqual(len(found), 1)
        self.assertEqual(found[0].last_seen, NOW - timedelta(hours=3))

    def test_crontab_dir_absent_is_not_an_error(self):
        self.assertEqual(self.run_probe("persist.crontab"), [])

    def test_installs_from_real_line_format(self):
        log = (
            '2026-09-01 15:47:15-04 host installd[847]: Installed "Ancient" (1.0)\n'
            '2026-10-01 15:47:15-04 host installd[847]: Installed "TestFlight" (4.4.0)\n'
            '2026-10-01 15:48:24-04 host installd[847]: Installed "\u200eWhatsApp" (26.38.74)\n'
            '2026-10-04 15:46:51-04 host installd[847]: Installed "TestFlight" (4.4.1)\n'
            '2026-10-02 04:57:31-04 host system_installd[849]: Installed "XProtectPlistConfigData" (5363)\n'
            '2026-10-04 15:46:52-04 host installd[847]: PackageKit: ----- End install -----\n'
            'a continuation line with no timestamp\n')
        self.write("var/log/install.log", log)
        found = {f.subject: f for f in self.run_probe("persist.install")}
        self.assertEqual(sorted(found),
                         ["TestFlight", "XProtectPlistConfigData", "\\u200eWhatsApp"])
        tf = found["TestFlight"]
        self.assertEqual((tf.count, tf.severity), (2, "info"))
        self.assertIn("4.4.1", tf.sample)
        self.assertEqual(tf.last_seen, datetime(2026, 10, 4, 15, 46, 51, tzinfo=TZ))

    def test_install_log_with_invalid_bytes(self):
        path = self.write("var/log/install.log")
        with open(path, "wb") as f:
            f.write(b'2026-10-04 15:46:51-04 host installd[1]: Installed "Caf\xff" (1)\n')
        self.assertEqual(len(self.run_probe("persist.install")), 1)

    def test_install_log_absent_is_not_an_error(self):
        self.assertEqual(self.run_probe("persist.install"), [])


class CrashProbesTest(ProbeCase):
    def reports(self, name, n, kind="ips"):
        for i in range(n):
            self.write("Library/Logs/DiagnosticReports/%s-2026-10-04-0000%02d.%s" % (name, i, kind),
                       hours_ago=1 + i)

    def test_split_between_stability_and_waste(self):
        self.reports("flaky", 2)
        self.reports("looper", 3)
        self.reports("JetsamEvent", 1)
        self.write("Library/Logs/DiagnosticReports/userapp-2026-10-04-000000.ips",
                   hours_ago=1, base=self.home)
        stab = {f.subject: f for f in self.run_probe("stability.crash-report")}
        waste = {f.subject: f for f in self.run_probe("waste.repeat-crasher")}
        self.assertEqual(sorted(stab), ["flaky", "userapp"])
        self.assertEqual(sorted(waste), ["looper"])
        self.assertEqual((stab["flaky"].count, stab["flaky"].severity), (2, "info"))
        self.assertEqual((waste["looper"].count, waste["looper"].severity), (3, "medium"))
        self.assertEqual(waste["looper"].last_seen, NOW - timedelta(hours=1))

    def test_jetsam_events(self):
        self.reports("JetsamEvent", 2)
        self.reports("flaky", 1)
        found = self.run_probe("waste.jetsam")
        self.assertEqual(len(found), 1)
        self.assertEqual((found[0].count, found[0].severity), (2, "medium"))


LAUNCHD_LINE = ("%s (gui/501/%s) <Notice>: Service only ran for 0 seconds. "
                "Pushing respawn out by 10 seconds.\n")


class RespawnProbeTest(ProbeCase):
    def launchd_log(self, lines, name="launchd.log"):
        self.write("var/log/com.apple.xpc.launchd/" + name, "".join(lines))

    def line(self, hhmm, service):
        return LAUNCHD_LINE % ("2026-10-04 %s:00.695608" % hhmm, service)

    def test_three_in_an_hour_is_a_loop(self):
        self.launchd_log([
            "2026-10-04 10:00:00.000001 (system) <Notice>: something unrelated\n",
            self.line("20:00", "com.example.looper"),
            self.line("20:10", "com.example.looper"),
            self.line("20:45", "com.example.looper"),
            self.line("12:00", "com.example.rare"),
            self.line("20:00", "com.example.rare"),
            "2026-10-04 20:45:16.695654 (gui/501/com.example.looper) <Notice>: "
            "service spawn deferred by 10 seconds due to throttle\n",
        ])
        found = self.run_probe("waste.respawn-loop")
        self.assertEqual([f.subject for f in found], ["gui/501/com.example.looper"])
        self.assertEqual((found[0].count, found[0].severity), (3, "medium"))
        self.assertEqual(found[0].first_seen, datetime(2026, 10, 4, 20, 0, 0, 695608, tzinfo=TZ))

    def test_reads_rotated_files_and_respects_window(self):
        self.launchd_log([self.line("20:00", "svc"), self.line("20:10", "svc")])
        self.launchd_log([LAUNCHD_LINE % ("2026-10-01 20:00:00.000001", "svc"),
                          LAUNCHD_LINE % ("2026-10-04 19:50:00.000001", "svc")], "launchd.log.1")
        found = self.run_probe("waste.respawn-loop")
        self.assertEqual(found[0].count, 3)

    def test_notes_when_log_is_shorter_than_window(self):
        self.launchd_log(["2026-10-04 10:07:50.507756 (system) <Notice>: first line kept\n"])
        self.assertEqual(self.run_probe("waste.respawn-loop"), [])
        self.assertEqual(self.ctx.notes["waste"],
                         ["launchd.log only goes back to 10-04 10:07 (rotated by size)"])

    def test_no_note_when_log_covers_window(self):
        self.launchd_log(["2026-10-01 10:07:50.507756 (system) <Notice>: old enough\n"])
        self.run_probe("waste.respawn-loop")
        self.assertNotIn("waste", self.ctx.notes)

    def test_absent_log_is_not_an_error(self):
        self.assertEqual(self.run_probe("waste.respawn-loop"), [])


class ProbeTableTest(unittest.TestCase):
    def test_every_probe_is_well_formed(self):
        ids = [p.id for p in ls.PROBES]
        self.assertEqual(len(ids), len(set(ids)))
        self.assertTrue(set(ids).isdisjoint(r.id for r in ls.RULES))
        for p in ls.PROBES:
            self.assertIn(p.family, ls.FAMILIES, p.id)
            self.assertIn(p.severity, ls.SEVERITIES, p.id)
            self.assertTrue(p.id.startswith(p.family + "."), p.id)


import io
from contextlib import redirect_stderr


class ListSource:
    def __init__(self, events=(), error=None, earliest=datetime(2000, 1, 1, tzinfo=TZ)):
        self._events, self._error, self.skipped, self.calls = list(events), error, 0, []
        self._earliest = earliest

    def earliest(self):
        return self._earliest

    def events(self, predicate, since_seconds):
        self.calls.append((predicate, since_seconds))
        for e in self._events:
            yield e
        if self._error:
            raise ls.SourceError(self._error)


def finding(**kw):
    base = dict(rule_id="auth.x", family="auth", severity="high", title="sudo authentication failures",
                subject="alice", count=4,
                first_seen=datetime(2026, 10, 4, 9, 12, tzinfo=TZ),
                last_seen=datetime(2026, 10, 4, 9, 15, tzinfo=TZ),
                sample="alice : 3 incorrect password attempts ; TTY=ttys000", advice="was that you?",
                source="unified log",
                evidence=((datetime(2026, 10, 4, 9, 15, tzinfo=TZ),
                           "alice : 3 incorrect password attempts ; TTY=ttys000"),))
    base.update(kw)
    return ls.Finding(**base)


def probe(family, result=None, error=None, pid=None):
    def run(p, ctx):
        if error:
            raise ls.ProbeError(error)
        return list(result or [])
    return ls.Probe(pid or family + ".p", family, "info", "t", "a", run)


class EngineTest(ProbeCase):
    def test_log_rules_and_probes_combine(self):
        r = rule()
        src = ListSource([ev(0), ev(1)])
        res = ls.run_family("auth", src, self.ctx, rules=[r],
                            probes=[probe("auth", [finding(subject="p")]), probe("waste", [finding()])])
        self.assertEqual(sorted(f.subject for f in res.findings), ["p", "proc"])
        self.assertEqual((res.errors, res.read_ok), ([], 2))
        self.assertEqual(src.calls, [('(process == "proc")', 86400)])

    def test_family_without_log_rules_does_not_query(self):
        src = ListSource()
        res = ls.run_family("waste", src, self.ctx, rules=[rule()], probes=[probe("waste")])
        self.assertEqual((src.calls, res.findings, res.errors, res.read_ok), ([], [], [], 1))

    def test_source_error_discards_partial_log_findings_keeps_probes(self):
        src = ListSource([ev(0)], error="log show timed out after 120s")
        res = ls.run_family("auth", src, self.ctx, rules=[rule()],
                            probes=[probe("auth", [finding(subject="p")])])
        self.assertEqual([f.subject for f in res.findings], ["p"])
        self.assertEqual(res.errors, ["log show timed out after 120s"])
        self.assertEqual(res.read_ok, 1)

    def test_one_probe_failing_does_not_stop_the_next(self):
        res = ls.run_family("persist", ListSource(), self.ctx, rules=[],
                            probes=[probe("persist", error="/x: permission denied", pid="persist.a"),
                                    probe("persist", [finding()], pid="persist.b")])
        self.assertEqual((len(res.findings), res.errors, res.read_ok),
                         (1, ["/x: permission denied"], 1))

    def test_notes_are_collected(self):
        def run(p, ctx):
            ctx.note("waste", "only goes back so far")
            return []
        res = ls.run_family("waste", ListSource(), self.ctx, rules=[],
                            probes=[ls.Probe("waste.n", "waste", "info", "t", "a", run)])
        self.assertEqual(res.notes, ["only goes back so far"])

    def test_findings_sorted_by_severity_then_count(self):
        fs = [finding(severity="info", count=9, subject="c"),
              finding(severity="high", count=1, subject="a"),
              finding(severity="high", count=5, subject="b")]
        res = ls.run_family("auth", ListSource(), self.ctx, rules=[], probes=[probe("auth", fs)])
        self.assertEqual([f.subject for f in res.findings], ["b", "a", "c"])


def result(family, findings=(), errors=(), notes=(), read_ok=1):
    return ls.FamilyResult(family, list(findings), list(errors), list(notes), read_ok)


class RenderTest(unittest.TestCase):
    def render(self, results, **kw):
        args = dict(host="host", since_label="24h", now=NOW, skipped=0, color=False, width=100,
                    max_lines=3)
        args.update(kw)
        return ls.render(results, **args)

    def test_spec_layout(self):
        out = self.render([
            result("auth", [finding()]),
            result("persist", errors=["/Library/LaunchDaemons: permission denied"], read_ok=0),
            result("stability"),
        ], skipped=2)
        lines = out.splitlines()
        self.assertEqual(lines[0], "logsweep — host — last 24h — 2026-10-04 22:00")
        self.assertIn("AUTH", lines)
        row = next(l for l in lines if "sudo authentication failures" in l)
        self.assertRegex(row, r"^  HIGH\s+sudo authentication failures\s+alice\s+x4\s+10-04 09:12 → 09:15$")
        self.assertIn("          source: unified log", lines)
        self.assertIn("          10-04 09:15:00  alice : 3 incorrect password attempts ; TTY=ttys000", lines)
        self.assertIn("          check:  was that you?", lines)
        self.assertIn("  could not check: /Library/LaunchDaemons: permission denied", lines)
        self.assertEqual(lines[lines.index("STABILITY") + 1], "  no findings")
        self.assertEqual(lines[-1], "Summary: 1 high, 0 medium, 0 info · "
                                    "1 family could not be checked · 2 lines skipped")

    def test_never_says_no_findings_when_something_was_unreadable(self):
        out = self.render([result("persist", errors=["/x: permission denied"], read_ok=1)])
        self.assertNotIn("no findings", out)
        self.assertIn("could not check: /x: permission denied", out)

    def test_findings_and_errors_both_shown(self):
        out = self.render([result("auth", [finding()], errors=["log show exited 64"])])
        self.assertIn("sudo authentication failures", out)
        self.assertIn("could not check: log show exited 64", out)

    def test_notes_shown(self):
        out = self.render([result("waste", notes=["launchd.log only goes back to 10-04 10:07"])])
        self.assertIn("  note: launchd.log only goes back to 10-04 10:07", out.splitlines())
        self.assertIn("  no findings", out.splitlines())

    def test_single_occurrence_shows_one_time(self):
        t = datetime(2026, 10, 4, 9, 12, tzinfo=TZ)
        out = self.render([result("auth", [finding(count=1, first_seen=t, last_seen=t)])])
        self.assertRegex(out, r"x1\s+10-04 09:12\n")

    def test_span_across_days_shows_both_dates(self):
        out = self.render([result("auth", [finding(
            first_seen=datetime(2026, 10, 3, 23, 50, tzinfo=TZ))])])
        self.assertIn("10-03 23:50 → 10-04 09:15", out)

    def test_long_lines_truncated_to_width(self):
        out = self.render([result("auth", [finding(
            subject="s" * 300, evidence=((NOW, "x" * 500),))])], width=60)
        self.assertTrue(all(len(l) <= 60 for l in out.splitlines()), out)
        self.assertIn("…", out)

    def test_color_only_when_asked(self):
        plain = self.render([result("auth", [finding()])])
        self.assertNotIn("\033[", plain)
        colored = self.render([result("auth", [finding()])], color=True)
        self.assertIn("\033[", colored)
        strip = re.sub(r"\033\[[0-9;]*m", "", colored)
        self.assertEqual(strip, plain)

    def test_summary_pluralisation(self):
        out = self.render([result("auth", errors=["e"], read_ok=0),
                           result("waste", errors=["e"], read_ok=0)], skipped=1)
        self.assertTrue(out.endswith("2 families could not be checked · 1 line skipped\n"))


class MainTest(ProbeCase):
    def main(self, argv, source=None, **kw):
        out = io.StringIO()
        kw.setdefault("platform", "darwin")
        code = ls.main(argv, source=source or ListSource(), ctx=self.ctx, out=out, **kw)
        return code, out.getvalue()

    def test_clean_run_exits_0_and_prints_every_family(self):
        code, out = self.main([])
        self.assertEqual(code, 0)
        for name in ("AUTH", "PERSISTENCE", "STABILITY", "WASTE"):
            self.assertIn(name, out.splitlines())
        self.assertIn("last 24h", out)

    def test_family_and_since_flags(self):
        src = ListSource()
        code, out = self.main(["--family", "auth", "--since", "7d"], source=src)
        self.assertEqual(code, 0)
        self.assertNotIn("WASTE", out)
        self.assertIn("last 7d", out)
        self.assertEqual(src.calls[0][1], 7 * 86400)

    def test_findings_still_exit_0(self):
        failure = fixture("auth.sudo-failure.ndjson")[1]
        code, out = self.main(["--family", "auth"], source=ListSource([failure] * 3))
        self.assertEqual(code, 0)
        self.assertIn("sudo authentication failures", out)

    def test_nothing_readable_exits_2_but_prints_report(self):
        code, out = self.main(["--family", "auth"], source=ListSource(error="log show exited 1"))
        self.assertEqual(code, 2)
        self.assertIn("could not check: log show exited 1", out)

    def test_partly_readable_exits_0(self):
        code, _ = self.main([], source=ListSource(error="log show exited 1"))
        self.assertEqual(code, 0)

    def test_unsupported_platform_exits_2(self):
        err = io.StringIO()
        with redirect_stderr(err):
            code, out = self.main([], platform="linux")
        self.assertEqual((code, out), (2, ""))
        self.assertEqual(err.getvalue(), "logsweep: linux is not supported yet\n")

    def test_ctrl_c_exits_130_without_traceback(self):
        class Interrupted(ListSource):
            def events(self, predicate, since_seconds):
                raise KeyboardInterrupt
                yield
        err = io.StringIO()
        with redirect_stderr(err):
            code, _ = self.main(["--family", "auth"], source=Interrupted())
        self.assertEqual(code, 130)
        self.assertNotIn("Traceback", err.getvalue())

    def test_closed_pipe_exits_quietly(self):
        class Closed(io.StringIO):
            def write(self, s):
                raise BrokenPipeError
        err = io.StringIO()
        with redirect_stderr(err):
            code = ls.main([], source=ListSource(), ctx=self.ctx, platform="darwin", out=Closed())
        self.assertEqual((code, err.getvalue()), (0, ""))

    def test_skipped_lines_reach_the_summary(self):
        src = ListSource()
        src.skipped = 3
        _, out = self.main(["--family", "auth"], source=src)
        self.assertIn("3 lines skipped", out)

    def test_no_color_when_out_is_not_a_tty(self):
        failure = fixture("auth.sudo-failure.ndjson")[1]
        _, out = self.main(["--family", "auth"], source=ListSource([failure] * 3))
        self.assertNotIn("\033[", out)


# --- pinned by the whole-branch review -------------------------------------

def burst(event, *seconds, minute=46):
    """Copies of event at the given second.millisecond offsets within one minute."""
    import dataclasses
    out = []
    for s in seconds:
        whole = int(s)
        micro = int(round((s - whole) * 1000000))
        out.append(dataclasses.replace(
            event, timestamp=datetime(2026, 10, 5, 2, minute, whole, micro, tzinfo=TZ)))
    return out


class BurstTest(unittest.TestCase):
    def test_lines_within_burst_window_are_one_occurrence(self):
        r = rule(threshold=(2, 10), burst_seconds=2)
        self.assertEqual(run_rule(r, burst(ev(0), 1.0, 1.2, 1.4, 2.9)), [])

    def test_separate_bursts_each_count_once(self):
        r = rule(threshold=(2, 10), burst_seconds=2)
        found = run_rule(r, burst(ev(0), 1.0, 1.2, 30.0, 30.1))
        self.assertEqual(found[0].count, 2)

    def test_without_burst_seconds_every_line_counts(self):
        found = run_rule(rule(threshold=(2, 10)), burst(ev(0), 1.0, 1.2))
        self.assertEqual(found[0].count, 2)

    def test_real_keybag_burst_is_two_attempts_not_six(self):
        # Shape captured 2026-10-05 02:46: three lines in 300 ms, twice, 10 s apart.
        r = get_rule("auth.login-failure")
        od = fixture("auth.login-failure.ndjson")[0]
        self.assertEqual(run_rule(r, burst(od, 32.204, 32.333, 32.469, 42.254, 42.383, 42.521)), [])

    def test_five_real_attempts_still_fire(self):
        r = get_rule("auth.login-failure")
        od = fixture("auth.login-failure.ndjson")[0]
        events = []
        for minute in range(40, 45):
            events += burst(od, 5.0, 5.1, 5.3, minute=minute)
        found = run_rule(r, events)
        self.assertEqual((len(found), found[0].count), (1, 5))


class LogReachTest(ProbeCase):
    def test_earliest_is_when_the_oldest_store_file_was_last_written(self):
        store = os.path.join(self.root, "Persist")
        self.write("Persist/0000000000000002.tracev3", hours_ago=3)
        self.write("Persist/0000000000000001.tracev3", hours_ago=30)
        self.write("Persist/readme.txt", hours_ago=900)
        got = ls.MacLogSource(popen=fake_popen([]), store=store).earliest()
        self.assertEqual(got, NOW - timedelta(hours=30))

    def test_earliest_is_none_when_store_cannot_be_read(self):
        missing = os.path.join(self.root, "nope")
        self.assertIsNone(ls.MacLogSource(popen=fake_popen([]), store=missing).earliest())
        os.makedirs(missing)
        self.assertIsNone(ls.MacLogSource(popen=fake_popen([]), store=missing).earliest())

    def test_note_when_log_is_shorter_than_window(self):
        src = ListSource(earliest=NOW - timedelta(hours=2))
        res = ls.run_family("auth", src, self.ctx, rules=[rule()], probes=[])
        self.assertEqual(res.notes, ["unified log only goes back to about 10-04 20:00"])

    def test_note_when_reach_is_unknown(self):
        res = ls.run_family("auth", ListSource(earliest=None), self.ctx, rules=[rule()], probes=[])
        self.assertEqual(res.notes, ["could not tell how far back the unified log goes"])

    def test_no_note_when_log_covers_window(self):
        src = ListSource(earliest=NOW - timedelta(days=3))
        res = ls.run_family("auth", src, self.ctx, rules=[rule()], probes=[])
        self.assertEqual(res.notes, [])

    def test_no_reach_note_for_family_without_log_rules(self):
        src = ListSource(earliest=NOW)
        res = ls.run_family("waste", src, self.ctx, rules=[rule()], probes=[])
        self.assertEqual(res.notes, [])


class ControlCharacterTest(ProbeCase):
    def test_filename_cannot_forge_report_lines(self):
        self.write("Library/LaunchAgents/evil.plist\nSTABILITY\n  no findings")
        f = self.run_probe("persist.launchd-plist")[0]
        self.assertEqual(f.subject, "evil.plist STABILITY no findings")
        self.assertNotIn("\n", f.sample)

    def test_escape_sequences_are_shown_not_sent(self):
        self.write("Library/LaunchAgents/bad\r\x1b[2K.plist")
        f = self.run_probe("persist.launchd-plist")[0]
        self.assertEqual(f.subject, "bad \\x1b[2K.plist")
        out = ls.render([result("persist", [f])], host="h", since_label="24h", now=NOW,
                        skipped=0, color=False, width=200, max_lines=3)
        self.assertNotIn("\x1b", out)
        self.assertNotIn("\r", out)

    def test_log_message_sample_is_cleaned(self):
        found = run_rule(rule(match=lambda e: "s\x07"), [ev(0, message="a\x1b[1Ab")])
        self.assertEqual((found[0].subject, found[0].sample), ("s\\x07", "a\\x1b[1Ab"))


class ReportNameTest(ProbeCase):
    def test_unusual_report_names_are_not_dropped(self):
        d = os.path.join(self.root, "reports")
        names = {
            "panic-full-2026-09-28-001725.0002.panic": ("panic-full", "panic"),
            "Foo-2026-09-28-001725-1.ips": ("Foo", "ips"),
            "Bar-2026-09-28-001725.000.crash": ("Bar", "crash"),
            "Baz_2026-09-28-001725_mac-2.lan-3.diag": ("Baz", "diag"),
            "undated-report.ips": ("undated-report", "ips"),
        }
        for n in names:
            self.write(os.path.join("reports", n))
        self.write("reports/.DS_Store")
        got = {os.path.basename(r.path): (r.process, r.kind)
               for r in ls.crash_reports([d], self.ctx.cutoff())}
        self.assertEqual(got, names)


class FormatDriftTest(ProbeCase):
    def test_launchd_log_with_no_readable_line_cannot_be_checked(self):
        self.write("var/log/com.apple.xpc.launchd/launchd.log", "Oct  4 20:45:16 launchd: x\nmore\n")
        with self.assertRaises(ls.ProbeError) as cm:
            self.run_probe("waste.respawn-loop")
        self.assertIn("launchd.log", str(cm.exception))
        self.assertIn("unrecognised format", str(cm.exception))

    def test_empty_launchd_log_is_fine(self):
        self.write("var/log/com.apple.xpc.launchd/launchd.log", "")
        self.assertEqual(self.run_probe("waste.respawn-loop"), [])

    def test_install_log_with_no_readable_line_cannot_be_checked(self):
        self.write("var/log/install.log", 'Oct  4 15:46:51 host installd[1]: Installed "X" (1)\n')
        with self.assertRaises(ls.ProbeError) as cm:
            self.run_probe("persist.install")
        self.assertIn("install.log", str(cm.exception))
        self.assertIn("unrecognised format", str(cm.exception))

    def test_empty_install_log_is_fine(self):
        self.write("var/log/install.log", "")
        self.assertEqual(self.run_probe("persist.install"), [])


# --- source and offending lines per finding --------------------------------

def at(hour, minute, second=0, micro=0, day=4):
    return datetime(2026, 10, day, hour, minute, second, micro, tzinfo=TZ)


class EvidenceRenderTest(unittest.TestCase):
    def render(self, f, **kw):
        args = dict(host="host", since_label="24h", now=NOW, skipped=0, color=False,
                    width=100, max_lines=3)
        args.update(kw)
        return ls.render([result("auth", [f])], **args).splitlines()

    def five(self):
        return tuple((at(9, m, 51, 106000), "line %d" % m) for m in range(10, 15))

    def test_source_then_most_recent_lines_in_order_then_remainder(self):
        out = self.render(finding(source="/var/log/x.log", evidence=self.five()))
        i = out.index("          source: /var/log/x.log")
        self.assertEqual(out[i + 1:i + 6], [
            "          10-04 09:12:51.106  line 12",
            "          10-04 09:13:51.106  line 13",
            "          10-04 09:14:51.106  line 14",
            "          … 2 more lines",
            "          check:  was that you?",
        ])
        self.assertFalse(any("sample:" in l for l in out))

    def test_one_hidden_line_is_singular(self):
        out = self.render(finding(evidence=self.five()), max_lines=4)
        self.assertIn("          … 1 more line", out)

    def test_no_remainder_marker_when_everything_is_shown(self):
        out = self.render(finding(evidence=self.five()), max_lines=5)
        self.assertFalse(any("more line" in l for l in out))
        self.assertIn("          10-04 09:10:51.106  line 10", out)

    def test_lines_zero_shows_source_only(self):
        out = self.render(finding(source="/var/log/x.log", evidence=self.five()), max_lines=0)
        self.assertIn("          source: /var/log/x.log", out)
        self.assertFalse(any("line 1" in l or "more line" in l for l in out))

    def test_whole_second_times_have_no_milliseconds(self):
        out = self.render(finding(evidence=((at(9, 12, 5), "whole"),)))
        self.assertIn("          10-04 09:12:05  whole", out)

    def test_source_is_never_clipped_but_lines_are(self):
        # The source of a log finding is a command meant to be pasted.
        src = "unified log · /usr/bin/log show --last 24h --predicate '%s'" % ("x" * 200)
        out = self.render(finding(source=src, evidence=((at(9, 0), "y" * 500),)), width=60)
        self.assertIn("          source: " + src, out)
        ev_line = next(l for l in out if "yyyy" in l)
        self.assertEqual(len(ev_line), 60)

    def test_finding_without_source_or_evidence_still_renders(self):
        out = self.render(finding(source="", evidence=()))
        self.assertFalse(any("source:" in l for l in out))
        self.assertIn("          check:  was that you?", out)


class EvidenceFromRulesTest(ProbeCase):
    def test_log_rule_keeps_every_matching_line_with_its_time(self):
        m = ls.Matches()
        r = rule(threshold=(1, 10), burst_seconds=2)
        for e in burst(ev(0), 1.0, 1.25, 30.0):
            m.add(r, e)
        f = m.findings(r, "the source")[0]
        self.assertEqual(f.source, "the source")
        self.assertEqual(f.count, 2)  # two bursts...
        self.assertEqual([t.second for t, _ in f.evidence], [1, 1, 30])  # ...three lines
        self.assertEqual(f.evidence[1], (at(2, 46, 1, 250000, day=5), "boom"))

    def test_evidence_text_is_cleaned(self):
        m = ls.Matches()
        r = rule(match=lambda e: "s")
        m.add(r, ev(0, message="a\x1b[1A\nb"))
        self.assertEqual(m.findings(r)[0].evidence[0][1], "a\\x1b[1A b")

    def test_engine_gives_log_findings_a_pasteable_command(self):
        res = ls.run_family("auth", ListSource([ev(0)]), self.ctx, rules=[rule()], probes=[])
        self.assertEqual(res.findings[0].source,
                         "unified log · /usr/bin/log show --last 24h "
                         "--predicate 'process == \"proc\"'")

    def test_no_shipped_predicate_contains_a_single_quote(self):
        for r in ls.RULES:
            self.assertNotIn("'", r.predicate, r.id)


class EvidenceFromProbesTest(ProbeCase):
    def test_plist_source_is_the_file_with_home_abbreviated(self):
        self.write("Library/LaunchAgents/mine.plist", hours_ago=2, base=self.home)
        sys_path = self.write("Library/LaunchDaemons/their.plist", hours_ago=2)
        by = {f.subject: f for f in self.run_probe("persist.launchd-plist")}
        self.assertEqual(by["mine.plist"].source, "~/Library/LaunchAgents/mine.plist")
        self.assertEqual(by["their.plist"].source, sys_path)
        self.assertEqual(by["mine.plist"].evidence, ())

    def test_install_source_and_lines(self):
        path = self.write("var/log/install.log",
                          '2026-10-01 15:47:15-04 host installd[847]: Installed "TestFlight" (4.4.0)\n'
                          '2026-10-04 15:46:51-04 host installd[847]: Installed "TestFlight" (4.4.1)\n')
        f = self.run_probe("persist.install")[0]
        self.assertEqual(f.source, path)
        self.assertEqual(f.evidence, ((at(15, 47, 15, day=1), 'Installed "TestFlight" (4.4.0)'),
                                      (at(15, 46, 51), 'Installed "TestFlight" (4.4.1)')))

    def test_single_crash_report_source_is_the_file(self):
        path = self.write("Library/Logs/DiagnosticReports/one-2026-10-04-000000.ips",
                          base=self.home)
        f = self.run_probe("stability.crash-report")[0]
        self.assertEqual(f.source, "~/Library/Logs/DiagnosticReports/one-2026-10-04-000000.ips")
        self.assertEqual(f.evidence, ())
        self.assertTrue(path.endswith(f.source[1:]))

    def test_several_crash_reports_list_each_file(self):
        for i in range(3):
            self.write("Library/Logs/DiagnosticReports/loop-2026-10-04-00000%d.ips" % i,
                       hours_ago=3 - i)
        f = self.run_probe("waste.repeat-crasher")[0]
        self.assertEqual(f.source, os.path.join(self.root, "Library/Logs/DiagnosticReports"))
        self.assertEqual([t for _, t in f.evidence],
                         ["loop-2026-10-04-000000.ips", "loop-2026-10-04-000001.ips",
                          "loop-2026-10-04-000002.ips"])
        self.assertEqual(f.evidence[0][0], NOW - timedelta(hours=3))

    def test_respawn_source_names_the_files_the_lines_came_from(self):
        d = "var/log/com.apple.xpc.launchd/"
        cur = self.write(d + "launchd.log", (LAUNCHD_LINE % ("2026-10-04 20:00:00.000001", "svc"))
                         + (LAUNCHD_LINE % ("2026-10-04 20:10:00.000001", "svc")))
        old = self.write(d + "launchd.log.1", LAUNCHD_LINE % ("2026-10-04 19:50:00.000001", "svc"))
        self.write(d + "launchd.log.2", "2026-10-04 12:00:00.000001 (other) <Notice>: unrelated\n")
        f = self.run_probe("waste.respawn-loop")[0]
        self.assertEqual(f.source, "%s, %s" % (cur, old))
        self.assertEqual([t.minute for t, _ in f.evidence], [50, 0, 10])
        self.assertTrue(f.evidence[0][1].startswith("Service only ran for 0 seconds."))

    def test_crontab_source_is_the_directory(self):
        tabs = os.path.join(self.root, "usr/lib/cron/tabs")
        os.makedirs(tabs)
        self.age(tabs, 3)
        self.assertEqual(self.run_probe("persist.crontab")[0].source, tabs)


class LinesFlagTest(ProbeCase):
    def test_default_and_explicit(self):
        self.assertEqual(ls.parse_args([]).lines, 3)
        self.assertEqual(ls.parse_args(["--lines", "0"]).lines, 0)
        self.assertEqual(ls.parse_args(["--lines", "10"]).lines, 10)

    def test_bad_values_exit_2(self):
        for bad in ("-1", "many", "1.5"):
            with self.assertRaises(SystemExit) as cm, redirect_stderr(io.StringIO()):
                ls.parse_args(["--lines", bad])
            self.assertEqual(cm.exception.code, 2, bad)

    def test_flag_reaches_the_report(self):
        failure = fixture("auth.sudo-failure.ndjson")[1]
        out = io.StringIO()
        ls.main(["--family", "auth", "--lines", "1"], source=ListSource([failure] * 3),
                ctx=self.ctx, platform="darwin", out=out)
        text = out.getvalue()
        self.assertIn("          source: unified log · /usr/bin/log show --last 24h --predicate '", text)
        self.assertEqual(text.count("1 incorrect password attempt"), 1)
        self.assertIn("          … 2 more lines", text)


if __name__ == "__main__":
    unittest.main()

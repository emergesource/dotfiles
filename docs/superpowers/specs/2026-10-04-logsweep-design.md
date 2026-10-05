# logsweep — design

Date: 2026-10-04
Status: awaiting review

## Purpose

A command run by hand on a Mac that reads recent system logs and prints a short
report of things worth a look: suspicious access, newly installed persistence,
instability, and processes stuck in failure loops.

Success means:

- every finding is produced by a rule that can be read and explained;
- a full run takes seconds, not minutes;
- the tool never reports "clean" for something it could not read;
- it changes nothing on the system.

## Decisions

| Decision | Choice | Reason |
|---|---|---|
| Target | macOS in v1; Linux in v2 | Linux rules cannot be verified from this machine. |
| Detection | Curated rules, no baselines, no stored state | Explainable, nothing to maintain between runs. |
| Usage | Interactive report, run on demand | No daemon, no scheduling. |
| Families | Auth, Persistence, Stability, Waste | |
| Waste scope | Log-derived failure loops only | Log volume ranks Apple daemons (`corespotlightd`, `dasd`, `deleted`, `sandboxd`) that cannot be acted on. |
| Suppression | None in v1 | See what the real noise is before designing a mechanism. |
| Language | Python 3.9+, stdlib only | `/usr/bin/python3` is 3.9.6; Homebrew's is newer; `env python3` may pick either. |
| Structure | One file with a rules table | Deploys by symlink like every other script; no `sys.path` handling. |

## Non-goals for v1

- Linux support (the source interface exists; no backend).
- Log-volume statistics or any full-firehose scan.
- A live process snapshot (`ps`, CPU, memory).
- Ignore files, allowlists, or any per-machine configuration.
- JSON output, scheduling, notifications.
- Fixing or changing anything it finds.

## Measurements that shaped the design

Taken on the target Mac on 2026-10-04:

| Query | Result |
|---|---|
| `log show --last 24h`, predicate on `sudo`/`sshd`/`loginwindow` | 2,840 events, 4 s |
| `log show --last 10m`, no predicate | 285,601 events, 275 MB of ndjson, 4.8 s |
| Lines in that sample containing `<private>` | 70,295 (about 25%) |

Consequences:

- Every query uses a narrow predicate. Nothing reads the firehose.
- Output is streamed line by line and never buffered whole.
- Rules match on fields that survive redaction: process, subsystem, category,
  event type and the non-private parts of the message. No rule may depend on a
  value that appears as `<private>`. The tool does not suggest `sudo` on macOS,
  because redaction is assumed to happen at log time (not verified).

## Shape

- File: `bin/bin/logsweep`, no extension, `#!/usr/bin/env python3`, executable,
  stowed to `~/bin/logsweep`.
- Header comment in the style of `freespace.sh`: what it does, usage, flags.

### CLI

```
logsweep [--since DURATION] [--family LIST] [--no-color] [-h]
```

| Flag | Default | Meaning |
|---|---|---|
| `--since` | `24h` | Window for log-event rules. Accepts `Nm`, `Nh`, `Nd`. |
| `--family` | all | Comma-separated subset of `auth,persist,stability,waste`. |
| `--no-color` | off | Disable ANSI colour. Colour is also off when stdout is not a TTY. |

Filesystem-probe rules for persistence use a fixed 7-day window, or `--since`
if that is longer, because a 24-hour mtime window misses anything installed
between runs.

### Exit codes

| Code | Meaning |
|---|---|
| 0 | Run completed, with or without findings. |
| 2 | Bad arguments, unsupported platform, or no source could be read at all. |

## Components

All in one file, in this order. Each can be tested without the others.

### 1. Event and Finding records

```
Event:   timestamp, process, pid, subsystem, category, event_type, message
Finding: rule_id, family, severity, title, subject, count, first_seen,
         last_seen, sample, advice
```

`severity` is one of `high`, `medium`, `info`.

### 2. Sources

`MacLogSource.events(predicate, since) -> Iterator[Event]`

- Runs `/usr/bin/log show --style ndjson --last <since> --predicate <predicate>`
  by absolute path. (`log` is also a zsh builtin, which matters for anyone
  reproducing a query by hand.)
- Reads stdout line by line, parses each line as JSON, yields an `Event`.
- A line that is not valid JSON, or lacks a timestamp, is skipped and counted.
- A non-zero exit, a missing binary, or a timeout raises `SourceError` with the
  reason. The timeout is 120 seconds per invocation.

One invocation per family: the predicates of that family's enabled rules are
ORed into a single query, and each event is offered to every rule in the family.

Platform selection: on anything other than macOS the tool prints
`logsweep: <platform> is not supported yet` and exits 2.

### 3. Filesystem probes

Plain functions returning lists of `(path, mtime)` or parsed records:

- `recent_files(dirs, since)` — entries whose mtime is inside the window.
  Used for `~/Library/LaunchAgents`, `/Library/LaunchAgents`,
  `/Library/LaunchDaemons`.
- `crash_reports(since)` — files in `~/Library/Logs/DiagnosticReports` and
  `/Library/Logs/DiagnosticReports` inside the window, with the process name
  taken from the filename.

A directory that does not exist is skipped silently. One that exists but cannot
be read marks the dependent rule as "could not check".

### 4. Rules

```
Rule:
  id          e.g. "auth.sudo-failure"
  family      auth | persist | stability | waste
  severity    high | medium | info
  title       one line, shown in the report
  predicate   source-side filter (log rules only)
  match       Event -> subject string, or None
  threshold   optional (count, window_minutes), applied per subject
  advice      one line: what to check next
```

- A rule without a threshold produces one finding per subject, with a count.
- A rule with a threshold produces a finding only for subjects that reach
  `count` matches inside any `window_minutes` span.
- Probe rules are functions that return findings directly.

`RULES` is a module-level list. Adding a rule means adding one entry.

#### v1 rule set

| Family | Rule | Kind | Severity |
|---|---|---|---|
| Auth | sudo authentication failures, 3+ per user in 10 min | log, threshold | high |
| Auth | sshd failed logins, by source address | log | medium |
| Auth | sshd accepted logins, by source address | log | info |
| Auth | failed login/unlock attempts, 5+ in 10 min | log, threshold | medium |
| Persistence | launchd plist modified in window | probe | medium |
| Persistence | crontab changed | probe | medium |
| Persistence | package installed (from `/var/log/install.log`) | probe | info |
| Stability | kernel panic | probe | high |
| Stability | unclean shutdown | log | medium |
| Stability | disk I/O error | log | high |
| Stability | crash reports, per process (1–2 in window) | probe | info |
| Waste | launchd throttling a respawning service | log, threshold | medium |
| Waste | jetsam (out-of-memory) kill, per process | log | medium |
| Waste | same process crashed 3+ times in window | probe | medium |
| Waste | thermal throttling | log | info |

A process with three or more crash reports is reported once, under Waste, not
also under Stability.

**Verification rule.** The predicates and message patterns above are not yet
confirmed. During implementation each rule is written against a real line
captured from this machine. A rule for which no real example can be found or
safely provoked is dropped from v1 and listed in the implementation notes; it
is not shipped on a guessed pattern.

Persistence findings carry the note "hygiene signal": mtime is trivially
backdated, and legitimate updaters (three Zoom plists in the last 30 days here)
will appear.

### 5. Engine

```
for each selected family:
    run the family's log query once, feed events to its rules
    run the family's probe rules
    collect findings, or record the family as "could not check" with a reason
```

A failure in one family does not stop the others.

### 6. Report

```
logsweep — <host> — last 24h — <date>

AUTH
  HIGH    sudo authentication failures    colin    x4   09:12 → 09:15
          sample: <one log line, truncated to terminal width>
          check:  <advice>

PERSISTENCE
  could not check: /Library/LaunchDaemons: permission denied

STABILITY
  no findings

Summary: 1 high, 0 medium, 0 info · 1 family could not be checked · 0 lines skipped
```

- Families in fixed order; findings within a family by severity, then count.
- "no findings" is printed only when the family's sources were all read.
- Sample lines are truncated to the terminal width.
- Colour by severity, via small ANSI helpers; none when not a TTY or with
  `--no-color`.

## Error handling

| Situation | Behaviour |
|---|---|
| `log` exits non-zero or times out | That family reports "could not check: <reason>". |
| Unparseable line | Skipped, counted, shown in the summary. |
| Unreadable directory | Dependent rule reports "could not check". |
| Every family unreadable | Report is printed, exit 2. |
| Bad `--since` or `--family` value | Usage error on stderr, exit 2. |
| Ctrl-C | Child process is terminated, exit 130, no traceback. |

## Testing

- `tools/test_logsweep.py`, `unittest`, run with
  `python3 tools/test_logsweep.py`. `tools/` is repo infrastructure and is never
  stowed. The script is loaded from its extensionless path with `importlib`.
- Fixtures in `tools/fixtures/logsweep/*.ndjson`: real captured lines, one file
  per rule, with usernames, hostnames and addresses scrubbed before commit.
- Covered:
  - each rule's `match` against its fixture, plus a near-miss line that must
    not match;
  - threshold logic (below, at, and spread wider than the window);
  - ndjson parsing, including malformed lines and `<private>` messages;
  - duration parsing for `--since`;
  - probes against a temporary directory with controlled mtimes;
  - report rendering for findings, "no findings" and "could not check";
  - engine behaviour when a source raises `SourceError`.
- `MacLogSource` is exercised with a fake subprocess; one opt-in test runs the
  real `log` binary and is skipped off macOS.

## Documentation

- `CLAUDE.md`: a row in the Scripts table, and a short section recording the
  redaction constraint and the verification rule.
- `README.md`: usage and a sample report.

## Deferred

- Linux backend (`journalctl`, `/var/log/auth.log`), built against fixtures
  captured from a real machine.
- Suppression, once real noise has been observed.
- Live process snapshot and log-volume statistics.

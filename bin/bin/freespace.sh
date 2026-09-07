#!/usr/bin/env bash
#
# freespace.sh - report and reclaim disk space.
#
# Dry run by default: prints what it would remove and how much that is worth.
# Pass -f to actually delete.
#
#   freespace.sh          # report only
#   freespace.sh -f       # reclaim
#
# Knobs (environment):
#   ARCHIVE_DAYS=90       # delete .xcarchive bundles older than this
#   STALE_DAYS=120        # delete node_modules/venv under ~/devel older than this
#   PRUNE_VOLUMES=0       # 1 also passes --volumes to docker system prune
#
# bash, not sh: this uses [[ ]], arrays and pipefail.

set -euo pipefail

DRY_RUN=1
ARCHIVE_DAYS="${ARCHIVE_DAYS:-90}"
STALE_DAYS="${STALE_DAYS:-120}"
PRUNE_VOLUMES="${PRUNE_VOLUMES:-0}"
TOTAL_MB=0

case "${OSTYPE:-}" in darwin*) IS_MAC=1 ;; *) IS_MAC=0 ;; esac

# The header comment above is the help text; stop at the first non-comment line
# so the two cannot drift apart.
usage() {
    awk 'NR > 2 { if ($0 !~ /^#/) exit; sub(/^# ?/, ""); print }' "$0"
    exit "${1:-0}"
}

while [ $# -gt 0 ]; do
    case "$1" in
        -f|--force) DRY_RUN=0 ;;
        -h|--help)  usage 0 ;;
        *)          printf 'unknown option: %s\n\n' "$1" >&2; usage 1 ;;
    esac
    shift
done

# ---------------------------------------------------------------- helpers ---

have()    { command -v "$1" >/dev/null 2>&1; }
section() { printf '\n\033[1m%s\033[0m\n' "$1"; }
note()    { printf '    \033[2m%s\033[0m\n' "$*"; }
skip()    { printf '  \033[2m%-38s %8s\033[0m\n' "$1" "-"; }

# MB -> human
human() {
    awk -v m="$1" 'BEGIN { if (m >= 1024) printf "%.1fG", m/1024; else printf "%dM", m }'
}

# Total size in MB of whichever of the given paths exist.
size_mb() {
    local p; local -a existing=()
    for p in "$@"; do [ -e "$p" ] && existing+=("$p"); done
    if [ ${#existing[@]} -eq 0 ]; then printf '0'; return; fi
    # du exits non-zero on any unreadable entry; with pipefail that would kill
    # the script mid-report, so the partial total is deliberately accepted.
    { du -sxm "${existing[@]}" 2>/dev/null || true; } \
        | awk '{t += $1} END {printf "%d", t + 0}'
}

# reclaim <label> <path...> - measure, report, and delete when forced.
reclaim() {
    local label="$1"; shift
    local p mb; local -a existing=()
    for p in "$@"; do [ -e "$p" ] && existing+=("$p"); done
    if [ ${#existing[@]} -eq 0 ]; then skip "$label"; return; fi

    mb=$(size_mb "${existing[@]}")
    if [ "$mb" -eq 0 ]; then skip "$label"; return; fi

    printf '  %-38s %8s\n' "$label" "$(human "$mb")"
    TOTAL_MB=$(( TOTAL_MB + mb ))
    [ "$DRY_RUN" -eq 0 ] && rm -rf -- "${existing[@]}"
    return 0
}

# run <label> <cmd...> - for tools that clean up better than rm -rf can.
# Space freed this way is not measurable up front, so it misses the total.
run() {
    local label="$1"; shift
    if [ "$DRY_RUN" -eq 1 ]; then
        printf '  %-38s %8s\n' "$label" "?"
        note "$*"
    else
        printf '  %-38s %8s\n' "$label" "running"
        "$@" >/dev/null 2>&1 || note "failed: $*"
    fi
}

free_mb() { df -m "$1" | awk 'NR == 2 {print $4}'; }

# --------------------------------------------------------------- sections ---

xcode_section() {
    [ "$IS_MAC" -eq 1 ] || return 0
    local dev="$HOME/Library/Developer"
    [ -d "$dev" ] || return 0

    section "Xcode"

    # Archives hold the dSYMs used to symbolicate crash reports from shipped
    # builds, so age is the only safe filter.
    local dir="$dev/Xcode/Archives"
    if [ -d "$dir" ]; then
        local mb; local -a old=()
        while IFS= read -r -d '' p; do old+=("$p"); done < <(
            find "$dir" -maxdepth 2 -name '*.xcarchive' -mtime +"$ARCHIVE_DAYS" -print0 2>/dev/null
        )
        if [ ${#old[@]} -eq 0 ]; then
            skip "archives older than ${ARCHIVE_DAYS}d"
        else
            mb=$(size_mb "${old[@]}")
            printf '  %-38s %8s\n' "archives older than ${ARCHIVE_DAYS}d (${#old[@]})" "$(human "$mb")"
            TOTAL_MB=$(( TOTAL_MB + mb ))
            if [ "$DRY_RUN" -eq 0 ]; then
                rm -rf -- "${old[@]}"
                find "$dir" -mindepth 1 -maxdepth 1 -type d -empty -delete 2>/dev/null || true
            fi
        fi
    fi

    reclaim "DerivedData" "$dev/Xcode/DerivedData"
    reclaim "iOS DeviceSupport"  "$dev/Xcode/iOS DeviceSupport"

    if have xcrun; then
        run "unavailable simulators" xcrun simctl delete unavailable
        local sim; sim=$(size_mb "$dev/CoreSimulator/Devices")
        [ "$sim" -gt 0 ] && note "CoreSimulator/Devices is $(human "$sim") total; \
list runtimes with: xcrun simctl runtime list"
    fi
}

docker_section() {
    have docker || return 0
    section "Docker"

    if docker info >/dev/null 2>&1; then
        if [ "$PRUNE_VOLUMES" -eq 1 ]; then
            run "prune (incl. named volumes)" docker system prune -af --volumes
        else
            run "prune images/containers/cache" docker system prune -af
            note "named volumes kept; PRUNE_VOLUMES=1 removes them too"
        fi
    else
        skip "daemon not running"
    fi

    local raw="$HOME/Library/Containers/com.docker.docker/Data/vms/0/data/Docker.raw"
    if [ -f "$raw" ]; then
        note "Docker.raw: $(du -sh "$raw" 2>/dev/null | awk '{print $1}') on disk, \
$(ls -lh "$raw" | awk '{print $5}') apparent (sparse)"
        note "Pruning frees space inside the VM; this host file does not shrink."
        note "To reclaim it: Docker Desktop > Settings > Resources > Disk image size, or"
        note "  docker run --rm --privileged --pid=host alpine \\"
        note "    nsenter -t 1 -m -u -n -i fstrim /var/lib/docker"
    fi
}

cache_section() {
    section "Package and build caches"

    if have brew; then
        run "brew cleanup" brew cleanup -s --prune=all
        run "brew autoremove" brew autoremove
    fi

    reclaim "npm"        "$HOME/.npm/_cacache"
    reclaim "gradle"     "$HOME/.gradle/caches"
    reclaim "deno"       "$HOME/Library/Caches/deno" "$HOME/.cache/deno"
    reclaim "CocoaPods"  "$HOME/Library/Caches/CocoaPods"
    reclaim "yarn"       "$HOME/Library/Caches/Yarn" "$HOME/.cache/yarn"
    reclaim "pnpm store" "$HOME/Library/pnpm/store"

    have uv   && run "uv cache"   uv cache clean
    have pip3 && run "pip cache"  pip3 cache purge
    # go clean -modcache is deliberately absent: it forces a full re-download.
    have go   && run "go build cache" go clean -cache

    return 0
}

devel_section() {
    [ -d "$HOME/devel" ] || return 0
    section "Stale dependency directories (~/devel)"

    # -prune stops find descending into a match, so nested node_modules are not
    # counted twice. Directory mtime only moves when entries are added or
    # removed, so this is a proxy for staleness rather than proof of it.
    local mb; local -a stale=()
    while IFS= read -r -d '' p; do stale+=("$p"); done < <(
        find "$HOME/devel" \
            \( -name node_modules -o -name venv -o -name .venv -o -name env \) \
            -type d -prune -mtime +"$STALE_DAYS" -print0 2>/dev/null
    )

    if [ ${#stale[@]} -eq 0 ]; then
        skip "unused for ${STALE_DAYS}d"
        return 0
    fi

    mb=$(size_mb "${stale[@]}")
    printf '  %-38s %8s\n' "unused for ${STALE_DAYS}d (${#stale[@]} dirs)" "$(human "$mb")"
    TOTAL_MB=$(( TOTAL_MB + mb ))
    [ "$DRY_RUN" -eq 1 ] && printf '%s\n' "${stale[@]}" | sed "s|^$HOME|    ~|"
    [ "$DRY_RUN" -eq 0 ] && rm -rf -- "${stale[@]}"
    return 0
}

macos_section() {
    [ "$IS_MAC" -eq 1 ] || return 0
    section "macOS"

    local -a trash=()
    if [ -d "$HOME/.Trash" ]; then
        while IFS= read -r -d '' p; do trash+=("$p"); done < <(
            find "$HOME/.Trash" -mindepth 1 -maxdepth 1 -print0 2>/dev/null
        )
    fi
    if [ ${#trash[@]} -gt 0 ]; then reclaim "Trash" "${trash[@]}"; else skip "Trash"; fi

    reclaim "user logs" "$HOME/Library/Logs/DiagnosticReports"

    # Local snapshots are the usual explanation for "purgeable" space. Thinning
    # needs sudo, so report rather than escalate.
    if have tmutil; then
        local snaps
        snaps=$(tmutil listlocalsnapshots / 2>/dev/null | grep -c 'com.apple.TimeMachine' || true)
        if [ "${snaps:-0}" -gt 0 ]; then
            printf '  %-38s %8s\n' "Time Machine local snapshots" "$snaps"
            note "reclaim with: sudo tmutil thinlocalsnapshots / 21474836480 4"
        else
            skip "Time Machine local snapshots"
        fi
    fi
}

report_section() {
    section "Largest directories (not touched)"
    { du -sh -x "$HOME"/* "$HOME"/Library/* 2>/dev/null || true; } \
        | sort -h | tail -12 | sed "s|$HOME|~|"

    section "Memory"
    if [ "$IS_MAC" -eq 1 ]; then
        sysctl -n vm.swapusage 2>/dev/null | sed 's/^/    swap: /' || true
        memory_pressure 2>/dev/null | grep -i 'free percentage' | sed 's/^/    /' || true
    else
        free -h | sed 's/^/    /'
    fi
    printf '    top processes by RSS:\n'
    # head closes the pipe early, so sort dies of SIGPIPE (141) under pipefail.
    { ps axo rss,comm | sort -nr | head -5 || true; } \
        | awk '{ printf "      %.1fG  %s\n", $1 / 1048576, $2 }'
}

# ------------------------------------------------------------------- main ---

have figlet && figlet "free your space..."

BEFORE=$(free_mb "$HOME")
if [ "$DRY_RUN" -eq 1 ]; then
    printf '\033[1mDRY RUN\033[0m - nothing will be deleted. Re-run with -f to reclaim.\n'
fi
printf 'Free now: %s\n' "$(human "$BEFORE")"

xcode_section
docker_section
cache_section
devel_section
macos_section
report_section

section "Total"
printf '  %-38s %8s\n' "identified by path" "$(human "$TOTAL_MB")"
note "excludes brew/docker/simulator cleanups, which report '?' above"

if [ "$DRY_RUN" -eq 0 ]; then
    AFTER=$(free_mb "$HOME")
    printf '  %-38s %8s\n' "free before" "$(human "$BEFORE")"
    printf '  %-38s %8s\n' "free after"  "$(human "$AFTER")"
    printf '  %-38s %8s\n' "actually reclaimed" "$(human "$(( AFTER - BEFORE ))")"
fi

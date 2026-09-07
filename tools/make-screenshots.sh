#!/usr/bin/env bash
#
# Regenerate the SVGs in docs/ by running the real tools in a detached tmux
# session and rendering the captured ANSI. No manual screenshotting, and the
# images stay honest -- they are the actual output, not a mock-up.
#
#   ./tools/make-screenshots.sh
#
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DOCS="$REPO/docs"
SOCK=dotfiles-shots
WORK="$(mktemp -d)"
trap 'tmux -L "$SOCK" kill-server 2>/dev/null || true; rm -rf "$WORK"' EXIT

mkdir -p "$DOCS"

# Colours of the currently active theme, so the images match the real thing.
BG='#1a1b26'; FG='#c0caf5'
PAL="$HOME/.config/theme/current/palette.sh"
if [ -f "$PAL" ]; then
    # shellcheck disable=SC1090
    . "$PAL"
    BG="#$BG"; FG="#$FG"
fi

shoot() {  # shoot <name> <cols> <rows> <settle-seconds> <title> <command...>
    local name="$1" cols="$2" rows="$3" settle="$4" title="$5"; shift 5
    tmux -L "$SOCK" kill-server 2>/dev/null || true
    tmux -L "$SOCK" new-session -d -x "$cols" -y "$rows" "$*"
    sleep "$settle"
    tmux -L "$SOCK" capture-pane -p -e -t 0 \
        | python3 "$REPO/tools/ansi2svg.py" --bg "$BG" --fg "$FG" --title "$title" \
        > "$DOCS/$name.svg"
    tmux -L "$SOCK" kill-server 2>/dev/null || true
    printf '  %-22s %s\n' "$name.svg" "$(wc -c < "$DOCS/$name.svg" | tr -d ' ') bytes"
}

# ---------------------------------------------------------------- conflicts --
# A real merge conflict, resolved with the real config.
git init -q "$WORK/conflict" && cd "$WORK/conflict"
git config user.email a@b; git config user.name a
cat > deploy.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

TARGET="staging"
TIMEOUT=30
RETRIES=3

deploy() {
    log "deploying to $TARGET"
    rsync -av ./build/ "$TARGET:/srv/app/"
}
EOF
git add . && git commit -qm base
git checkout -qb feature
sed -i '' 's/staging/production/; s/TIMEOUT=30/TIMEOUT=120/; s/RETRIES=3/RETRIES=5/' deploy.sh
git commit -qam "production"
git checkout -q master 2>/dev/null || git checkout -q main
sed -i '' 's/staging/qa/; s/TIMEOUT=30/TIMEOUT=60/; s/RETRIES=3/RETRIES=10/' deploy.sh
git commit -qam "qa"
git merge feature >/dev/null 2>&1 || true

shoot conflicts 92 20 2.5 "vim — resolving a merge conflict" \
    "cd $WORK/conflict && vim deploy.sh"

# -------------------------------------------------------------------- theme --
shoot theme-swatch 92 16 1.5 "theme — palette preview" \
    "cd $REPO && sh -c '~/bin/theme swatch \$(~/bin/theme current); sleep 30'"

echo "done -> $DOCS"

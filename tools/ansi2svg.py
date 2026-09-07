#!/usr/bin/env python3
"""Render ANSI terminal output (from `tmux capture-pane -e`) as an SVG.

Text-based output on purpose: the result diffs sensibly in git, stays small,
and renders on GitHub without committing binaries.

    tmux capture-pane -p -e | tools/ansi2svg.py --bg '#1a1b26' --fg '#c0caf5' > out.svg
"""
import argparse
import html
import re
import sys

SGR = re.compile(r"\x1b\[([0-9;]*)m")
# Everything except SGR. The final-byte class deliberately omits "m" -- an
# earlier version used [A-Za-z], which swallowed every colour code before it
# could be parsed, and rendered the whole capture in the default colours.
OTHER_ESC = re.compile(r"\x1b\][^\x07\x1b]*(?:\x07|\x1b\\)|\x1b\[[0-9;?]*[A-Za-ln-z]|\x1b[()][A-B0]")

# xterm 16-colour base, used only when a scheme sends indexed colours
BASE16 = [
    "#000000", "#cc0000", "#4e9a06", "#c4a000", "#3465a4", "#75507b", "#06989a", "#d3d7cf",
    "#555753", "#ef2929", "#8ae234", "#fce94f", "#729fcf", "#ad7fa8", "#34e2e2", "#eeeeec",
]


def xterm256(n):
    if n < 16:
        return BASE16[n]
    if n < 232:
        n -= 16
        r, g, b = n // 36, (n % 36) // 6, n % 6
        f = lambda v: 0 if v == 0 else 55 + 40 * v
        return "#%02x%02x%02x" % (f(r), f(g), f(b))
    v = 8 + (n - 232) * 10
    return "#%02x%02x%02x" % (v, v, v)


class Style:
    __slots__ = ("fg", "bg", "bold")

    def __init__(self, fg=None, bg=None, bold=False):
        self.fg, self.bg, self.bold = fg, bg, bold

    def copy(self):
        return Style(self.fg, self.bg, self.bold)

    def key(self):
        return (self.fg, self.bg, self.bold)


def apply_sgr(style, params):
    """Mutate `style` per one SGR escape's parameters."""
    codes = [int(p) if p else 0 for p in params.split(";")] or [0]
    i = 0
    while i < len(codes):
        c = codes[i]
        if c == 0:
            style.fg = style.bg = None
            style.bold = False
        elif c == 1:
            style.bold = True
        elif c == 22:
            style.bold = False
        elif c == 39:
            style.fg = None
        elif c == 49:
            style.bg = None
        elif 30 <= c <= 37:
            style.fg = BASE16[c - 30]
        elif 90 <= c <= 97:
            style.fg = BASE16[c - 90 + 8]
        elif 40 <= c <= 47:
            style.bg = BASE16[c - 40]
        elif 100 <= c <= 107:
            style.bg = BASE16[c - 100 + 8]
        elif c in (38, 48):
            target = "fg" if c == 38 else "bg"
            if i + 1 < len(codes) and codes[i + 1] == 2 and i + 4 < len(codes):
                setattr(style, target, "#%02x%02x%02x" % tuple(codes[i + 2:i + 5]))
                i += 4
            elif i + 1 < len(codes) and codes[i + 1] == 5 and i + 2 < len(codes):
                setattr(style, target, xterm256(codes[i + 2]))
                i += 2
        i += 1
    return style


def parse(text):
    """-> list of lines, each a list of (char, Style)."""
    lines = []
    style = Style()
    for raw in text.split("\n"):
        raw = OTHER_ESC.sub("", raw)
        cells, pos = [], 0
        for m in SGR.finditer(raw):
            for ch in raw[pos:m.start()]:
                cells.append((ch, style.copy()))
            style = apply_sgr(style, m.group(1))
            pos = m.end()
        for ch in raw[pos:]:
            cells.append((ch, style.copy()))
        lines.append(cells)
    return lines


def render(lines, bg, fg, font_size, char_w, line_h, pad, title):
    cols = max((len(l) for l in lines), default=0)
    top = pad + (28 if title else 0)
    w = cols * char_w + pad * 2
    h = len(lines) * line_h + top + pad

    out = [
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{w:.0f}" height="{h:.0f}" '
        f'viewBox="0 0 {w:.0f} {h:.0f}" font-family="ui-monospace,SFMono-Regular,'
        f'Menlo,Consolas,monospace" font-size="{font_size}">',
        f'<rect width="{w:.0f}" height="{h:.0f}" rx="8" fill="{bg}"/>',
    ]
    if title:
        for i, c in enumerate(("#ff5f57", "#febc2e", "#28c840")):
            out.append(f'<circle cx="{pad + 8 + i * 18}" cy="{pad + 6}" r="6" fill="{c}"/>')
        out.append(
            f'<text x="{w/2:.0f}" y="{pad + 11}" fill="{fg}" opacity="0.6" '
            f'text-anchor="middle" font-size="{font_size - 2}">{html.escape(title)}</text>'
        )

    for row, cells in enumerate(lines):
        y = top + row * line_h
        # background runs first, so text always paints on top
        col = 0
        while col < len(cells):
            style = cells[col][1]
            run = col
            while run < len(cells) and cells[run][1].bg == style.bg:
                run += 1
            if style.bg:
                out.append(
                    f'<rect x="{pad + col * char_w:.1f}" y="{y:.1f}" '
                    f'width="{(run - col) * char_w:.1f}" height="{line_h:.1f}" fill="{style.bg}"/>'
                )
            col = run
        # then text runs
        col = 0
        while col < len(cells):
            style = cells[col][1]
            run = col
            while run < len(cells) and cells[run][1].key() == style.key():
                run += 1
            text = "".join(c for c, _ in cells[col:run])
            if text.strip():
                attrs = f' font-weight="bold"' if style.bold else ""
                out.append(
                    f'<text x="{pad + col * char_w:.1f}" y="{y + line_h - 4:.1f}" '
                    f'fill="{style.fg or fg}"{attrs} xml:space="preserve">'
                    f'{html.escape(text)}</text>'
                )
            col = run

    out.append("</svg>")
    return "\n".join(out)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--bg", default="#1a1b26")
    ap.add_argument("--fg", default="#c0caf5")
    ap.add_argument("--font-size", type=float, default=13)
    ap.add_argument("--char-width", type=float, default=7.8)
    ap.add_argument("--line-height", type=float, default=17)
    ap.add_argument("--pad", type=float, default=14)
    ap.add_argument("--title", default="")
    a = ap.parse_args()

    text = sys.stdin.read().rstrip("\n")
    lines = parse(text)
    while lines and not any(c.strip() for c, _ in lines[-1]):
        lines.pop()
    sys.stdout.write(render(lines, a.bg, a.fg, a.font_size,
                            a.char_width, a.line_height, a.pad, a.title))


if __name__ == "__main__":
    main()

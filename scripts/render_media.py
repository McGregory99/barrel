#!/usr/bin/env python3
"""Render the README and landing-page animations as self-contained animated SVGs.

- docs/media/casts/<name>.txt  ->  docs/media/cast-<name>.svg
  A cast replays recorded terminal output: "$ " lines are typed commands, other lines are
  output, "# " lines are comments (skipped) and a trailing "  @45 s" marks how long the
  command really took (shown as a muted note; the animation itself is compressed).
- docs/media/how-it-works-{light,dark}.svg: the architecture diagram.

The SVGs use only CSS and SMIL animation, so they play inside GitHub's <img> rendering.

usage: render_media.py
"""
import html
import pathlib
import re

ROOT = pathlib.Path(__file__).resolve().parent.parent
MEDIA = ROOT / "docs" / "media"

MONO = "ui-monospace, 'SF Mono', SFMono-Regular, Menlo, Consolas, monospace"
SANS = "-apple-system, BlinkMacSystemFont, 'Inter', 'Segoe UI', Helvetica, Arial, sans-serif"

# Terminal palette (one dark terminal reads well on both GitHub themes).
TERM = {
    "bg": "#101014", "edge": "#26262c", "title": "#8e8e99", "text": "#f4f4f5",
    "muted": "#8e8e99", "prompt": "#e07a45", "ok": "#7cc79a", "note": "#5c5c66",
}

COLS = 76         # terminal width in characters; longer lines wrap like a real terminal
CHAR_W = 7.8      # advance of a 13px monospace glyph
LINE_H = 21
PAD_X = 22
TOP = 52          # first baseline below the title bar
TYPE_S = 0.034    # seconds per typed character
LINE_S = 0.07     # seconds between output lines
HOLD_S = 3.2      # pause on the finished screen before the loop restarts


def esc(text):
    return html.escape(text, quote=False)


def wrap(text, first_width):
    rows, width = [], first_width
    while len(text) > width:
        rows.append(text[:width])
        text, width = text[width:], COLS
    return rows + [text]


def parse_cast(path):
    """Returns screen rows: 'cmd' (typed after a prompt), 'cont' (typed, wrapped) and 'out'."""
    rows = []
    for raw in path.read_text().splitlines():
        if raw.startswith("# "):
            continue
        note = None
        match = re.search(r"\s{2}@(.+)$", raw)
        if match:
            note, raw = match.group(1), raw[:match.start()]
        raw = raw.expandtabs(8)
        if raw.startswith("$ "):
            parts = wrap(raw[2:], COLS - 2)
            rows.append({"kind": "cmd", "text": parts[0], "note": None})
            rows += [{"kind": "cont", "text": part, "note": None} for part in parts[1:]]
        else:
            parts = wrap(raw, COLS)
            rows += [{"kind": "out", "text": part, "note": None, "ok": False} for part in parts]
            rows[-len(parts)]["ok"] = bool(re.match(r"^(Installed|Created|'.*' now uses)", raw))
            rows[-1]["note"] = note
    return rows


def appear(name, total, start):
    """Keyframes: hidden until `start`, visible until the loop fades out."""
    a = start / total * 100
    b = min(a + 0.01, 100)
    fade = (total - 0.4) / total * 100
    return f"@keyframes {name}{{0%,{a:.3f}%{{opacity:0}}{b:.3f}%,{fade:.3f}%{{opacity:1}}100%{{opacity:0}}}}"


def render_cast(name, rows):
    width = round(PAD_X * 2 + COLS * CHAR_W)
    height = TOP + LINE_H * len(rows) + 22
    css, body = [], []
    t = 0.6

    for i, row in enumerate(rows):
        y = TOP + i * LINE_H
        if row["kind"] in ("cmd", "cont"):
            if row["kind"] == "cmd" and i > 0:
                t += 0.55
            typed = len(row["text"])
            end = t + typed * TYPE_S
            x0 = PAD_X + (2 * CHAR_W if row["kind"] == "cmd" else 0)
            prompt = f'<text x="{PAD_X}" y="{y}" class="p">❯</text>' if row["kind"] == "cmd" else ""
            # The command is revealed by sliding a background-coloured cover (led by a cursor) off it.
            body.append(
                f'<g class="l{i}">{prompt}'
                f'<text x="{x0:.1f}" y="{y}" class="{"n" if row["text"].startswith("#") else "c"}" xml:space="preserve">{esc(row["text"])}</text>'
                f'<g class="k{i}"><rect x="{x0:.1f}" y="{y - 15}" width="{CHAR_W:.1f}" height="19" class="cur"/>'
                f'<rect x="{x0 + CHAR_W:.1f}" y="{y - 15}" width="{width}" height="19" class="bg"/></g></g>')
            row.update(start=t, end=end, typed=typed)
            t = end if i + 1 < len(rows) and rows[i + 1]["kind"] == "cont" else end + 0.25
        else:
            t += LINE_S
            text = esc(row["text"]) or " "
            cls = "ok" if row["ok"] else "o"
            body.append(f'<g class="l{i}"><text x="{PAD_X}" y="{y}" class="{cls}" xml:space="preserve">{text}</text>')
            if row["note"]:
                nx = PAD_X + (len(row["text"]) + 2) * CHAR_W
                body.append(f'<text x="{nx:.1f}" y="{y}" class="n">· {esc(row["note"])}</text>')
            body.append("</g>")
            row.update(start=t)
            if row["note"]:
                t += 0.9  # let a slow step read as slow

    total = t + HOLD_S
    for i, row in enumerate(rows):
        css.append(appear(f"v{i}", total, row["start"]))
        css.append(f".l{i}{{animation:v{i} {total:.2f}s infinite}}")
        if row["kind"] in ("cmd", "cont"):
            shift = row["typed"] * CHAR_W
            wraps = i + 1 < len(rows) and rows[i + 1]["kind"] == "cont"
            hide = row["end"] + (0.02 if wraps else 0.2)  # hand the cursor straight to a wrapped row
            css.append(
                f"@keyframes t{i}{{0%,{row['start'] / total * 100:.3f}%"
                f"{{transform:translateX(0);opacity:1;animation-timing-function:steps({row['typed']},end)}}"
                f"{row['end'] / total * 100:.3f}%{{transform:translateX({shift:.1f}px);opacity:1}}"
                f"{hide / total * 100:.3f}%,100%{{transform:translateX({shift:.1f}px);opacity:0}}}}")
            css.append(f".k{i}{{animation:t{i} {total:.2f}s infinite}}")

    style = f"""
text{{font:13px {MONO};white-space:pre}}
.p{{fill:{TERM['prompt']}}} .c{{fill:{TERM['text']}}} .o{{fill:{TERM['muted']}}} .ok{{fill:{TERM['ok']}}}
.n{{fill:{TERM['note']}}} .bg{{fill:{TERM['bg']}}} .cur{{fill:{TERM['text']};opacity:.85}}
.t{{font:600 12px {SANS};fill:{TERM['title']}}}
""" + "\n".join(css)

    return f"""<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" viewBox="0 0 {width} {height}" role="img" aria-label="Terminal: {esc(name)}">
<style>{style}</style>
<rect width="{width}" height="{height}" rx="14" fill="{TERM['bg']}" stroke="{TERM['edge']}"/>
<circle cx="22" cy="20" r="6" fill="#ff5f57"/><circle cx="42" cy="20" r="6" fill="#febc2e"/><circle cx="62" cy="20" r="6" fill="#28c840"/>
<text x="{width / 2}" y="24" text-anchor="middle" class="t">barrel — zsh</text>
{chr(10).join(body)}
</svg>
"""


THEMES = {
    "light": {"ink": "#1c1c1e", "muted": "#595d63", "line": "#d9d8d0", "card": "#ffffff",
              "soft": "#f7f6f2", "accent": "#b74c1b", "blue": "#176fd6"},
    "dark": {"ink": "#f4f4f5", "muted": "#a1a1aa", "line": "#34343c", "card": "#16161c",
             "soft": "#101014", "accent": "#e07a45", "blue": "#5aa2f5"},
}


def render_how_it_works(theme):
    c = THEMES[theme]
    w, h = 960, 360

    def node(x, y, title, subtitle, accent=False):
        stroke = c["accent"] if accent else c["line"]
        return (f'<g><rect x="{x}" y="{y}" width="230" height="76" rx="14" fill="{c["card"]}" stroke="{stroke}"/>'
                f'<text x="{x + 20}" y="{y + 32}" class="h">{esc(title)}</text>'
                f'<text x="{x + 20}" y="{y + 55}" class="s">{esc(subtitle)}</text></g>')

    # Two flows leave the game: system calls through Wine, Direct3D through DXVK/DXMT.
    sys_path = "M 236 190 C 290 190, 290 98, 344 98 L 574 98 L 650 98"
    gfx_path = "M 236 190 C 290 190, 290 282, 344 282 L 574 282 L 650 282"
    flows = []
    for pid, d, color, label, ly in (
        ("a", sys_path, c["accent"], "CreateWindowEx · ReadFile · XInput", 44),
        ("b", gfx_path, c["blue"], "ID3D11DeviceContext::Draw", 346),
    ):
        flows.append(f'<path id="{pid}" d="{d}" fill="none" stroke="{c["line"]}" stroke-width="2"/>')
        flows.append(f'<path d="{d}" fill="none" stroke="{color}" stroke-width="2" class="flow"/>')
        for k, delay in enumerate((0, 0.8, 1.6)):
            flows.append(
                f'<circle r="4" fill="{color}"><animateMotion dur="2.4s" begin="{delay}s" repeatCount="indefinite"'
                f' keyPoints="0;1" keyTimes="0;1" calcMode="linear"><mpath href="#{pid}"/></animateMotion>'
                f'<animate attributeName="opacity" values="0;1;1;0" keyTimes="0;.1;.85;1" dur="2.4s"'
                f' begin="{delay}s" repeatCount="indefinite"/></circle>')
        flows.append(f'<text x="360" y="{ly}" class="m">{esc(label)}</text>')

    bottle = (f'<rect x="20" y="132" width="230" height="116" rx="18" fill="none" stroke="{c["accent"]}"'
              f' stroke-dasharray="5 5" opacity=".6"/>'
              f'<text x="36" y="236" class="e">BOTTLE · C: DRIVE · REGISTRY</text>')
    game = (f'<rect x="36" y="150" width="200" height="66" rx="12" fill="{c["card"]}" stroke="{c["line"]}"/>'
            f'<rect x="54" y="168" width="13" height="13" rx="2" fill="{c["blue"]}"/>'
            f'<rect x="70" y="168" width="13" height="13" rx="2" fill="{c["blue"]}" opacity=".7"/>'
            f'<rect x="54" y="184" width="13" height="13" rx="2" fill="{c["blue"]}" opacity=".7"/>'
            f'<rect x="70" y="184" width="13" height="13" rx="2" fill="{c["blue"]}" opacity=".45"/>'
            f'<text x="98" y="181" class="h">Game.exe</text><text x="98" y="201" class="s">Windows x64</text>')

    nodes = [
        node(344, 60, "Wine 11", "Windows API → macOS", accent=True),
        node(650, 60, "macOS", "windows · files · input · audio"),
        node(344, 244, "DXVK  ·  DXMT", "Direct3D → Vulkan / Metal", accent=True),
        node(650, 244, "Metal", "Apple GPU"),
    ]
    style = f"""
.h{{font:650 17px {SANS};fill:{c['ink']};letter-spacing:-.02em}}
.s{{font:13px {SANS};fill:{c['muted']}}}
.m{{font:12px {MONO};fill:{c['muted']}}}
.e{{font:600 10px {SANS};fill:{c['accent']};letter-spacing:.08em}}
.flow{{stroke-dasharray:6 14;animation:f 1.2s linear infinite;opacity:.55}}
@keyframes f{{to{{stroke-dashoffset:-20}}}}
"""
    return f"""<svg xmlns="http://www.w3.org/2000/svg" width="{w}" height="{h}" viewBox="0 0 {w} {h}" role="img" aria-label="How barrel runs a Windows game: system calls go through Wine to macOS, Direct3D goes through DXVK or DXMT to Metal">
<style>{style}</style>
{chr(10).join(flows)}
{bottle}
{game}
{chr(10).join(nodes)}
</svg>
"""


def main():
    for cast in sorted((MEDIA / "casts").glob("*.txt")):
        out = MEDIA / f"cast-{cast.stem}.svg"
        out.write_text(render_cast(cast.stem, parse_cast(cast)))
        print("wrote", out.relative_to(ROOT))
    for theme in THEMES:
        out = MEDIA / f"how-it-works-{theme}.svg"
        out.write_text(render_how_it_works(theme))
        print("wrote", out.relative_to(ROOT))


if __name__ == "__main__":
    main()

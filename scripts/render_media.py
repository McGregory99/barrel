#!/usr/bin/env python3
"""Render the README and landing-page animations as self-contained animated SVGs.

- docs/media/casts/<name>.txt  ->  docs/media/cast-<name>.svg
  A cast replays recorded terminal output: "$ " lines are typed commands, other lines are
  output, "# " lines are comments (skipped) and a trailing "  @45 s" marks how long the
  command really took (shown as a muted note; the animation itself is compressed).
- docs/media/how-it-works-{light,dark}.svg: the architecture diagram.
- docs/media/dock-demo.svg: "Add to Dock" puts a game's icon in the Dock (icons from docs/media/logos,
  embedded because an SVG shown as an image cannot load other files).
- docs/media/graphics-demo.svg: a game's Graphics menu opens, the pointer moves over each engine and
  picks Automatic.
- docs/media/steps-demo.svg: the four steps to play a Steam game (Open Steam, install, Refresh, Play).

The SVGs use only CSS and SMIL animation, so they play inside GitHub's <img> rendering.

usage: render_media.py
"""
import base64
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


def data_uri(path):
    kind = "image/svg+xml" if path.suffix == ".svg" else "image/png"
    return f"data:{kind};base64,{base64.b64encode(path.read_bytes()).decode()}"


def render_dock_demo():
    logos = MEDIA / "logos"
    game = data_uri(logos / "stonewards.png")
    docked = [data_uri(logos / n) for n in ("barrel.svg", "steam.png", "cs2.png", "tf2.png", "warframe.png")]
    dur = "6s"
    size, gap, pad = 54, 8, 12
    def row(count):  # Dock x and width for `count` icons, centred at x=320
        width = 2 * pad + count * size + (count - 1) * gap
        return 320 - width // 2, width
    (x0, w0), (x1, w1) = row(len(docked)), row(len(docked) + 1)
    icons = []
    for i, href in enumerate(docked):
        a, b = x0 + pad + i * (size + gap), x1 + pad + i * (size + gap)
        move = f'values="{a};{a};{b};{b};{a}" keyTimes="0;.45;.6;.94;1" dur="{dur}" repeatCount="indefinite"'
        icons.append(f'<image y="318" width="{size}" height="{size}" href="{href}"><animate attributeName="x" {move}/></image>')
        if i == 1:  # Steam is running
            icons.append(f'<circle cy="379" r="2.2" fill="#3a3a3e"><animate attributeName="cx" '
                         f'values="{a + 27};{a + 27};{b + 27};{b + 27};{a + 27}" keyTimes="0;.45;.6;.94;1" dur="{dur}" repeatCount="indefinite"/></circle>')
    slot = x1 + pad + len(docked) * (size + gap)
    icons = "\n".join(icons)
    # One 6-second loop: the cursor clicks "Add to Dock", the icon flies into the Dock, the Dock makes room.
    return f"""<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="640" height="400" viewBox="0 0 640 400" role="img" aria-label="Clicking Add to Dock on Stonewards puts its icon in the macOS Dock">
<defs>
  <linearGradient id="desk" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#f3d9c4"/><stop offset=".55" stop-color="#e9c2b5"/><stop offset="1" stop-color="#c9b6d6"/></linearGradient>
  <filter id="shadow" x="-20%" y="-20%" width="140%" height="160%"><feDropShadow dx="0" dy="8" stdDeviation="10" flood-opacity=".18"/></filter>
  <clipPath id="round"><rect width="640" height="400" rx="18"/></clipPath>
</defs>
<style>
text{{font-family:{SANS}}}
.t{{font-size:17px;font-weight:650;fill:#1c1c1e}} .ok{{font-size:12px;fill:#2f9a55}} .b{{font-size:13px;font-weight:550;fill:#1c1c1e}}
</style>
<g clip-path="url(#round)">
<rect width="640" height="400" fill="url(#desk)"/>
<g filter="url(#shadow)">
  <rect x="120" y="54" width="400" height="118" rx="16" fill="#fff" fill-opacity=".92"/>
</g>
<image x="142" y="76" width="64" height="64" href="{game}"/>
<text x="222" y="102" class="t">Stonewards</text>
<circle cx="228" cy="121" r="5.5" fill="#2f9a55"/><path d="M225.4 121l1.8 1.8 3.4-3.6" fill="none" stroke="#fff" stroke-width="1.6" stroke-linecap="round"/>
<text x="239" y="125" class="ok">Tested: works</text>
<g>
  <rect x="380" y="92" width="118" height="36" rx="18" fill="#ececee">
    <animate attributeName="fill" values="#ececee;#ececee;#cfcfd4;#ececee;#ececee" keyTimes="0;.3;.33;.37;1" dur="{dur}" repeatCount="indefinite"/>
  </rect>
  <text x="439" y="115" text-anchor="middle" class="b">Add to Dock</text>
</g>
<!-- Dock: grows to make room for the new icon -->
<g filter="url(#shadow)">
  <rect y="306" height="78" rx="22" fill="#fff" fill-opacity=".55" stroke="#fff" stroke-opacity=".7">
    <animate attributeName="x" values="{x0};{x0};{x1};{x1};{x0}" keyTimes="0;.45;.6;.94;1" dur="{dur}" repeatCount="indefinite"/>
    <animate attributeName="width" values="{w0};{w0};{w1};{w1};{w0}" keyTimes="0;.45;.6;.94;1" dur="{dur}" repeatCount="indefinite"/>
  </rect>
</g>
{icons}
<!-- The game's icon flies from the card into the new slot -->
<image width="64" height="64" href="{game}" opacity="0">
  <animate attributeName="opacity" values="0;0;1;1;1;0" keyTimes="0;.33;.34;.92;.97;1" dur="{dur}" repeatCount="indefinite"/>
  <animate attributeName="x" values="142;142;142;{slot};{slot};{slot}" keyTimes="0;.33;.36;.6;.97;1" dur="{dur}" repeatCount="indefinite" calcMode="spline" keySplines="0 0 1 1;0 0 1 1;.4 0 .2 1;0 0 1 1;0 0 1 1"/>
  <animate attributeName="y" values="76;76;60;318;318;318" keyTimes="0;.33;.38;.6;.97;1" dur="{dur}" repeatCount="indefinite" calcMode="spline" keySplines="0 0 1 1;.2 0 .6 1;.5 0 .9 1;0 0 1 1;0 0 1 1"/>
  <animate attributeName="width" values="64;64;64;54;54;54" keyTimes="0;.33;.36;.6;.97;1" dur="{dur}" repeatCount="indefinite"/>
  <animate attributeName="height" values="64;64;64;54;54;54" keyTimes="0;.33;.36;.6;.97;1" dur="{dur}" repeatCount="indefinite"/>
</image>
<!-- Cursor -->
<g>
  <path d="M0 0 L0 22 L6 16 L10 26 L14 24 L10 14 L18 14 Z" fill="#1c1c1e" stroke="#fff" stroke-width="1.5" stroke-linejoin="round"/>
  <animateTransform attributeName="transform" type="translate" values="560,250;560,250;452,116;452,116;600,230;560,250" keyTimes="0;.08;.28;.4;.7;1" dur="{dur}" repeatCount="indefinite" calcMode="spline" keySplines="0 0 1 1;.4 0 .2 1;0 0 1 1;.4 0 .2 1;0 0 1 1"/>
</g>
</g>
</svg>
"""


def render_graphics_demo():
    game = data_uri(MEDIA / "logos" / "stonewards.png")
    dur = "8s"
    rep = f'dur="{dur}" repeatCount="indefinite"'
    # Menu rows: (label, vertical centre); the player had picked DXMT before the loop starts.
    rows = [("Automatic", 288), ("DXVK", 334), ("DXMT", 368), ("wined3d (OpenGL)", 402)]
    items = "\n".join(f'  <text x="270" y="{y + 6}" class="m">{label}</text>' for label, y in rows)
    hover = [334, 368, 402, 288]  # the order the pointer visits them
    hy = ";".join(str(y - 16) for y in hover[:1] + hover)
    # One 8-second loop: open the menu, hover DXVK, DXMT and wined3d, choose Automatic, menu closes.
    return f"""<svg xmlns="http://www.w3.org/2000/svg" width="680" height="440" viewBox="20 30 680 440" role="img" aria-label="The pointer opens a game's Graphics menu, moves over DXVK, DXMT and wined3d, and chooses Automatic">
<defs>
  <filter id="card" x="-20%" y="-20%" width="140%" height="160%"><feDropShadow dx="0" dy="1" stdDeviation="1.5" flood-opacity=".06"/><feDropShadow dx="0" dy="18" stdDeviation="22" flood-opacity=".12"/></filter>
  <filter id="menu" x="-20%" y="-20%" width="140%" height="150%"><feDropShadow dx="0" dy="10" stdDeviation="12" flood-opacity=".16"/></filter>
</defs>
<style>
text{{font-family:{SANS}}}
.t{{font-size:24px;font-weight:650;fill:#1c1c1e}} .ok{{font-size:16px;font-weight:500;fill:#2f9a55}}
.l{{font-size:19px;fill:#3a3a3e}} .p{{font-size:18px;font-weight:500;fill:#1c1c1e}} .m{{font-size:18px;fill:#1c1c1e}}
.btn{{font-size:18px;font-weight:550}}
</style>
<rect x="70" y="70" width="580" height="290" rx="22" fill="#fff" filter="url(#card)"/>
<image x="100" y="100" width="96" height="96" href="{game}"/>
<text x="220" y="140" class="t">Stonewards</text>
<circle cx="228" cy="167" r="8" fill="#2f9a55"/><path d="M224.2 167l2.6 2.6 5-5.2" fill="none" stroke="#fff" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/>
<text x="243" y="173" class="ok">Tested: works</text>
<text x="100" y="248" class="l">Graphics</text>
<!-- The pop-up button: the player's DXMT, then Automatic once chosen -->
<g>
  <animate attributeName="opacity" values="1;1;0;0;1" keyTimes="0;.755;.756;.97;1" {rep}/>
  <rect x="200" y="224" width="112" height="34" rx="8" fill="#e2e2e6">
    <animate attributeName="fill" values="#e2e2e6;#e2e2e6;#cfcfd5;#cfcfd5;#e2e2e6" keyTimes="0;.22;.23;.755;1" calcMode="discrete" {rep}/>
  </rect>
  <text x="216" y="247" class="p">DXMT</text>
  <path d="M287 238l5 5 5-5" fill="none" stroke="#1c1c1e" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/>
</g>
<g opacity="0">
  <animate attributeName="opacity" values="0;0;1;1;0" keyTimes="0;.755;.756;.97;1" {rep}/>
  <rect x="200" y="224" width="226" height="34" rx="8" fill="#e2e2e6"/>
  <text x="216" y="247" class="p">Automatic · DXVK</text>
  <path d="M401 238l5 5 5-5" fill="none" stroke="#1c1c1e" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/>
</g>
<rect x="100" y="286" width="330" height="48" rx="24" fill="#0a7cff"/>
<path d="M243 299v22l17-11z" fill="#fff"/><text x="268" y="317" class="btn" fill="#fff">Play</text>
<rect x="446" y="286" width="174" height="48" rx="24" fill="#e2e2e6"/>
<text x="533" y="317" text-anchor="middle" class="btn" fill="#1c1c1e">Add to Dock</text>
<!-- The menu -->
<g opacity="0">
  <animate attributeName="opacity" values="0;1;0" keyTimes="0;.255;.755" calcMode="discrete" {rep}/>
  <rect x="200" y="262" width="262" height="160" rx="12" fill="#fbfbfc" stroke="#000" stroke-opacity=".08" filter="url(#menu)"/>
  <rect x="206" width="250" height="32" rx="7" fill="#0a7cff" fill-opacity=".14" opacity="0">
    <animate attributeName="y" values="{hy}" keyTimes="0;.34;.44;.54;.68" calcMode="discrete" {rep}/>
    <animate attributeName="opacity" values="0;1;.4;1;0" keyTimes="0;.34;.735;.745;.755" calcMode="discrete" {rep}/>
  </rect>
  <line x1="220" y1="312" x2="442" y2="312" stroke="#000" stroke-opacity=".1"/>
  <path d="M249 369l4 4 8-9" fill="none" stroke="#1c1c1e" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/>
{items}
</g>
<!-- Pointer -->
<g>
  <path d="M0 0 L0 22 L6 16 L10 26 L14 24 L10 14 L18 14 Z" fill="#1c1c1e" stroke="#fff" stroke-width="1.5" stroke-linejoin="round"/>
  <animateTransform attributeName="transform" type="translate" values="600,430;600,430;262,236;262,236;330,328;330,328;318,362;318,362;340,396;340,396;300,282;300,282;600,430;600,430" keyTimes="0;.08;.21;.28;.34;.40;.44;.50;.54;.60;.68;.78;.92;1" {rep} calcMode="spline" keySplines="0 0 1 1;.4 0 .2 1;0 0 1 1;.4 0 .2 1;0 0 1 1;.4 0 .2 1;0 0 1 1;.4 0 .2 1;0 0 1 1;.4 0 .2 1;0 0 1 1;.4 0 .2 1;0 0 1 1"/>
</g>
</svg>
"""


def render_steps_demo():
    game = data_uri(MEDIA / "logos" / "stonewards.png")
    T = 16.0  # loop length in seconds
    rep = f'dur="{T:g}s" repeatCount="indefinite"'
    ease = ".45 0 .25 1"

    def frac(t):
        return f"{t / T:.4f}".rstrip("0").rstrip(".") or "0"

    def anim(attr, keys, mode="spline", kind=None):
        """Keyframes as (seconds, value); held before the first and after the last, so keyTimes run 0..1."""
        keys = list(keys)
        if keys[0][0] > 0:
            keys.insert(0, (0, keys[0][1]))
        if keys[-1][0] < T:
            keys.append((T, keys[-1][1]))
        vals = ";".join(str(v) for _, v in keys)
        times = ";".join(frac(t) for t, _ in keys)
        timing = f'values="{vals}" keyTimes="{times}" {rep}'
        if mode == "spline":
            splines = ";".join("0 0 1 1" if str(a[1]) == str(b[1]) else ease for a, b in zip(keys, keys[1:]))
            timing += f' calcMode="spline" keySplines="{splines}"'
        elif mode == "discrete":
            timing += ' calcMode="discrete"'
        if kind:
            return f'<animateTransform attributeName="transform" type="{kind}" {timing}/>'
        return f'<animate attributeName="{attr}" {timing}/>'

    def fade(*keys):  # opacity keyframes
        return anim("opacity", keys)

    def press(t, dark=.22):  # a click darkens the target for a quarter second
        return fade((t - .01, 0), (t, dark), (t + .25, 0))

    def ripple(x, y, t, color):  # a ring spreads from the click point
        return (f'<circle cx="{x}" cy="{y}" r="4" fill="none" stroke="{color}" stroke-width="2" opacity="0">'
                f'{anim("r", [(t, 4), (t + .5, 24)], mode="linear")}{fade((t - .01, 0), (t, .7), (t + .5, 0))}</circle>')

    # Scenes: 1 Open Steam, 2 install the game in Steam, 3 Refresh, 4 Play (start times, then the loop's end).
    bounds = (0, 2.2, 7.5, 10.5, 16)
    labels = ("Open Steam", "Install the game", "Refresh", "Play")
    seg_w, gap = 141, 12
    steps = []
    for i, label in enumerate(labels):
        x0 = 40 + i * (seg_w + gap)
        a, b = bounds[i], bounds[i + 1]
        if i == 0:
            on = fade((b - .15, 1), (b + .15, 0), (15.6, 0), (15.95, 1))
        elif i == 3:
            on = fade((a - .15, 0), (a + .15, 1), (15.6, 1), (15.95, 0))
        else:
            on = fade((a - .15, 0), (a + .15, 1), (b - .15, 1), (b + .15, 0))
        fill = anim("width", [(a, 0), (min(b, 15.6), seg_w)], mode="linear")
        steps.append(f"""<g transform="translate({x0},0)">
  <circle cx="10" cy="25" r="10" fill="#fffdf8" stroke="#17213d" stroke-opacity=".14"/>
  <text x="10" y="29.5" text-anchor="middle" class="n" fill="#4b546a">{i + 1}</text>
  <text x="28" y="30" class="sl" fill="#4b546a">{label}</text>
  <g opacity="{1 if i == 0 else 0}">{on}
    <circle cx="10" cy="25" r="10" fill="#2c4a9a"/>
    <text x="10" y="29.5" text-anchor="middle" class="n" fill="#fff">{i + 1}</text>
    <text x="28" y="30" class="sl" fill="#17213d">{label}</text>
  </g>
  <rect y="42" width="{seg_w}" height="4" rx="2" fill="#2c4a9a" fill-opacity=".12"/>
  <rect y="42" width="0" height="4" rx="2" fill="#2c4a9a">{fill}{fade((15.6, 1), (15.95, 0))}</rect>
</g>""")
    steps = "\n".join(steps)

    # Clicks (seconds) and where the pointer's tip lands.
    c_open, c_install, c_refresh, c_play = 1.6, 3.6, 8.6, 11.8
    rest, open_btn, install, aside, refresh, play = "604,406", "566,86", "335,256", "590,350", "478,86", "325,240"
    pointer = anim(None, [(.3, rest), (1.45, open_btn), (2.5, open_btn), (3.45, install), (3.9, install),
                          (4.7, aside), (7.4, aside), (8.45, refresh), (10.7, refresh), (11.65, play),
                          (12.2, play), (13.1, rest)], kind="translate")
    squeeze = []
    for t in (c_open, c_install, c_refresh, c_play):
        squeeze += [(t - .08, 1), (t, .82), (t + .15, 1)]
    squeeze = anim(None, squeeze, kind="scale")

    # Steam's download: the bar fills between these times and a percentage counts up in 5% steps.
    d0, d1 = 3.9, 6.3
    pct = []
    for k in range(21):
        t0 = d0 + k * (d1 - d0) / 20
        keys = [(0, 0), (t0, 1)] + ([(d0 + (k + 1) * (d1 - d0) / 20, 0)] if k < 20 else [])
        pct.append(f'<text x="580" y="300" text-anchor="end" class="st" opacity="0">{k * 5}%{anim("opacity", keys, mode="discrete")}</text>')
    pct = "\n    ".join(pct)

    return f"""<svg xmlns="http://www.w3.org/2000/svg" width="680" height="440" viewBox="0 0 680 440" role="img" aria-label="Four steps: Barrel's Open Steam button opens Steam, the game installs, Refresh adds it to Barrel's library and Play starts it">
<defs>
  <linearGradient id="desk" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#f8f4ea"/><stop offset=".5" stop-color="#f1efe8"/><stop offset="1" stop-color="#e3e9f4"/></linearGradient>
  <filter id="shadow" x="-20%" y="-20%" width="140%" height="160%"><feDropShadow dx="0" dy="10" stdDeviation="12" flood-opacity=".2"/></filter>
  <clipPath id="round"><rect width="680" height="440" rx="18"/></clipPath>
  <clipPath id="win"><rect x="40" y="60" width="600" height="340" rx="14"/></clipPath>
</defs>
<style>
text{{font-family:{SANS}}}
.n{{font-size:12px;font-weight:650}} .sl{{font-size:13px;font-weight:600}} .s{{font-size:11px;font-weight:600;fill:#9a9aa0}} .side{{font-size:14px;fill:#1c1c1e}}
.h{{font-size:16px;font-weight:650;fill:#1c1c1e}} .tb{{font-size:13px;font-weight:550;fill:#fff}} .empty{{font-size:15px;fill:#8e8e93}}
.g{{font-size:14px;font-weight:650;fill:#1c1c1e}} .ok{{font-size:11px;fill:#2f9a55}} .l{{font-size:12px;fill:#3a3a3e}} .pop{{font-size:11px;fill:#1c1c1e}}
.btn{{font-size:12px;font-weight:550}} .st{{font-size:12px;fill:#c7d0da}} .stt{{font-size:20px;font-weight:650;fill:#fff}} .cap{{font-size:10px;font-weight:650;fill:#7c8794;letter-spacing:.08em}}
</style>
<g clip-path="url(#round)">
<!-- The four steps; the current one is highlighted and its bar fills while it plays -->
{steps}
<!-- Barrel's Library window -->
<g><rect x="40" y="60" width="600" height="340" rx="14" fill="#fff"/></g>
<g clip-path="url(#win)">
  <rect x="40" y="60" width="160" height="340" fill="#f6f6f7"/>
  <circle cx="60" cy="80" r="5.5" fill="#ff5f57"/><circle cx="78" cy="80" r="5.5" fill="#febc2e"/><circle cx="96" cy="80" r="5.5" fill="#28c840"/>
  <text x="56" y="114" class="s">Play</text>
  <rect x="50" y="122" width="140" height="28" rx="7" fill="#2a63d9"/><text x="64" y="141" class="side" style="fill:#fff">Library</text>
  <text x="56" y="180" class="s">Advanced</text>
  <text x="64" y="206" class="side">steam</text>
  <text x="220" y="90" class="h">Library</text>
  <line x1="200" y1="106" x2="640" y2="106" stroke="#000" stroke-opacity=".08"/>
  <!-- Refresh: spins once when clicked -->
  <circle cx="476" cy="84" r="16" fill="#fff" stroke="#000" stroke-opacity=".1"/>
  <circle cx="476" cy="84" r="15.5" fill="#000" opacity="0">{press(c_refresh, .12)}</circle>
  <g>{anim(None, [(c_refresh, "0 476 84"), (c_refresh + .7, "360 476 84")], kind="rotate")}
    <path d="M481 79.5a7 7 0 1 0 2 5" fill="none" stroke="#1c1c1e" stroke-width="1.6" stroke-linecap="round"/><path d="M477.5 77.5l4 2-2 4" fill="none" stroke="#1c1c1e" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"/>
  </g>
  {ripple(476, 84, c_refresh, "#3478f6")}
  <!-- Open Steam -->
  <rect x="507" y="68" width="123" height="32" rx="16" fill="#3478f6"/>
  <rect x="507" y="68" width="123" height="32" rx="16" fill="#000" opacity="0">{press(c_open)}</rect>
  <path transform="translate(-2 0)" d="M523 89h12a3.6 3.6 0 0 0 .3-7.2 5 5 0 0 0-9.5 1.2 3 3 0 0 0-2.8 6" fill="none" stroke="#fff" stroke-width="1.5" stroke-linejoin="round"/>
  <text x="541" y="89" class="tb">Open Steam</text>
  {ripple(566, 84, c_open, "#fff")}
  <text x="420" y="250" text-anchor="middle" class="empty">No games yet{fade((9.0, 1), (9.25, 0), (15.4, 0), (15.8, 1))}</text>
  <!-- After Refresh: the game's card -->
  <g opacity="0">{fade((9.2, 0), (9.65, 1), (15.1, 1), (15.5, 0))}
    <g>{anim(None, [(9.2, "0,10"), (9.65, "0,0")], kind="translate")}
    <rect x="216" y="120" width="330" height="144" rx="12" fill="#f6f6f7"/>
    <image x="230" y="134" width="44" height="44" href="{game}"/>
    <text x="286" y="152" class="g">Stonewards</text>
    <circle cx="291" cy="166" r="5" fill="#2f9a55"/><path d="M288.6 166l1.7 1.7 3.1-3.3" fill="none" stroke="#fff" stroke-width="1.4" stroke-linecap="round"/>
    <text x="301" y="170" class="ok">Tested: works</text>
    <text x="230" y="208" class="l">Graphics</text>
    <rect x="284" y="194" width="118" height="22" rx="5" fill="#e6e6ea"/><text x="292" y="209" class="pop">Automatic · DXVK</text>
    <rect x="230" y="224" width="190" height="28" rx="14" fill="#3478f6"/>
    <rect x="230" y="224" width="190" height="28" rx="14" fill="#000" opacity="0">{press(c_play)}</rect>
    <path d="M305 232v12l10-6z" fill="#fff"/><text x="321" y="243" class="btn" fill="#fff">Play</text>
    {ripple(325, 238, c_play, "#fff")}
    <rect x="428" y="224" width="106" height="28" rx="14" fill="#e6e6ea"/><text x="481" y="243" text-anchor="middle" class="btn" fill="#1c1c1e">Add to Dock</text>
    </g>
  </g>
</g>
<!-- Steam's window: rises in after Open Steam, sinks away once the game is installed -->
<g opacity="0">{fade((1.9, 0), (2.4, 1), (7.0, 1), (7.5, 0))}
  <g>{anim(None, [(1.9, "0,16"), (2.4, "0,0"), (7.0, "0,0"), (7.5, "0,10")], kind="translate")}
  <g><rect x="110" y="96" width="500" height="290" rx="10" fill="#1b2129"/></g>
  <rect x="110" y="96" width="500" height="28" rx="10" fill="#12161c"/><rect x="110" y="114" width="500" height="10" fill="#12161c"/>
  <circle cx="126" cy="110" r="5" fill="#ff5f57"/><circle cx="142" cy="110" r="5" fill="#febc2e"/><circle cx="158" cy="110" r="5" fill="#28c840"/>
  <text x="360" y="114" text-anchor="middle" class="st">Steam</text>
  <rect x="110" y="124" width="140" height="262" fill="#20262f"/>
  <text x="124" y="148" class="cap">LIBRARY</text>
  <rect x="116" y="158" width="128" height="26" rx="4" fill="#2f3a48"/>
  <image x="122" y="162" width="18" height="18" href="{game}"/><text x="146" y="175" class="st" style="fill:#fff">Stonewards</text>
  <image x="270" y="150" width="64" height="64" href="{game}"/>
  <text x="350" y="190" class="stt">Stonewards</text>
  <g>{fade((3.75, 1), (3.95, 0))}
    <rect x="270" y="236" width="130" height="36" rx="4" fill="#1a9fff"/>
    <rect x="270" y="236" width="130" height="36" rx="4" fill="#000" opacity="0">{press(c_install)}</rect>
    <text x="335" y="259" text-anchor="middle" class="btn" fill="#fff">Install</text>
  </g>
  {ripple(335, 254, c_install, "#fff")}
  <g opacity="0">{fade((3.75, 0), (3.95, 1), (d1, 1), (d1 + .25, 0))}
    <rect x="270" y="236" width="130" height="36" rx="4" fill="#3a4350"/><text x="335" y="259" text-anchor="middle" class="btn" fill="#9aa5b2">Installing…</text>
  </g>
  <g opacity="0">{fade((d1, 0), (d1 + .25, 1))}
    <rect x="270" y="236" width="130" height="36" rx="4" fill="#5ba32b"/><path d="M314 247v12l10-6z" fill="#fff"/><text x="330" y="259" class="btn" fill="#fff">Play</text>
  </g>
  <g opacity="0">{fade((3.75, 0), (3.95, 1))}
    <text x="270" y="300" class="st">Downloading…{fade((d1, 1), (d1 + .2, 0))}</text>
    <text x="270" y="300" class="st" style="fill:#7cc79a" opacity="0">Installed{fade((d1, 0), (d1 + .2, 1))}</text>
    {pct}
    <rect x="270" y="310" width="310" height="8" rx="4" fill="#2b3440"/>
    <rect x="270" y="310" width="0" height="8" rx="4" fill="#1a9fff">{anim("width", [(d0, 0), (d1, 310)], mode="linear")}</rect>
  </g>
  </g>
</g>
<!-- The game starts: its window grows in, loads, and fades away before the loop restarts -->
<g opacity="0">{fade((12.0, 0), (12.45, 1), (14.9, 1), (15.3, 0))}
  <g transform="translate(360 234)"><g>{anim(None, [(12.0, .92), (12.45, 1)], kind="scale")}<g transform="translate(-360 -234)">
  <g><rect x="150" y="104" width="420" height="260" rx="10" fill="#141418"/></g>
  <image x="320" y="140" width="80" height="80" href="{game}"/>
  <text x="360" y="262" text-anchor="middle" class="stt">Stonewards</text>
  <rect x="260" y="290" width="200" height="4" rx="2" fill="#2a2a30"/>
  <rect x="260" y="290" width="0" height="4" rx="2" fill="#e07a45">{anim("width", [(12.5, 0), (14.4, 200)], mode="linear")}</rect>
  </g></g></g>
</g>
<!-- Pointer: glides between targets and squeezes on each click -->
<g>{pointer}
  <g>{squeeze}
    <path d="M0 0 L0 22 L6 16 L10 26 L14 24 L10 14 L18 14 Z" fill="#1c1c1e" stroke="#fff" stroke-width="1.5" stroke-linejoin="round"/>
  </g>
</g>
</g>
</svg>
"""


def main():
    for cast in sorted((MEDIA / "casts").glob("*.txt")):
        out = MEDIA / f"cast-{cast.stem}.svg"
        out.write_text(render_cast(cast.stem, parse_cast(cast)))
        print("wrote", out.relative_to(ROOT))
    for name, render in (("dock-demo", render_dock_demo), ("graphics-demo", render_graphics_demo),
                         ("steps-demo", render_steps_demo)):
        out = MEDIA / f"{name}.svg"
        out.write_text(render())
        print("wrote", out.relative_to(ROOT))
    for theme in THEMES:
        out = MEDIA / f"how-it-works-{theme}.svg"
        out.write_text(render_how_it_works(theme))
        print("wrote", out.relative_to(ROOT))


if __name__ == "__main__":
    main()

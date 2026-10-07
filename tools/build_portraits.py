#!/usr/bin/env python3
"""Draw the four recurring heroes of the station as SVG portraits.

Run from anywhere:  python3 tools/build_portraits.py

Writes assets/characters/<hero>_<neutral|happy|thinking>.svg. The portraits are
generated so that the three expressions of one hero share every line except the
face; edit the drawing functions below, rerun, then let Godot reimport.

Heroes:  nora  - a voice in an old radio, deliberately WITHOUT a face
         teo   - the mad master: wild hair, goggles, tools everywhere
         clara - the friendly photographer with a camera and a braid
         bruno - the mad trainer in an orange hat with a whistle
"""
import math
import random
from pathlib import Path

OUT = Path(__file__).resolve().parents[1] / "assets" / "characters"
W, H = 240, 270
EXPRESSIONS = ("neutral", "happy", "thinking")


def frame(inner: str, top: str, bottom: str, extra_defs: str = "") -> str:
    """Card with a soft vignette and the brass frame every portrait shares."""
    return f"""<svg xmlns="http://www.w3.org/2000/svg" width="{W * 2}" height="{H * 2}" viewBox="0 0 {W} {H}">
<defs>
<linearGradient id="bg" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="{top}"/><stop offset="1" stop-color="{bottom}"/></linearGradient>
<radialGradient id="glow" cx=".5" cy=".42" r=".6"><stop offset="0" stop-color="#fff" stop-opacity=".22"/><stop offset="1" stop-color="#fff" stop-opacity="0"/></radialGradient>
{extra_defs}
</defs>
<clipPath id="card"><rect width="{W}" height="{H}" rx="24"/></clipPath>
<g clip-path="url(#card)">
<rect width="{W}" height="{H}" fill="url(#bg)"/>
<rect width="{W}" height="{H}" fill="url(#glow)"/>
{inner}
</g>
<rect x="4" y="4" width="{W - 8}" height="{H - 8}" rx="21" fill="none" stroke="#d8b676" stroke-opacity=".75" stroke-width="2.5"/>
<rect x="9" y="9" width="{W - 18}" height="{H - 18}" rx="17" fill="none" stroke="#d8b676" stroke-opacity=".25" stroke-width="1"/>
</svg>
"""


def mountains(color: str, opacity: float = 0.35, base: int = 200) -> str:
    return (f'<path d="M0 {base} L34 {base - 46} L56 {base - 24} L92 {base - 78} L128 {base - 30} '
            f'L160 {base - 58} L196 {base - 22} L240 {base - 52} L240 {H} L0 {H}Z" '
            f'fill="{color}" fill-opacity="{opacity}"/>')


# --------------------------------------------------------------------------- NORA
def nora(expr: str) -> str:
    """No face on purpose: Nora is a voice. The radio is her portrait."""
    lit = expr != "neutral"
    dial_glow = "#ffd988" if expr == "happy" else "#e8b866" if expr == "thinking" else "#a9814b"
    parts = []
    # night sky, moon, far mountains and the beam of a lighthouse that nobody has seen
    parts.append('<circle cx="188" cy="46" r="17" fill="#f2e4b8" opacity=".85"/><circle cx="195" cy="41" r="15" fill="#13222d" opacity=".55"/>')
    for x, y, r in ((30, 36, 1.4), (64, 22, 1), (110, 30, 1.2), (150, 18, 1), (214, 92, 1.2), (24, 90, 1)):
        parts.append(f'<circle cx="{x}" cy="{y}" r="{r}" fill="#f6ecc9" opacity=".8"/>')
    parts.append(mountains("#0b1a24", 0.85, 196))
    parts.append('<path d="M34 196 L38 150 L42 196Z" fill="#1d3442"/><rect x="33" y="146" width="10" height="7" fill="#e9c878" opacity=".9"/>'
                 '<path d="M43 148 L120 126 L120 138Z" fill="#f5dc9a" opacity=".16"/>')
    # sound waves: how much the signal is "alive" depends on the mood
    cx, cy = 120, 92
    arcs = {"neutral": 2, "happy": 4, "thinking": 3}[expr]
    for i in range(arcs):
        r = 30 + i * 15
        op = 0.75 - i * 0.14
        parts.append(f'<path d="M{cx - r} {cy + 4} A{r} {r} 0 0 1 {cx + r} {cy + 4}" fill="none" stroke="#f0cc86" stroke-opacity="{max(op, .18):.2f}" stroke-width="2.4" stroke-linecap="round" stroke-dasharray="{"3 6" if expr == "thinking" else "none"}"/>')
    if expr == "thinking":
        # static: the voice is breaking up while she thinks
        parts.append('<path d="M70 70 l7 -6 l5 9 l7 -12 l6 10 l7 -7 M146 60 l6 8 l6 -10 l7 9 l6 -6" fill="none" stroke="#9fc4c4" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" opacity=".8"/>')
    if expr == "happy":
        for x, y, s in ((60, 52, 7), (182, 70, 6), (92, 28, 5), (166, 30, 5)):
            parts.append(f'<path d="M{x} {y - s} L{x + s * .3} {y - s * .3} L{x + s} {y} L{x + s * .3} {y + s * .3} L{x} {y + s} L{x - s * .3} {y + s * .3} L{x - s} {y} L{x - s * .3} {y - s * .3}Z" fill="#ffe9a8"/>')
    # table
    parts.append(f'<rect x="0" y="228" width="{W}" height="42" fill="#3b2a1f"/><rect x="0" y="228" width="{W}" height="4" fill="#5a4230"/>')
    # radio body
    parts.append('<rect x="38" y="112" width="164" height="118" rx="16" fill="#6b4529"/>'
                 '<rect x="38" y="112" width="164" height="118" rx="16" fill="none" stroke="#3f2815" stroke-width="3"/>'
                 '<rect x="44" y="118" width="152" height="106" rx="12" fill="#7d5333"/>')
    # speaker grille
    parts.append('<rect x="52" y="126" width="62" height="88" rx="8" fill="#2c1d12"/>')
    for i in range(9):
        parts.append(f'<rect x="57" y="{132 + i * 9}" width="52" height="3.4" rx="1.7" fill="#c9a45c" opacity="{.92 if lit else .6}"/>')
    # dial window with a tiny lighthouse inside
    parts.append(f'<rect x="124" y="128" width="64" height="40" rx="7" fill="#1a110a"/>'
                 f'<rect x="127" y="131" width="58" height="34" rx="5" fill="{dial_glow}" opacity="{.95 if lit else .55}"/>')
    parts.append('<path d="M134 163 V150 M146 163 V152 M158 163 V148 M170 163 V152" stroke="#5b3a18" stroke-width="1.4" opacity=".7"/>')
    needle_x = {"neutral": 140, "happy": 166, "thinking": 153}[expr]
    parts.append(f'<path d="M{needle_x} 133 V163" stroke="#b7331f" stroke-width="2.2" stroke-linecap="round"/>')
    parts.append('<path d="M171 163 L173.5 151 L176 163Z" fill="#3a2410"/><rect x="171.5" y="147" width="4" height="4" fill="#fff6c8"/>')
    # knobs
    for kx in (140, 172):
        parts.append(f'<circle cx="{kx}" cy="196" r="13" fill="#2d1c10"/><circle cx="{kx}" cy="196" r="10" fill="#c9a45c"/>'
                     f'<path d="M{kx} 196 L{kx + (4 if kx == 140 else -3)} 188" stroke="#3a2410" stroke-width="2.4" stroke-linecap="round"/>')
    # antenna + a steaming cup of mate: someone was here a moment ago
    parts.append('<path d="M176 112 L206 52" stroke="#c9a45c" stroke-width="2.4"/><circle cx="206" cy="52" r="3.4" fill="#e8c878"/>')
    parts.append('<path d="M202 224 h26 l-3 -22 h-20Z" fill="#9a7a4a"/><path d="M204 206 h20" stroke="#6f542f" stroke-width="2"/>'
                 '<path d="M208 196 q-4 -8 1 -14 M216 196 q-4 -8 1 -14" fill="none" stroke="#d9d2c3" stroke-width="2" stroke-linecap="round" opacity=".65"/>')
    parts.append('<path d="M214 202 L222 168" stroke="#d8c9a0" stroke-width="3" stroke-linecap="round"/>')
    return frame("\n".join(parts), "#132633", "#1c2f3a")


# --------------------------------------------------------------------------- shared face helpers
def head(cx, cy, rx, ry, skin, shade, ears=True):
    out = []
    if ears:
        out.append(f'<ellipse cx="{cx - rx + 1}" cy="{cy + 6}" rx="8" ry="11" fill="{skin}"/><ellipse cx="{cx + rx - 1}" cy="{cy + 6}" rx="8" ry="11" fill="{skin}"/>')
        out.append(f'<ellipse cx="{cx - rx + 1}" cy="{cy + 6}" rx="3.5" ry="6" fill="{shade}" opacity=".55"/><ellipse cx="{cx + rx - 1}" cy="{cy + 6}" rx="3.5" ry="6" fill="{shade}" opacity=".55"/>')
    out.append(f'<rect x="{cx - 16}" y="{cy + ry - 14}" width="32" height="34" rx="8" fill="{shade}"/>')
    out.append(f'<ellipse cx="{cx}" cy="{cy}" rx="{rx}" ry="{ry}" fill="{skin}"/>')
    return "".join(out)


def eye(x, y, r, pupil=3.4, look=(0, 0), lid=None, color="#2a1d1a"):
    """White eye with a pupil. lid squashes the top (sleepy/happy)."""
    s = f'<ellipse cx="{x}" cy="{y}" rx="{r}" ry="{r * 1.05}" fill="#fffdf6" stroke="#4a3328" stroke-width="1.4"/>'
    s += f'<circle cx="{x + look[0]}" cy="{y + look[1]}" r="{pupil}" fill="{color}"/>'
    s += f'<circle cx="{x + look[0] + pupil * .35}" cy="{y + look[1] - pupil * .4}" r="{pupil * .3}" fill="#fff"/>'
    return s


# --------------------------------------------------------------------------- TEO
def teo(expr: str) -> str:
    rnd = random.Random(7)
    skin, shade = "#d9a174", "#b97f58"
    hair, hair2 = "#2e1d17", "#47301f"
    cx, cy = 120, 122
    p = []
    # workshop wall: pegboard with the silhouettes of tools and a big gear
    p.append('<rect width="240" height="270" fill="#5a3a26"/>')
    for gx in range(14, 240, 26):
        for gy in range(14, 150, 26):
            p.append(f'<circle cx="{gx}" cy="{gy}" r="1.6" fill="#2b1a10" opacity=".55"/>')
    def gear(x, y, r, teeth, col, op):
        pts = []
        for i in range(teeth * 2):
            a = math.pi * i / teeth
            rr = r if i % 2 == 0 else r * .78
            pts.append(f"{x + math.cos(a) * rr:.1f},{y + math.sin(a) * rr:.1f}")
        return f'<polygon points="{" ".join(pts)}" fill="{col}" opacity="{op}"/><circle cx="{x}" cy="{y}" r="{r * .3}" fill="#5a3a26"/>'
    p.append(gear(34, 56, 26, 9, "#b9833f", .55))
    p.append(gear(206, 104, 20, 8, "#d3a45a", .5))
    p.append(gear(196, 30, 12, 7, "#b9833f", .45))
    # shoulders and leather apron: pockets bristling with tools
    p.append('<path d="M10 270 Q14 200 76 186 L164 186 Q226 200 230 270Z" fill="#3c5568"/>')
    p.append('<path d="M70 190 L90 262 L150 262 L170 190 L150 202 Q120 214 90 202Z" fill="#8a5a33"/>')
    p.append('<path d="M70 190 L82 270 M170 190 L158 270" stroke="#6a421f" stroke-width="7"/>')
    p.append('<rect x="92" y="232" width="56" height="34" rx="5" fill="#a06b3c" stroke="#5e3a1b" stroke-width="2"/>')
    # tools in the pocket
    p.append('<rect x="98" y="214" width="6" height="26" rx="2" fill="#d94c2f"/><rect x="98" y="214" width="6" height="6" rx="2" fill="#7a2415"/>'
             '<rect x="109" y="208" width="5" height="32" rx="2" fill="#e8c243"/><rect x="109" y="208" width="5" height="6" fill="#8a6a10"/>'
             '<path d="M122 238 V206 M128 238 V212" stroke="#cfd6d8" stroke-width="4" stroke-linecap="round"/>'
             '<circle cx="122" cy="204" r="6" fill="none" stroke="#cfd6d8" stroke-width="3.2"/><path d="M128 210 l9 -6 l3 5 l-8 6Z" fill="#cfd6d8"/>'
             '<rect x="136" y="214" width="7" height="26" rx="3" fill="#3a8f6c"/>')
    # wrench hanging on the strap and a measuring tape on the belt
    p.append('<g transform="rotate(-24 62 232)"><rect x="58" y="206" width="9" height="50" rx="4" fill="#aeb7bb"/><circle cx="62.5" cy="206" r="10" fill="none" stroke="#aeb7bb" stroke-width="8"/></g>')
    p.append('<rect x="160" y="226" width="24" height="18" rx="4" fill="#e8c243"/><rect x="164" y="231" width="16" height="8" fill="#6a5008"/>')
    # a big goggle strap: goggles pushed up on the forehead
    p.append(head(cx, cy, 47, 56, skin, shade))
    # WILD hair: dozens of curls exploding in all directions
    curls = []
    for i in range(34):
        a = math.pi * (1.02 + 0.96 * i / 33) + rnd.uniform(-.08, .08)
        dist = 50 + rnd.uniform(0, 20)
        x = cx + math.cos(a) * dist
        y = cy - 4 + math.sin(a) * (dist + 8)
        curls.append(f'<circle cx="{x:.1f}" cy="{y:.1f}" r="{rnd.uniform(9, 15):.1f}" fill="{hair if i % 3 else hair2}"/>')
    for sx in (-1, 1):
        for k in range(4):
            curls.append(f'<circle cx="{cx + sx * (50 + rnd.uniform(-3, 5)):.1f}" cy="{cy - 26 + k * 13 + rnd.uniform(-3, 3):.1f}" r="{rnd.uniform(8, 12):.1f}" fill="{hair}"/>')
    p.append("".join(curls))
    # forehead and sideburn cover
    p.append(f'<path d="M{cx - 44} {cy - 14} Q{cx - 30} {cy - 60} {cx} {cy - 52} Q{cx + 30} {cy - 60} {cx + 44} {cy - 14} Q{cx + 26} {cy - 36} {cx} {cy - 32} Q{cx - 26} {cy - 36} {cx - 44} {cy - 14}Z" fill="{hair}"/>')
    # things stuck in the hair: pencil, screwdriver, a tiny gear, a spring
    p.append('<g transform="rotate(-28 70 52)"><rect x="66" y="22" width="6" height="42" rx="1.5" fill="#f1c84a"/><rect x="66" y="22" width="6" height="7" fill="#e07a7a"/><path d="M66 64 L69 72 L72 64Z" fill="#e8c9a0"/></g>')
    p.append('<g transform="rotate(22 168 44)"><rect x="164" y="14" width="6" height="40" rx="2" fill="#aab4b8"/><rect x="160" y="42" width="14" height="22" rx="4" fill="#2f77c0"/></g>')
    p.append('<path d="M96 38 q-6 -4 0 -8 q6 -4 0 -8 q-6 -4 0 -8" fill="none" stroke="#cfd6d8" stroke-width="2.4" stroke-linecap="round"/>')
    # goggles pushed up: mismatched lenses (one is a magnifier)
    p.append('<path d="M70 84 Q120 66 170 84" fill="none" stroke="#2a2a2a" stroke-width="7" stroke-linecap="round"/>')
    p.append('<circle cx="98" cy="78" r="17" fill="#2a2a2a"/><circle cx="98" cy="78" r="13" fill="#8fd0d8" opacity=".92"/><path d="M89 74 q6 -8 14 -6" stroke="#fff" stroke-width="2.6" fill="none" stroke-linecap="round"/>'
             '<circle cx="142" cy="76" r="14" fill="#7a5a28"/><circle cx="142" cy="76" r="10.5" fill="#cfe9d6" opacity=".92"/><path d="M135 73 q4 -6 10 -4" stroke="#fff" stroke-width="2.2" fill="none" stroke-linecap="round"/>')
    # face
    brow_l = f"M{cx - 38} {cy - 6} Q{cx - 26} {cy - 20} {cx - 12} {cy - 8}"
    brow_r = f"M{cx + 12} {cy - 8} Q{cx + 26} {cy - 20} {cx + 38} {cy - 6}"
    if expr == "thinking":
        brow_l = f"M{cx - 38} {cy - 2} Q{cx - 26} {cy - 8} {cx - 12} {cy - 3}"
        brow_r = f"M{cx + 12} {cy - 22} Q{cx + 26} {cy - 32} {cx + 38} {cy - 18}"
    p.append(f'<path d="{brow_l} M{brow_r[1:]}" fill="none" stroke="{hair}" stroke-width="5.5" stroke-linecap="round"/>')
    if expr == "happy":
        p.append(f'<path d="M{cx - 36} {cy + 6} Q{cx - 24} {cy - 8} {cx - 12} {cy + 6} M{cx + 12} {cy + 6} Q{cx + 24} {cy - 8} {cx + 36} {cy + 6}" fill="none" stroke="#2a1d1a" stroke-width="4" stroke-linecap="round"/>')
    elif expr == "thinking":
        p.append(eye(cx - 24, cy + 4, 11, 3.6, (4, -4)) + eye(cx + 24, cy + 2, 15, 4.4, (5, -6)))
        p.append(f'<circle cx="{cx + 24}" cy="{cy + 2}" r="18" fill="none" stroke="#8a6a28" stroke-width="3"/>')
    else:
        p.append(eye(cx - 24, cy + 4, 12.5, 3, (0, 0)) + eye(cx + 24, cy + 4, 12.5, 3, (0, 0)))
    # nose and soot smudges
    p.append(f'<path d="M{cx} {cy + 8} q-7 14 0 20 q7 0 6 -4" fill="none" stroke="#a5683f" stroke-width="2.4" stroke-linecap="round"/>')
    p.append(f'<ellipse cx="{cx - 30}" cy="{cy + 26}" rx="9" ry="5" fill="#2a1d1a" opacity=".28"/><ellipse cx="{cx + 34}" cy="{cy + 14}" rx="6" ry="3.6" fill="#2a1d1a" opacity=".25"/>')
    # mouth
    my = cy + 38
    if expr == "happy":
        p.append(f'<path d="M{cx - 26} {my - 6} Q{cx} {my + 34} {cx + 26} {my - 6}Z" fill="#6a1f1b" stroke="#3a1210" stroke-width="2"/>'
                 f'<path d="M{cx - 20} {my - 4} h40 v7 h-40Z" fill="#fffdf6"/><path d="M{cx - 12} {my + 16} Q{cx} {my + 6} {cx + 12} {my + 16} Q{cx} {my + 26} {cx - 12} {my + 16}Z" fill="#d6685a"/>')
    elif expr == "thinking":
        p.append(f'<path d="M{cx - 18} {my + 4} Q{cx} {my - 6} {cx + 20} {my + 2}" fill="none" stroke="#6a1f1b" stroke-width="3.4" stroke-linecap="round"/><path d="M{cx + 20} {my + 2} l6 -5" stroke="#6a1f1b" stroke-width="3" stroke-linecap="round"/>')
    else:
        p.append(f'<path d="M{cx - 26} {my - 4} Q{cx - 2} {my + 22} {cx + 26} {my - 8} Q{cx} {my + 4} {cx - 26} {my - 4}Z" fill="#6a1f1b" stroke="#3a1210" stroke-width="2"/><path d="M{cx - 18} {my - 2} Q{cx} {my + 6} {cx + 18} {my - 4} l-1 5 Q{cx} {my + 11} {cx - 17} {my + 3}Z" fill="#fffdf6"/>')
    p.append(f'<path d="M{cx - 6} {my + 24} q6 4 12 0" stroke="#a5683f" stroke-width="2" fill="none" stroke-linecap="round" opacity=".6"/>')
    # expression extras
    if expr == "happy":
        for x, y, s in ((26, 150, 9), (214, 170, 7), (208, 60, 6)):
            p.append(f'<path d="M{x} {y - s} L{x + 2} {y - 2} L{x + s} {y} L{x + 2} {y + 2} L{x} {y + s} L{x - 2} {y + 2} L{x - s} {y} L{x - 2} {y - 2}Z" fill="#ffe08a"/>')
        p.append('<path d="M36 176 l-10 8 l8 2 l-6 10" fill="none" stroke="#ffd34a" stroke-width="3" stroke-linecap="round" stroke-linejoin="round"/>')
    if expr == "thinking":
        p.append('<g transform="translate(196 36)"><circle r="17" fill="#ffe27a" opacity=".95"/><rect x="-6" y="14" width="12" height="9" rx="2" fill="#9a8a8a"/><path d="M-5 -2 q5 7 10 0 M0 -2 v8" stroke="#a9742a" stroke-width="2" fill="none" stroke-linecap="round"/><path d="M-26 -20 l-8 -6 M26 -20 l8 -6 M0 -30 v-8" stroke="#ffe27a" stroke-width="3" stroke-linecap="round"/></g>')
    return frame("\n".join(p), "#6a4630", "#34231a")


# --------------------------------------------------------------------------- CLARA
def clara(expr: str) -> str:
    skin, shade = "#f0c4a0", "#d9a07a"
    hair, hair2 = "#7a4426", "#a05d33"
    cx, cy = 120, 120
    p = []
    # a bright river valley behind her
    p.append(mountains("#2c6b73", .5, 168))
    p.append('<path d="M0 214 Q60 196 118 210 T240 200 V270 H0Z" fill="#3b8f96" opacity=".7"/>')
    p.append('<path d="M10 226 q22 -8 44 0 M128 232 q26 -9 52 0" stroke="#d3f0ee" stroke-width="2.2" fill="none" stroke-linecap="round" opacity=".7"/>')
    for fx, fy, c in ((24, 74, "#ffd47a"), (206, 52, "#ffb1a1"), (212, 150, "#fff2b0"), (30, 130, "#ffe1d0")):
        p.append(f'<circle cx="{fx}" cy="{fy}" r="4.5" fill="{c}" opacity=".85"/><circle cx="{fx}" cy="{fy}" r="1.8" fill="#d98b2b"/>')
    # back hair + braid over the shoulder
    p.append(f'<path d="M{cx - 54} {cy + 40} Q{cx - 66} {cy - 70} {cx} {cy - 70} Q{cx + 66} {cy - 70} {cx + 54} {cy + 40} Q{cx + 50} {cy + 8} {cx} {cy - 4} Q{cx - 50} {cy + 8} {cx - 54} {cy + 40}Z" fill="{hair}"/>')
    # yellow rain jacket and camera strap
    p.append('<path d="M8 270 Q14 204 72 188 L168 188 Q226 204 232 270Z" fill="#e9b93a"/>')
    p.append('<path d="M72 188 L120 226 L168 188 L158 184 L120 210 L82 184Z" fill="#c99220"/>')
    p.append('<path d="M120 226 V270" stroke="#c99220" stroke-width="3"/><circle cx="120" cy="244" r="3" fill="#8a5f10"/>')
    p.append(f'<rect x="{cx - 17}" y="{cy + 40}" width="34" height="36" rx="8" fill="{shade}"/>')
    p.append('<path d="M86 190 Q96 232 116 246 M154 190 Q144 232 124 246" fill="none" stroke="#7b3f2c" stroke-width="5"/>')
    # braid
    braid = '<path d="M172 150 Q196 170 190 204 Q186 232 200 248" fill="none" stroke="%s" stroke-width="22" stroke-linecap="round"/>' % hair
    p.append(braid)
    for i in range(5):
        y = 164 + i * 16
        x = 186 + (-4 if i % 2 else 4) * (1 - i * .12)
        p.append(f'<ellipse cx="{x:.0f}" cy="{y}" rx="9.5" ry="6" fill="{hair2}" transform="rotate({-20 if i % 2 else 20} {x:.0f} {y})"/>')
    p.append('<circle cx="200" cy="250" r="6" fill="#3ba8a0"/>')
    # retro camera on her chest
    p.append('<rect x="82" y="224" width="76" height="46" rx="9" fill="#2a2d33"/><rect x="82" y="224" width="76" height="16" rx="8" fill="#c9ced3"/>'
             '<rect x="92" y="216" width="22" height="10" rx="3" fill="#c9ced3"/><rect x="130" y="218" width="16" height="8" rx="2" fill="#e95a3a"/>'
             '<circle cx="120" cy="252" r="21" fill="#17191d"/><circle cx="120" cy="252" r="16" fill="#3a4a63"/><circle cx="120" cy="252" r="9" fill="#101a2a"/><circle cx="115" cy="247" r="3.4" fill="#cfe4ff" opacity=".9"/>')
    # head
    p.append(head(cx, cy, 46, 54, skin, shade))
    # rosy cheeks + freckles
    p.append(f'<circle cx="{cx - 28}" cy="{cy + 22}" r="9" fill="#f08a78" opacity=".38"/><circle cx="{cx + 28}" cy="{cy + 22}" r="9" fill="#f08a78" opacity=".38"/>')
    for fx, fy in ((-22, 17), (-30, 24), (-17, 25), (22, 17), (30, 24), (17, 25)):
        p.append(f'<circle cx="{cx + fx}" cy="{cy + fy}" r="1.4" fill="#b8734d"/>')
    # fringe
    p.append(f'<path d="M{cx - 47} {cy - 8} Q{cx - 44} {cy - 62} {cx + 4} {cy - 58} Q{cx + 50} {cy - 56} {cx + 47} {cy - 8} Q{cx + 40} {cy - 34} {cx + 20} {cy - 40} Q{cx + 4} {cy - 20} {cx - 14} {cy - 36} Q{cx - 34} {cy - 30} {cx - 47} {cy - 8}Z" fill="{hair}"/>')
    p.append(f'<path d="M{cx - 20} {cy - 50} Q{cx} {cy - 58} {cx + 24} {cy - 50}" fill="none" stroke="{hair2}" stroke-width="3" stroke-linecap="round" opacity=".8"/>')
    # leaf hairpin
    p.append(f'<g transform="translate({cx + 40} {cy - 36}) rotate(30)"><path d="M0 0 q10 -16 24 -10 q-4 16 -24 10Z" fill="#59b36b"/><path d="M2 -2 L20 -8" stroke="#2f7a42" stroke-width="1.5"/></g>')
    # eyes + brows
    eye_y = cy + 6
    if expr == "happy":
        p.append(f'<path d="M{cx - 34} {eye_y + 2} Q{cx - 23} {eye_y - 12} {cx - 12} {eye_y + 2} M{cx + 12} {eye_y + 2} Q{cx + 23} {eye_y - 12} {cx + 34} {eye_y + 2}" fill="none" stroke="#3b2418" stroke-width="3.8" stroke-linecap="round"/>')
    elif expr == "thinking":
        p.append(eye(cx - 23, eye_y, 10, 4.2, (-4, -5)) + eye(cx + 23, eye_y, 10, 4.2, (-4, -5)))
    else:
        p.append(eye(cx - 23, eye_y, 10, 4.4, (1, 1)) + eye(cx + 23, eye_y, 10, 4.4, (1, 1)))
        p.append(f'<path d="M{cx - 33} {eye_y - 8} Q{cx - 23} {eye_y - 17} {cx - 13} {eye_y - 8}" fill="none" stroke="#3b2418" stroke-width="1.8" stroke-linecap="round"/>')
    brow_stroke = hair
    if expr == "thinking":
        p.append(f'<path d="M{cx - 34} {eye_y - 16} Q{cx - 23} {eye_y - 24} {cx - 12} {eye_y - 17} M{cx + 12} {eye_y - 24} Q{cx + 23} {eye_y - 32} {cx + 34} {eye_y - 22}" fill="none" stroke="{brow_stroke}" stroke-width="3.6" stroke-linecap="round"/>')
    else:
        p.append(f'<path d="M{cx - 34} {eye_y - 14} Q{cx - 23} {eye_y - 22} {cx - 12} {eye_y - 15} M{cx + 12} {eye_y - 15} Q{cx + 23} {eye_y - 22} {cx + 34} {eye_y - 14}" fill="none" stroke="{brow_stroke}" stroke-width="3.6" stroke-linecap="round"/>')
    # nose and mouth
    p.append(f'<path d="M{cx - 2} {cy + 14} q-3 8 2 11 q4 0 5 -3" fill="none" stroke="#b8734d" stroke-width="2" stroke-linecap="round"/>')
    my = cy + 36
    if expr == "happy":
        p.append(f'<path d="M{cx - 20} {my - 6} Q{cx} {my + 24} {cx + 20} {my - 6}Z" fill="#9a3a3a" stroke="#6a2020" stroke-width="2"/><path d="M{cx - 16} {my - 4} h32 v6 h-32Z" fill="#fffdf6"/><path d="M{cx - 10} {my + 10} Q{cx} {my + 3} {cx + 10} {my + 10} Q{cx} {my + 18} {cx - 10} {my + 10}Z" fill="#e88a82"/>')
    elif expr == "thinking":
        p.append(f'<path d="M{cx - 12} {my + 2} Q{cx + 2} {my + 8} {cx + 14} {my - 2}" fill="none" stroke="#9a3a3a" stroke-width="3" stroke-linecap="round"/>')
    else:
        p.append(f'<path d="M{cx - 17} {my - 3} Q{cx} {my + 13} {cx + 17} {my - 3}" fill="none" stroke="#9a3a3a" stroke-width="3.2" stroke-linecap="round"/>')
    if expr == "happy":
        for x, y, s in ((30, 88, 8), (210, 108, 7), (46, 40, 5)):
            p.append(f'<path d="M{x} {y - s} L{x + 2} {y - 2} L{x + s} {y} L{x + 2} {y + 2} L{x} {y + s} L{x - 2} {y + 2} L{x - s} {y} L{x - 2} {y - 2}Z" fill="#fff2b0"/>')
    if expr == "thinking":
        p.append('<g fill="none" stroke="#fff2b0" stroke-width="3" stroke-linecap="round"><path d="M178 48 v-12 h12 M216 48 v-12 h-12 M178 84 v12 h12 M216 84 v12 h-12"/></g>'
                 '<circle cx="197" cy="66" r="4" fill="#fff2b0" opacity=".85"/>')
    return frame("\n".join(p), "#a9dbd3", "#4c9aa0")


# --------------------------------------------------------------------------- BRUNO
def bruno(expr: str) -> str:
    skin, shade = "#c98a5e", "#a66a43"
    cx, cy = 120, 126
    p = []
    # sunrise over the mountain he runs up every morning
    p.append('<circle cx="120" cy="176" r="86" fill="#ffd072" opacity=".5"/><circle cx="120" cy="176" r="56" fill="#ffe7a6" opacity=".45"/>')
    p.append(mountains("#7a3a34", .75, 196))
    p.append('<path d="M92 118 L128 74 L156 118Z" fill="#fff" opacity=".0"/>')
    for i in range(12):
        a = math.pi * (1.05 + i * .083)
        p.append(f'<path d="M120 190 L{120 + math.cos(a) * 190:.0f} {190 + math.sin(a) * 190:.0f}" stroke="#fff1b8" stroke-width="2.2" opacity=".18"/>')
    # tank top in team colours, huge "30"
    p.append('<path d="M6 270 Q10 206 66 190 L174 190 Q230 206 234 270Z" fill="#2fa59a"/>')
    p.append('<path d="M66 190 Q120 232 174 190 L162 186 Q120 214 78 186Z" fill="#1c6f68"/>')
    p.append('<text x="120" y="262" font-family="Arial Black, Impact, sans-serif" font-weight="900" font-size="46" text-anchor="middle" fill="#fff4cf" stroke="#d95b1c" stroke-width="2">30</text>')
    p.append(f'<rect x="{cx - 20}" y="{cy + 44}" width="40" height="34" rx="8" fill="{shade}"/>')
    # stopwatch + whistle on cords
    p.append('<path d="M92 190 Q104 214 118 232 M148 190 Q136 214 122 232" fill="none" stroke="#f2e6c8" stroke-width="3"/>')
    p.append('<circle cx="120" cy="238" r="14" fill="#cfd6d8" stroke="#6a7276" stroke-width="2.4"/><circle cx="120" cy="238" r="10.5" fill="#fffdf6"/><rect x="117" y="220" width="6" height="6" fill="#6a7276"/><path d="M120 238 V231 M120 238 L126 241" stroke="#c0392b" stroke-width="2" stroke-linecap="round"/>')
    p.append(head(cx, cy, 51, 57, skin, shade))
    # bushy mustache + sweat
    p.append(f'<path d="M{cx - 40} {cy + 36} Q{cx - 24} {cy + 20} {cx} {cy + 32} Q{cx + 24} {cy + 20} {cx + 40} {cy + 36} Q{cx + 28} {cy + 46} {cx} {cy + 38} Q{cx - 28} {cy + 46} {cx - 40} {cy + 36}Z" fill="#2c1b14"/>')
    # eyes: huge, tiny pupils = completely unhinged
    ey = cy + 2
    brow = "#2c1b14"
    if expr == "happy":
        p.append(eye(cx - 24, ey, 15, 3.2) + eye(cx + 24, ey, 15, 3.2))
        p.append(f'<path d="M{cx - 42} {ey - 20} Q{cx - 24} {ey - 40} {cx - 8} {ey - 22} M{cx + 8} {ey - 22} Q{cx + 24} {ey - 40} {cx + 42} {ey - 20}" fill="none" stroke="{brow}" stroke-width="7" stroke-linecap="round"/>')
    elif expr == "thinking":
        p.append(eye(cx - 24, ey, 12, 4, (5, 3)) + eye(cx + 24, ey, 15, 3.2, (4, 2)))
        p.append(f'<path d="M{cx - 40} {ey - 10} Q{cx - 24} {ey - 20} {cx - 8} {ey - 8} M{cx + 6} {ey - 28} Q{cx + 24} {ey - 44} {cx + 42} {ey - 24}" fill="none" stroke="{brow}" stroke-width="7" stroke-linecap="round"/>')
    else:
        p.append(eye(cx - 24, ey, 14, 2.6) + eye(cx + 24, ey, 14, 2.6))
        p.append(f'<path d="M{cx - 42} {ey - 14} L{cx - 8} {ey - 26} M{cx + 8} {ey - 26} L{cx + 42} {ey - 14}" fill="none" stroke="{brow}" stroke-width="7" stroke-linecap="round"/>')
    # pulsing temple vein for good measure
    p.append(f'<path d="M{cx + 38} {cy - 22} q4 6 -1 10 q-3 4 2 8" fill="none" stroke="#a04a3a" stroke-width="2.4" stroke-linecap="round" opacity=".7"/>')
    p.append(f'<path d="M{cx - 4} {cy + 6} q-8 14 -1 20 q8 2 10 -4" fill="none" stroke="#8a5330" stroke-width="2.6" stroke-linecap="round"/>')
    my = cy + 50
    if expr == "happy":
        p.append(f'<path d="M{cx - 30} {my - 12} Q{cx} {my + 40} {cx + 30} {my - 12}Z" fill="#6a1f1b" stroke="#3a1210" stroke-width="2.4"/>'
                 f'<path d="M{cx - 25} {my - 10} h50 v9 h-50Z" fill="#fffdf6"/><path d="M{cx - 14} {my + 18} Q{cx} {my + 6} {cx + 14} {my + 18} Q{cx} {my + 30} {cx - 14} {my + 18}Z" fill="#d6685a"/>')
    elif expr == "thinking":
        p.append(f'<rect x="{cx - 8}" y="{my - 8}" width="22" height="12" rx="6" fill="#f2c94c" stroke="#8a6a10" stroke-width="2"/><circle cx="{cx + 8}" cy="{my - 2}" r="2.6" fill="#8a6a10"/>')
        p.append(f'<path d="M{cx + 10} {my - 4} Q{cx + 40} {my - 6} {cx + 44} {my + 22}" fill="none" stroke="#f2e6c8" stroke-width="2.4"/>')
    else:
        p.append(f'<path d="M{cx - 30} {my - 12} Q{cx} {my + 28} {cx + 30} {my - 12}Z" fill="#6a1f1b" stroke="#3a1210" stroke-width="2.4"/><path d="M{cx - 25} {my - 10} h50 v8 h-50Z" fill="#fffdf6"/><path d="M{cx - 25} {my - 3} h50" stroke="#caa" stroke-width="1"/>')
    # whistle in the neutral/happy state hangs from the neck; in "thinking" it is already in his mouth
    # big orange panama hat
    p.append(f'<path d="M{cx - 72} {cy - 38} Q{cx} {cy - 58} {cx + 72} {cy - 38} Q{cx + 66} {cy - 24} {cx} {cy - 28} Q{cx - 66} {cy - 24} {cx - 72} {cy - 38}Z" fill="#c9561a" stroke="#8a3a10" stroke-width="2.4"/>')
    p.append(f'<path d="M{cx - 44} {cy - 40} Q{cx - 44} {cy - 100} {cx} {cy - 102} Q{cx + 44} {cy - 100} {cx + 44} {cy - 40} Q{cx} {cy - 52} {cx - 44} {cy - 40}Z" fill="#ff8a2e" stroke="#c9561a" stroke-width="2.4"/>')
    p.append(f'<path d="M{cx - 42} {cy - 50} Q{cx} {cy - 62} {cx + 42} {cy - 50}" fill="none" stroke="#ffe9b8" stroke-width="7"/>')
    for i in range(7):
        x = cx - 30 + i * 10
        p.append(f'<path d="M{x} {cy - 86} L{x - 6} {cy - 56}" stroke="#e86f1c" stroke-width="2" opacity=".55"/>')
    # tufts of hair escaping from under the brim
    p.append(f'<path d="M{cx - 52} {cy - 30} q-14 4 -12 18 q8 -4 14 -2Z M{cx + 52} {cy - 30} q14 4 12 18 q-8 -4 -14 -2Z" fill="#2c1b14"/>')
    # sweat drops (flying off while he is "training")
    for sx, sy in ((cx - 66, cy - 6), (cx + 70, cy + 4), (cx - 58, cy + 22)):
        p.append(f'<path d="M{sx} {sy - 9} q-6 9 0 13 q6 -4 0 -13Z" fill="#a9e1ff" opacity=".9"/>')
    if expr == "happy":
        for x, y, s in ((26, 60, 9), (214, 70, 8), (40, 156, 6), (206, 156, 6)):
            p.append(f'<path d="M{x} {y - s} L{x + 2} {y - 2} L{x + s} {y} L{x + 2} {y + 2} L{x} {y + s} L{x - 2} {y + 2} L{x - s} {y} L{x - 2} {y - 2}Z" fill="#fff4c0"/>')
        p.append('<path d="M16 100 l-8 -6 M224 100 l8 -6 M16 118 h-10 M224 118 h10" stroke="#fff4c0" stroke-width="3" stroke-linecap="round"/>')
    return frame("\n".join(p), "#f7a24d", "#a8452e")


HEROES = {"nora": nora, "teo": teo, "clara": clara, "bruno": bruno}


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    for hero, draw in HEROES.items():
        for expr in EXPRESSIONS:
            (OUT / f"{hero}_{expr}.svg").write_text(draw(expr), encoding="utf-8")
            print("wrote", f"{hero}_{expr}.svg")


if __name__ == "__main__":
    main()

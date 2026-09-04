#!/usr/bin/env python3
"""Re-derive every codepoint in Glyphs.js from the font by NAME.

A wrong Nerd Font codepoint still exists in the font, so a presence check
passes while the bar draws the wrong picture. The only assertion worth making
is name -> codepoint, straight out of the .ttf cmap.

    uv run --with fonttools python3 test/glyphs-test.py
"""
import re
import sys
from pathlib import Path

try:
    from fontTools.ttLib import TTFont
except ImportError:  # pragma: no cover
    print("skip: fontTools not available (run via `uv run --with fonttools`)")
    sys.exit(0)

FONT = "/usr/share/fonts/TTF/JetBrainsMonoNerdFont-Regular.ttf"
SRC = Path(__file__).resolve().parent.parent / "Glyphs.js"

if not Path(FONT).exists():
    print(f"skip: {FONT} not installed")
    sys.exit(0)

font = TTFont(FONT)
cmap = {}
for table in font["cmap"].tables:
    cmap.update(table.cmap)
by_name = {}
for cp, name in cmap.items():
    by_name.setdefault(name, cp)

rows = re.findall(r'(\w+):\s*\{\s*name:\s*"([^"]+)",\s*cp:\s*0x([0-9A-Fa-f]+)', SRC.read_text())
if not rows:
    print("FAIL: no TABLE rows found in Glyphs.js")
    sys.exit(1)

bad = 0
for key, name, hexcp in rows:
    want = by_name.get(name)
    have = int(hexcp, 16)
    if want is None:
        print(f"FAIL {key}: glyph name {name!r} is not in the font")
        bad += 1
    elif want != have:
        print(f"FAIL {key}: {name} is U+{want:05X} in the font, Glyphs.js says U+{have:05X}")
        bad += 1
print(f"{len(rows) - bad}/{len(rows)} glyphs resolve by name")
sys.exit(1 if bad else 0)

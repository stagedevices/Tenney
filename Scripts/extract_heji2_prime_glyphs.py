#!/usr/bin/env python3
"""Extract HEJI2 prime accidental codepoints from bundled fonts.

This script verifies that the expected HEJI2 prime glyph codepoints exist in the
bundled fonts and prints the resolved mapping for primes 17–31.
"""
from __future__ import annotations

import json
from pathlib import Path
from typing import Dict, Iterable, Tuple

from fontTools.ttLib import TTFont
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
MAPPING_PATH = ROOT / "Tenney" / "Resources" / "heji2_mapping.json"
FONT_PATHS = [
    ROOT / "Tenney" / "Resources" / "Fonts" / "HEJI2" / "HEJI2.otf",
    ROOT / "Tenney" / "Resources" / "Fonts" / "HEJI2" / "HEJI2Text.otf",
]

PRIME_SEQUENCE = [11, 13, 17, 19, 23]
PRIME_29_31_CANDIDATE_PAIRS = [
    (0xE2EC, 0xE2ED),
    (0xE2EE, 0xE2EF),
    (0xE2F0, 0xE2F1),
    (0xE2F2, 0xE2F3),
]


def load_cmap(path: Path) -> Dict[int, str]:
    font = TTFont(path)
    cmap: Dict[int, str] = {}
    for table in font["cmap"].tables:
        cmap.update(table.cmap)
    return cmap


def all_codepoints(font_paths: Iterable[Path]) -> set[int]:
    points: set[int] = set()
    for path in font_paths:
        cmap = load_cmap(path)
        points.update(cmap.keys())
    return points


def codepoint_for_glyph(glyph: str) -> int:
    scalars = [ord(ch) for ch in glyph]
    if not scalars:
        raise ValueError("empty glyph")
    if len(scalars) > 1:
        raise ValueError(f"glyph {glyph!r} has multiple scalars: {scalars}")
    return scalars[0]

def glyph_metrics(path: Path, codepoint: int) -> Tuple[int, float]:
    font = TTFont(path)
    cmap: Dict[int, str] = {}
    for table in font["cmap"].tables:
        cmap.update(table.cmap)
    name = cmap.get(codepoint)
    if name is None:
        return (0, 0.0)
    width, _ = font["hmtx"][name]
    pil_font = ImageFont.truetype(str(path), 200)
    img = Image.new("L", (200, 200), 255)
    draw = ImageDraw.Draw(img)
    draw.text((0, 0), chr(codepoint), font=pil_font, fill=0)
    pixels = img.load()
    ink = 0
    total = 200 * 200
    for y in range(200):
        for x in range(200):
            if pixels[x, y] < 128:
                ink += 1
    return (width, ink / total)

def summarize_candidate_pairs() -> None:
    print("Candidate HEJI2 PUA pairs for primes 29/31 (down/up):")
    aggregate: Dict[Tuple[int, int], Dict[str, Tuple[int, float]]] = {}
    for pair in PRIME_29_31_CANDIDATE_PAIRS:
        aggregate[pair] = {}
        for font_path in FONT_PATHS:
            widths = [glyph_metrics(font_path, cp)[0] for cp in pair]
            inks = [glyph_metrics(font_path, cp)[1] for cp in pair]
            avg_width = int(round(sum(widths) / len(widths)))
            avg_ink = sum(inks) / len(inks)
            aggregate[pair][font_path.name] = (avg_width, avg_ink)
    for pair in PRIME_29_31_CANDIDATE_PAIRS:
        down, up = pair
        print(f"  pair=U+{down:04X}/U+{up:04X}")
        for font_name, (avg_width, avg_ink) in aggregate[pair].items():
            print(f"    {font_name}: avg_width={avg_width} avg_ink={avg_ink:.4f}")
    bracket_pair = min(
        aggregate.items(),
        key=lambda item: sum(info[1] for info in item[1].values()) / len(item[1])
    )[0]
    print(f"Bracket-like (lowest ink) pair: U+{bracket_pair[0]:04X}/U+{bracket_pair[1]:04X}")


def main() -> None:
    mapping = json.loads(MAPPING_PATH.read_text())
    primes = mapping["primeComponents"]
    base_down = codepoint_for_glyph(primes["11"]["1"]["down"][0]["glyph"])
    base_up = codepoint_for_glyph(primes["11"]["1"]["up"][0]["glyph"])
    if base_up != base_down + 1:
        raise ValueError("Unexpected base mapping: 11 up is not +1 from down")

    available_points = all_codepoints(FONT_PATHS)
    resolved: Dict[int, Tuple[int, int]] = {}

    for idx, prime in enumerate(PRIME_SEQUENCE):
        down = base_down + idx * 2
        up = down + 1
        resolved[prime] = (down, up)
        for cp in (down, up):
            if cp not in available_points:
                raise RuntimeError(f"Missing codepoint U+{cp:04X} for prime {prime}")

    print("Resolved HEJI2 prime mappings (11–23):")
    for prime in PRIME_SEQUENCE:
        down, up = resolved[prime]
        print(f"  prime={prime} down=U+{down:04X} up=U+{up:04X}")

    summarize_candidate_pairs()
    print("Current heji2_mapping.json entries (29/31):")
    for prime in (29, 31):
        entry = primes.get(str(prime), {}).get("1", {})
        down = entry.get("down", [{}])[0].get("glyph", "")
        up = entry.get("up", [{}])[0].get("glyph", "")
        if down and up:
            down_cp = codepoint_for_glyph(down)
            up_cp = codepoint_for_glyph(up)
            print(f"  prime={prime} down=U+{down_cp:04X} up=U+{up_cp:04X}")


if __name__ == "__main__":
    main()

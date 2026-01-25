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

ROOT = Path(__file__).resolve().parents[1]
MAPPING_PATH = ROOT / "Tenney" / "Resources" / "heji2_mapping.json"
FONT_PATHS = [
    ROOT / "Tenney" / "Resources" / "Fonts" / "HEJI2" / "HEJI2.otf",
    ROOT / "Tenney" / "Resources" / "Fonts" / "HEJI2" / "HEJI2Text.otf",
]

PRIME_SEQUENCE = [11, 13, 17, 19, 23, 29, 31]


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

    print("Resolved HEJI2 prime mappings:")
    for prime in PRIME_SEQUENCE:
        down, up = resolved[prime]
        print(f"  prime={prime} down=U+{down:04X} up=U+{up:04X}")


if __name__ == "__main__":
    main()

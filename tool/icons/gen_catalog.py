"""Generates lib/ui/icons/project_icons.g.dart from tool/icons/catalog.txt.

    python -I tool/icons/gen_catalog.py

Codepoints come from the lucide_icons_flutter package in the pub cache (the font the app ships), search keywords
from Lucide's tags.json for the same Lucide version (downloaded once into .dart_tool/). Fails on any name the font
doesn't have.
"""

import json
import pathlib
import re
import sys
import urllib.parse
import urllib.request

ROOT = pathlib.Path(__file__).resolve().parents[2]
CATALOG = ROOT / "tool" / "icons" / "catalog.txt"
OUT = ROOT / "lib" / "ui" / "icons" / "project_icons.g.dart"
PACKAGE = "lucide_icons_flutter"


def package_root() -> pathlib.Path:
    config = json.loads((ROOT / ".dart_tool" / "package_config.json").read_text(encoding="utf-8"))
    for p in config["packages"]:
        if p["name"] == PACKAGE:
            uri = urllib.parse.unquote(p["rootUri"])
            return pathlib.Path(re.sub(r"^file:///", "", uri))
    sys.exit(f"{PACKAGE} not found: run flutter pub get")


def lucide_version(pkg: pathlib.Path) -> str:
    match = re.search(r"Lucide version: ([0-9.]+)", (pkg / "README.md").read_text(encoding="utf-8"))
    if not match:
        sys.exit("Lucide version not found in the package README")
    return match.group(1)


def tags(version: str) -> dict:
    cache = ROOT / ".dart_tool" / f"lucide-tags-{version}.json"
    if not cache.exists():
        url = f"https://unpkg.com/lucide-static@{version}/tags.json"
        with urllib.request.urlopen(url, timeout=30) as r:
            cache.write_bytes(r.read())
    return json.loads(cache.read_text(encoding="utf-8"))


def catalog() -> list:
    categories = []
    for line in CATALOG.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if line.startswith("## "):
            categories.append((line[3:], []))
        elif line and not line.startswith("#"):
            names = categories[-1][1]
            names.extend(n for n in line.split() if n not in names)
    return categories


def drawn_codepoints(font: bytes) -> set:
    """Codepoints with a non-empty glyph in a TrueType font (cmap format 4 or 12, loca + glyf). Lucide keeps the
    names and codepoints of removed brand icons (github, figma...) but their glyphs are empty."""
    import struct

    tables = {}
    (count,) = struct.unpack_from(">H", font, 4)
    for i in range(count):
        tag, _, offset, length = struct.unpack_from(">4sIII", font, 12 + 16 * i)
        tables[tag.decode()] = (offset, length)
    head = tables["head"][0]
    (long_loca,) = struct.unpack_from(">h", font, head + 50)
    (glyphs,) = struct.unpack_from(">H", font, tables["maxp"][0] + 4)
    loca = tables["loca"][0]
    if long_loca:
        offsets = struct.unpack_from(f">{glyphs + 1}I", font, loca)
    else:
        offsets = [o * 2 for o in struct.unpack_from(f">{glyphs + 1}H", font, loca)]

    cmap = tables["cmap"][0]
    (subtables,) = struct.unpack_from(">H", font, cmap + 2)
    mapping = {}
    for i in range(subtables):
        _, _, sub = struct.unpack_from(">HHI", font, cmap + 4 + 8 * i)
        sub += cmap
        (fmt,) = struct.unpack_from(">H", font, sub)
        if fmt == 12:
            (groups,) = struct.unpack_from(">I", font, sub + 12)
            for g in range(groups):
                start, end, glyph = struct.unpack_from(">III", font, sub + 16 + 12 * g)
                for c in range(start, end + 1):
                    mapping[c] = glyph + c - start
        elif fmt == 4:
            (seg2,) = struct.unpack_from(">H", font, sub + 6)
            segs = seg2 // 2
            ends = struct.unpack_from(f">{segs}H", font, sub + 14)
            starts = struct.unpack_from(f">{segs}H", font, sub + 16 + seg2)
            deltas = struct.unpack_from(f">{segs}h", font, sub + 16 + 2 * seg2)
            ranges_at = sub + 16 + 3 * seg2
            ranges = struct.unpack_from(f">{segs}H", font, ranges_at)
            for k in range(segs):
                for c in range(starts[k], ends[k] + 1):
                    if c == 0xFFFF:
                        continue
                    if ranges[k] == 0:
                        glyph = (c + deltas[k]) & 0xFFFF
                    else:
                        at = ranges_at + 2 * k + ranges[k] + 2 * (c - starts[k])
                        (glyph,) = struct.unpack_from(">H", font, at)
                        glyph = (glyph + deltas[k]) & 0xFFFF if glyph else 0
                    mapping.setdefault(c, glyph)
    return {c for c, g in mapping.items() if 0 < g < glyphs and offsets[g + 1] > offsets[g]}


def dart_string(s: str) -> str:
    return "'" + s.replace("\\", "\\\\").replace("'", "\\'").replace("$", "\\$") + "'"


def main() -> None:
    pkg = package_root()
    codepoints = json.loads((pkg / "assets" / "codepoints.json").read_text(encoding="utf-8"))
    keywords = tags(lucide_version(pkg))
    categories = catalog()
    missing = sorted({n for _, names in categories for n in names if n not in codepoints})
    if missing:
        sys.exit("Not in the Lucide font: " + " ".join(missing))
    drawn = drawn_codepoints((pkg / "assets" / "lucide.ttf").read_bytes())
    blank = sorted({n for _, names in categories for n in names if codepoints[n] not in drawn})
    if blank:
        sys.exit("Empty glyph in the Lucide font (removed icon): " + " ".join(blank))

    out = [
        "// GENERATED by tool/icons/gen_catalog.py from tool/icons/catalog.txt. Do not edit.",
        "",
        "part of 'project_icons.dart';",
        "",
        "const _font = 'Lucide';",
        f"const _package = '{PACKAGE}';",
        "",
        "const iconCategories = <IconCategory>[",
    ]
    seen = set()
    for category, names in categories:
        out.append(f"  IconCategory({dart_string(category)}, [")
        for name in names:
            words = [name.replace("-", " "), *keywords.get(name, []), category.lower()]
            text = " ".join(dict.fromkeys(w.lower() for w in words))
            out.append(
                f"    ProjectIcon({dart_string(name)}, IconData(0x{codepoints[name]:x}, fontFamily: _font, "
                f"fontPackage: _package), {dart_string(text)}),"
            )
            seen.add(name)
        out.append("  ]),")
    out.append("];")
    out.append("")
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text("\n".join(out), encoding="utf-8", newline="\n")
    print(f"{len(seen)} icons in {len(categories)} categories -> {OUT.relative_to(ROOT)}")


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""Bundle an addon into one Luau file: its WebAssembly side modules (one per Dear ImGui branch, translated by Spider), the
enums extracted from its headers, the shared helpers in luau/addons/common.luau and its Luau source, under the same header
and comment rules as the bundles (see bundle.py).

The file returns what the addon's source returns. The source receives (Modules, Enums, Common): Modules = { <branch> = {
MemorySize, MemoryAlign, TableSize, Instantiate(imports) } }, which the runtime links into the running Dear ImGui context.
Common receives the signatures of the modules' exported functions, which are the same for every branch.
"""
from __future__ import annotations

import argparse
import datetime
import json
import pathlib
import re
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from bundle import LEXEMES, header, strip_comments  # noqa: E402

IDENTIFIER = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*$")


def luau_table(value: dict) -> str:
    """A Luau table literal for nested dicts of numbers."""
    items = []
    for key, item in value.items():
        field = key if IDENTIFIER.match(key) else f'["{key}"]'
        items.append(f"{field} = {luau_table(item) if isinstance(item, dict) else int(item)}")
    return "{ " + ", ".join(items) + " }"


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", required=True, help="the addon's Luau source")
    parser.add_argument("--common", required=True, help="luau/addons/common.luau")
    parser.add_argument("--module", action="append", default=[], metavar="BRANCH=LUAU,JSON",
                        help="a translated side module and the JSON build.py wrote for it (repeat per branch)")
    parser.add_argument("--enums", help="JSON {table: {name: value}} extracted from the addon's headers")
    parser.add_argument("--version", default="1.92.9b")
    parser.add_argument("--date", default=datetime.date.today().isoformat())
    parser.add_argument("--optimize-directive", action="store_true")
    parser.add_argument("--notice")
    parser.add_argument("--out", required=True)
    args = parser.parse_args()

    def read(path: str) -> str:
        return strip_comments(pathlib.Path(path).read_text(encoding="utf-8"), path)

    top = header(args.date, args.version, args.optimize_directive, args.notice)
    enums = json.loads(pathlib.Path(args.enums).read_text(encoding="utf-8")) if args.enums else {}
    parts = [top, "local Modules = {}\n"]
    signatures = None
    for spec in args.module:
        branch, _, paths = spec.partition("=")
        luau_path, json_path = paths.split(",")
        info = json.loads(pathlib.Path(json_path).read_text(encoding="utf-8"))
        if signatures is not None and info["signatures"] != signatures:
            raise AssertionError(f"the {branch} module's exports have other signatures than the first module's")
        signatures = info["signatures"]
        parts += [
            f"Modules.{branch} = {{ MemorySize = {info['memory_size']}, MemoryAlign = {info['memory_align']}, "
            f"TableSize = {info['table_size']}, Instantiate = function(imports)\n",
            "local instantiate = (function()\n",
            read(luau_path),
            "return function(imports)\n"
            "\trt_import_map = imports\n"
            "\trt_export_map = {}\n"
            "\tmodule()\n"
            "\treturn rt_export_map\n"
            "end\n"
            "end)()\n",
            "return instantiate(imports)\n",
            "end }\n",
        ]
    parts += [
        f"local Enums = {luau_table(enums)}\n",
        "local Signatures = { " + ", ".join(f'{name} = "{signature}"' for name, signature in sorted(signatures.items())) + " }\n",
        "local Common = (function(...)\n", read(args.common), "end)(Signatures)\n",
        "return (function(...)\n", read(args.source), "end)(Modules, Enums, Common)\n",
    ]
    source = "".join(parts)
    leftover = next((m for m in LEXEMES.finditer(source) if m.group("comment") is not None and m.start() >= len(top)), None)
    if leftover is not None:
        raise AssertionError(f"a comment is left in the addon: {leftover.group(0)[:60]!r}")

    out = pathlib.Path(args.out)
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(source, encoding="utf-8", newline="\n")
    print(f"wrote {out} ({out.stat().st_size / 1e6:.2f} MB)")


if __name__ == "__main__":
    main()

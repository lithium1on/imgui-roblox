#!/usr/bin/env python3
"""Bundle the Spider translation, the generated bindings, the render modes and the runtime into one Luau file.

The file starts with the watermark, the build date and the Dear ImGui version, then the optional --!optimize 2 directive
and --notice line. Every other comment is removed: each part's token stream is checked to be unchanged by the removal,
and the finished file is checked to have no comment after the header.
"""
from __future__ import annotations

import argparse
import datetime
import pathlib
import re
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from minify_luau import tokenize  # noqa: E402

WATERMARK = r"""    ___ __  __    _
   / (_) /_/ /_  (_)_  ______ ___
  / / / __/ __ \/ / / / / __ `__ \
 / / / /_/ / / / / /_/ / / / / / /
/_/_/\__/_/ /_/_/\__,_/_/ /_/ /_/
"""

LEXEMES = re.compile(
    r"(?P<string>\"(?:[^\"\\\n]|\\.)*\"|'(?:[^'\\\n]|\\.)*'|\[(?P<seq>=*)\[.*?\](?P=seq)\])"
    r"|(?P<comment>--\[(?P<ceq>=*)\[.*?\](?P=ceq)\]|--[^\n]*)",
    re.S,
)


def strip_comments(source: str, name: str) -> str:
    if "`" in LEXEMES.sub("", source):
        raise ValueError(f"{name}: interpolated strings are not supported by the comment stripper")

    def replace(m: re.Match) -> str:
        if m.group("comment") is None:
            return m.group(0)
        newlines = m.group(0).count("\n")
        return "\n" * newlines if newlines else " "

    stripped = LEXEMES.sub(replace, source)
    lines = [line.rstrip() for line in stripped.split("\n")]
    result = "\n".join(line for line in lines if line.strip()) + "\n"
    if [token[:2] for token in tokenize(result)] != [token[:2] for token in tokenize(source)]:
        raise AssertionError(f"{name}: removing comments changed the code")
    return result


def header(date: str, version: str, optimize_directive: bool, notice: str | None) -> str:
    lines = ["--" + line.rstrip() for line in WATERMARK.rstrip("\n").split("\n")]
    lines += ["--", f"-- built {date}", f"-- dear imgui {version}"]
    if optimize_directive:
        lines.append("--!optimize 2")
    if notice:
        lines.append(f"-- {notice}")
    return "\n".join(lines) + "\n"


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--wasm-luau", required=True)
    parser.add_argument("--runtime", required=True)
    parser.add_argument("--renderer", required=True)
    parser.add_argument("--bindings")
    parser.add_argument("--version", default="1.92.9b")
    parser.add_argument("--date", default=datetime.date.today().isoformat())
    parser.add_argument("--optimize-directive", action="store_true", help="add --!optimize 2 to the header")
    parser.add_argument("--notice", help="one extra header line, e.g. license notices")
    parser.add_argument("--out", required=True)
    args = parser.parse_args()

    def read(path: str) -> str:
        return strip_comments(pathlib.Path(path).read_text(encoding="utf-8"), path)

    top = header(args.date, args.version, args.optimize_directive, args.notice)
    parts = [
        top,
        "local WasmInstantiate = (function()\n",
        read(args.wasm_luau),
        "return function(imports)\n"
        "\trt_import_map = imports\n"
        "\trt_export_map = {}\n"
        "\tmodule()\n"
        "\treturn rt_export_map\n"
        "end\n"
        "end)()\n",
        "local InstallBindings = (function()\n",
        read(args.bindings) if args.bindings else "return nil\n",
        "end)()\n",
        "local Renderer = (function()\n",
        read(args.renderer),
        "end)()\n",
        "return (function(...)\n",
        read(args.runtime),
        "end)(WasmInstantiate, InstallBindings, Renderer)\n",
    ]
    source = "".join(parts)
    leftover = next((m for m in LEXEMES.finditer(source) if m.group("comment") is not None and m.start() >= len(top)), None)
    if leftover is not None:
        raise AssertionError(f"a comment is left in the bundle: {leftover.group(0)[:60]!r}")

    out = pathlib.Path(args.out)
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(source, encoding="utf-8", newline="\n")
    print(f"wrote {out} ({out.stat().st_size / 1e6:.2f} MB)")


if __name__ == "__main__":
    main()

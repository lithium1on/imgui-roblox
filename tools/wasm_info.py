#!/usr/bin/env python3
"""Reads what the build needs from a WebAssembly module: its imports, its exports and, for side modules, the memory and
table sizes in the dylink.0 section."""
from __future__ import annotations

import pathlib

KINDS = {0: "func", 1: "table", 2: "memory", 3: "global", 4: "tag"}


def _leb(data: bytes, pos: int) -> tuple[int, int]:
    result = shift = 0
    while True:
        byte = data[pos]
        pos += 1
        result |= (byte & 0x7F) << shift
        shift += 7
        if byte < 0x80:
            return result, pos


def _name(data: bytes, pos: int) -> tuple[str, int]:
    length, pos = _leb(data, pos)
    return data[pos:pos + length].decode("utf-8"), pos + length


def _skip_limits(data: bytes, pos: int) -> int:
    flags, pos = _leb(data, pos)
    _, pos = _leb(data, pos)
    if flags & 1:
        _, pos = _leb(data, pos)
    return pos


def read_module(path: str | pathlib.Path) -> dict:
    """{"imports": [(module, name, kind)], "exports": [(name, kind)], "memory_size", "memory_align", "table_size"}"""
    data = pathlib.Path(path).read_bytes()
    if data[:4] != b"\0asm":
        raise ValueError(f"{path} is not a WebAssembly module")
    info = {"imports": [], "exports": [], "memory_size": 0, "memory_align": 0, "table_size": 0}
    pos = 8
    while pos < len(data):
        section = data[pos]
        size, pos = _leb(data, pos + 1)
        end = pos + size
        if section == 0:
            name, p = _name(data, pos)
            while name == "dylink.0" and p < end:
                subsection = data[p]
                subsection_size, p = _leb(data, p + 1)
                if subsection == 1:
                    q = p
                    info["memory_size"], q = _leb(data, q)
                    info["memory_align"], q = _leb(data, q)
                    info["table_size"], q = _leb(data, q)
                p += subsection_size
        elif section == 2:
            count, p = _leb(data, pos)
            for _ in range(count):
                module, p = _name(data, p)
                field, p = _name(data, p)
                kind = data[p]
                p += 1
                if kind == 0:
                    _, p = _leb(data, p)
                elif kind == 1:
                    p = _skip_limits(data, p + 1)
                elif kind == 2:
                    p = _skip_limits(data, p)
                elif kind == 3:
                    p += 2
                elif kind == 4:
                    _, p = _leb(data, p + 1)
                info["imports"].append((module, field, KINDS[kind]))
        elif section == 7:
            count, p = _leb(data, pos)
            for _ in range(count):
                field, p = _name(data, p)
                kind = data[p]
                _, p = _leb(data, p + 1)
                info["exports"].append((field, KINDS[kind]))
        pos = end
    return info


if __name__ == "__main__":
    import json
    import sys

    print(json.dumps(read_module(sys.argv[1]), indent=1))

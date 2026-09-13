#!/usr/bin/env python3
"""Peephole optimizations for Spider's Luau output.

Spider carries f32 values as their IEEE-754 bit patterns and converts with
    from_bits_f32(bits)   -> buffer.writeu32 + buffer.readf32
    into_bits_f32(number) -> buffer.writef32 + buffer.readu32
and wraps i32 arithmetic with bit32.bor(x, 0). Rewrites, all exact for Dear ImGui (only NaN payload bits could differ in
3 and 4):
    1. from_bits_f32((0xXXXXXXXX))                  -> numeric literal             (every finite f32 is exactly a double)
    2. from_bits_f32((into_bits_f32((E))))          -> vector.create(E, 0, 0).x    (vector components are float32)
    3. into_bits_f32((from_bits_f32((E))))          -> (E)                         (bits -> float -> bits)
    4. buffer_write_u32(M, A, (into_bits_f32((E)))) -> buffer.writef32(M, A, E)
    5. bit32_or((X) + (Y), (0)), and with -         -> (((X) + (Y)) % 4294967296)  (the same for every integer below 2^53)
    6. (bit32_xor(X, 2^31) - 2^31) compared with the same form of Y, or with a constant, compares the bit32_xor results
Measured with tests/harness/bench.luau: 3-6% faster frames at Luau -O2 and 6-9% at -O1.
usage: optimize_luau.py input.luau output.luau
"""
from __future__ import annotations

import collections
import pathlib
import re
import struct
import sys

sys.setrecursionlimit(100000)

PRELUDE = """\
local rbx_vector_create = vector.create
local rbx_buffer_write_f32 = buffer.writef32

"""

RULES = [
    (r"from_bits_f32\(\(", "from_bits"),
    (r"into_bits_f32\(\(", "into_bits"),
    (r"buffer_write_u32\(", "store"),
    (r"bit32_or\(\(", "wrap"),
]

SIGNED = r"\(\(bit32_xor\((\w+), \(2147483648\)\)\) - \(2147483648\)\)"


class Rewriter:
    def __init__(self, text: str):
        self.text = text
        self.counts: collections.Counter[str] = collections.Counter()
        self.close_cache: dict[int, int] = {}
        self.pattern = re.compile("|".join(f"(?P<{name}>{regex})" for regex, name in RULES))

    def match_close(self, open_index: int) -> int:
        cached = self.close_cache.get(open_index)
        if cached is not None:
            return cached
        text = self.text
        depth = 0
        i = open_index
        n = len(text)
        while i < n:
            c = text[i]
            if c == "(":
                depth += 1
            elif c == ")":
                depth -= 1
                if depth == 0:
                    self.close_cache[open_index] = i
                    return i
            elif c == '"' or c == "'":
                quote = c
                i += 1
                while i < n and text[i] != quote:
                    if text[i] == "\\":
                        i += 1
                    i += 1
            i += 1
        raise ValueError(f"unbalanced parenthesis at {open_index}")

    def wrapped(self, start: int, end: int) -> bool:
        """text[start:end] is one parenthesized expression"""
        return end - start >= 2 and self.text[start] == "(" and self.match_close(start) == end - 1

    def call_argument(self, start: int, name: str):
        """For name((E)) at start: (E start, E end, end of the call), or None"""
        outer = start + len(name)
        inner = outer + 1
        close = self.match_close(outer)
        if self.text[inner] != "(" or self.match_close(inner) != close - 1:
            return None
        return inner + 1, close - 1, close + 1

    def split_arguments(self, open_index: int, close_index: int) -> list[tuple[int, int]]:
        text = self.text
        arguments = []
        i = start = open_index + 1
        while i < close_index:
            c = text[i]
            if c == "(":
                i = self.match_close(i) + 1
                continue
            if c == ",":
                arguments.append((start, i))
                start = i + 2 if text[i + 1] == " " else i + 1
            elif c == '"' or c == "'":
                quote = c
                i += 1
                while text[i] != quote:
                    if text[i] == "\\":
                        i += 1
                    i += 1
            i += 1
        arguments.append((start, close_index))
        return arguments

    # Each rule returns (pieces, end): strings are copied, (start, end) spans are rewritten recursively.
    def from_bits(self, start: int):
        span = self.call_argument(start, "from_bits_f32")
        if span is None:
            return None
        e_start, e_end, end = span
        text = self.text
        constant = re.fullmatch(r"0x([0-9A-Fa-f_]+)", text[e_start:e_end])
        if constant:
            bits = int(constant.group(1).replace("_", ""), 16)
            value = struct.unpack("<f", struct.pack("<I", bits))[0]
            if value != value or value in (float("inf"), float("-inf")) or bits == 0x80000000:
                return None
            self.counts["constant"] += 1
            literal = repr(value) if not value.is_integer() or abs(value) >= 1e15 else str(int(value))
            return [f"({literal})" if literal.startswith("-") else literal], end
        if text.startswith("into_bits_f32((", e_start):
            inner = self.call_argument(e_start, "into_bits_f32")
            if inner is not None and inner[2] == e_end:
                self.counts["fround"] += 1
                return ["rbx_vector_create((", (inner[0], inner[1]), "), 0, 0).x"], end
        return None

    def into_bits(self, start: int):
        span = self.call_argument(start, "into_bits_f32")
        if span is None:
            return None
        e_start, e_end, end = span
        if self.text.startswith("from_bits_f32((", e_start):
            inner = self.call_argument(e_start, "from_bits_f32")
            if inner is not None and inner[2] == e_end:
                self.counts["identity"] += 1
                return ["(", (inner[0], inner[1]), ")"], end
        return None

    def store(self, start: int):
        open_index = start + len("buffer_write_u32")
        close = self.match_close(open_index)
        arguments = self.split_arguments(open_index, close)
        if len(arguments) != 3:
            return None
        value_start, value_end = arguments[2]
        if not (self.wrapped(value_start, value_end) and self.text.startswith("into_bits_f32((", value_start + 1)):
            return None
        inner = self.call_argument(value_start + 1, "into_bits_f32")
        if inner is None or inner[2] != value_end - 1:
            return None
        if self.text.startswith("from_bits_f32((", inner[0]):
            round_trip = self.call_argument(inner[0], "from_bits_f32")
            if round_trip is not None and round_trip[2] == inner[1]:
                return None  # bits -> float -> bits: rule 3 keeps the plain u32 store
        self.counts["store"] += 1
        return ["rbx_buffer_write_f32(", arguments[0], ", ", arguments[1], ", (", (inner[0], inner[1]), "))"], close + 1

    def wrap(self, start: int):
        open_index = start + len("bit32_or")
        close = self.match_close(open_index)
        arguments = self.split_arguments(open_index, close)
        if len(arguments) != 2 or self.text[arguments[1][0]:arguments[1][1]] != "(0)":
            return None
        operand_start, operand_end = arguments[0]
        left_close = self.match_close(operand_start)
        if self.text[left_close + 1:left_close + 4] not in (" + ", " - ") or not self.wrapped(left_close + 4, operand_end):
            return None
        self.counts["wrap"] += 1
        return ["((", arguments[0], ") % 4294967296)"], close + 1

    def rewrite(self, start: int, end: int, out: list[str]) -> None:
        i = start
        while True:
            m = self.pattern.search(self.text, i, end)
            if m is None:
                out.append(self.text[i:end])
                return
            out.append(self.text[i:m.start()])
            result = getattr(self, m.lastgroup)(m.start())
            if result is None:
                out.append(self.text[m.start()])
                i = m.start() + 1
                continue
            pieces, i = result
            for piece in pieces:
                if isinstance(piece, str):
                    out.append(piece)
                else:
                    self.rewrite(piece[0], piece[1], out)


def main() -> None:
    source = pathlib.Path(sys.argv[1]).read_text(encoding="utf-8")
    rewriter = Rewriter(source)
    out: list[str] = [PRELUDE]
    rewriter.rewrite(0, len(source), out)
    result = "".join(out)

    result, equal = re.subn(SIGNED + r" (==|~=) " + SIGNED, r"(\1) \2 (\3)", result)
    result, ordered = re.subn(
        SIGNED + r" (<|<=|>|>=) " + SIGNED, r"(bit32_xor(\1, (2147483648))) \2 (bit32_xor(\3, (2147483648)))", result
    )
    result, constant = re.subn(
        SIGNED + r" (<|<=|>|>=) \((\d+)\)",
        lambda m: f"(bit32_xor({m.group(1)}, (2147483648))) {m.group(2)} ({int(m.group(3)) + 2147483648})",
        result,
    )
    rewriter.counts["signed compare"] = equal + ordered + constant

    pathlib.Path(sys.argv[2]).write_text(result, encoding="utf-8", newline="\n")
    counts = ", ".join(f"{count} {name}" for name, count in rewriter.counts.items())
    print(f"optimize_luau: {counts} ({len(source) / 1e6:.2f} MB -> {len(result) / 1e6:.2f} MB)")


if __name__ == "__main__":
    main()

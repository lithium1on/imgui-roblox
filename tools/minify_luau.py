#!/usr/bin/env python3
"""Shrink Spider's Luau output without changing what it does.

    1. Renames Spider's locals (loc_N_) and the runtime helpers declared at the top of the chunk to the shortest names
       nothing else in the chunk uses, most frequent first. The mapping is global, so it stays injective in every scope.
    2. Inside the module function, drops parentheses around a single name, number, true, false or nil unless they are
       call arguments or a parameter list.
    3. Drops comments, indentation and every space or newline the lexer does not need. A newline stays in front of a
       "(" that started a line, so no statement can turn into a call on the previous one.
The result is tokenized again and compared with the expected token stream before it is written.
usage: minify_luau.py input.luau output.luau
"""
from __future__ import annotations

import collections
import pathlib
import re
import sys

KEYWORDS = {
    "and", "break", "do", "else", "elseif", "end", "false", "for", "function", "if", "in", "local", "nil", "not", "or",
    "repeat", "return", "then", "true", "until", "while", "continue", "type", "export", "typeof",
}
VALUE_KEYWORDS = {"true", "false", "nil"}
# Referenced by the code tools/bundle.py wraps around the chunk
KEEP = {"module", "rt_import_map", "rt_export_map", "imports"}

TOKEN = re.compile(
    r"(?P<ws>[ \t\r]+)"
    r"|(?P<nl>\n)"
    r"|(?P<comment>--\[(?P<ceq>=*)\[.*?\](?P=ceq)\]|--[^\n]*)"
    r"|(?P<string>\"(?:[^\"\\\n]|\\.)*\"|'(?:[^'\\\n]|\\.)*'|\[(?P<seq>=*)\[.*?\](?P=seq)\])"
    r"|(?P<number>(?:\d|\.\d)(?:[eE][+-]|[\w.])*)"
    r"|(?P<name>[A-Za-z_]\w*)"
    r"|(?P<op>\.\.\.|\.\.=|\.\.|==|~=|<=|>=|//=|//|->|::|\+=|-=|\*=|/=|%=|\^=|[-+*/%^#&~|<>=(){}\[\];:,.?@!`])",
    re.S,
)
WORD = ("name", "number")


def tokenize(text: str) -> list[tuple[str, str, bool]]:
    """(kind, value, starts a line) for every token; comments and whitespace are dropped."""
    tokens = []
    pos, newline = 0, True
    for m in TOKEN.finditer(text):
        if m.start() != pos:
            raise ValueError(f"cannot tokenize at offset {pos}: {text[pos:pos + 40]!r}")
        pos = m.end()
        kind = m.lastgroup
        if kind in ("ceq", "seq"):
            kind = "comment" if m.group("comment") is not None else "string"
        if kind == "nl":
            newline = True
        elif kind not in ("ws", "comment"):
            if kind == "op" and m.group() == "`":
                raise ValueError("interpolated strings are not supported")
            tokens.append((kind, m.group(), newline))
            newline = False
    if pos != len(text):
        raise ValueError(f"cannot tokenize at offset {pos}")
    return tokens


def short_names(forbidden: set[str]):
    first = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ_"
    rest = first + "0123456789"
    suffixes = [""]
    while True:
        for c in first:
            for suffix in suffixes:
                name = c + suffix
                if name not in forbidden and name not in KEYWORDS:
                    yield name
        suffixes = [c + suffix for c in rest for suffix in suffixes]


def plan_renames(text: str, tokens) -> dict[str, str]:
    helpers = set(re.findall(r"^local function (\w+)", text, re.M)) | set(re.findall(r"^local (\w+)\s*=", text, re.M))
    helpers |= set(re.findall(r"^\s*local (stack) = stack_acquire", text, re.M))
    counts = collections.Counter()
    unsafe = set(KEEP)
    for i, (kind, value, _) in enumerate(tokens):
        if kind != "name":
            continue
        is_local = re.fullmatch(r"loc_\d+_", value) is not None
        if not is_local and value not in helpers:
            continue
        counts[value] += 1
        prev = tokens[i - 1][1] if i else ""
        nxt = tokens[i + 1][1] if i + 1 < len(tokens) else ""
        if prev in (".", ":", "::"):
            unsafe.add(value)  # a field or method name
        elif not is_local and prev in ("{", ",", ";") and nxt == "=":
            unsafe.add(value)  # possibly a table constructor key
    for name in unsafe:
        counts.pop(name, None)
    forbidden = {value for kind, value, _ in tokens if kind == "name" and value not in counts} | KEEP
    generator = short_names(forbidden)
    return {name: next(generator) for name, _ in counts.most_common()}


def unwrap_atoms(tokens) -> list[tuple[str, str, bool]]:
    start = next(
        (i for i in range(len(tokens) - 1) if tokens[i][1] == "module" and tokens[i + 1][1] == "="),
        len(tokens),
    )
    kept = list(tokens[:start])
    i, n = start, len(tokens)
    while i < n:
        kind, value, line_start = tokens[i]
        if value == "(" and i + 2 < n and tokens[i + 2][1] == ")":
            inner_kind, inner_value, _ = tokens[i + 1]
            atom = inner_kind == "number" or (inner_kind == "name" and (inner_value not in KEYWORDS or inner_value in VALUE_KEYWORDS))
            prev_kind, prev_value, _ = kept[-1] if kept else ("op", ";", True)
            if prev_kind == "name":
                # f(x) is a call and function(x) a parameter list; after a keyword such as return or then it is a value
                wrapped_value = prev_value in KEYWORDS and prev_value not in VALUE_KEYWORDS and prev_value != "function"
            elif prev_kind == "string":
                wrapped_value = False
            else:
                wrapped_value = prev_value not in (")", "]", "}")
            if atom and wrapped_value:
                kept.append((inner_kind, inner_value, line_start))
                i += 3
                continue
        kept.append((kind, value, line_start))
        i += 1
    return kept


def separator(prev_kind: str, prev_value: str, kind: str, value: str, line_start: bool) -> str:
    if line_start and value == "(":
        return "\n"
    if prev_kind in WORD and kind in WORD:
        return " "
    if prev_kind == "number" and re.match(r"[\w.]", value):
        return " "
    if prev_kind == "op" and kind == "op":
        if prev_value == "[" and value[0] in "[=":
            return " "
        merged = TOKEN.match(prev_value + value)
        if merged is None or merged.group() != prev_value:
            return " "
    return ""


def minify(text: str):
    tokens = tokenize(text)
    renames = plan_renames(text, tokens)
    kept = unwrap_atoms(tokens)

    out = []
    expected = []
    prev_kind = prev_value = None
    for kind, value, line_start in kept:
        if kind == "name":
            value = renames.get(value, value)
        if prev_kind is not None:
            out.append(separator(prev_kind, prev_value, kind, value, line_start))
        out.append(value)
        expected.append((kind, value))
        prev_kind, prev_value = kind, value
    result = "".join(out) + "\n"

    actual = [(kind, value) for kind, value, _ in tokenize(result)]
    if actual != expected:
        for index, (a, b) in enumerate(zip(actual, expected)):
            if a != b:
                raise AssertionError(f"token {index} changed: got {a}, expected {b}")
        raise AssertionError(f"token count changed: {len(actual)} != {len(expected)}")
    return result, len(renames), (len(tokens) - len(kept)) // 2


def main() -> None:
    source = pathlib.Path(sys.argv[1]).read_text(encoding="utf-8")
    result, renamed, parens = minify(source)
    pathlib.Path(sys.argv[2]).write_text(result, encoding="utf-8", newline="\n")
    print(
        f"minify_luau: {renamed} names shortened, {parens} parenthesized atoms unwrapped "
        f"({len(source) / 1e6:.2f} MB -> {len(result) / 1e6:.2f} MB)"
    )


if __name__ == "__main__":
    main()

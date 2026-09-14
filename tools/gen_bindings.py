#!/usr/bin/env python3
"""Generate the Luau-facing Dear ImGui API from dear_bindings metadata (dcimgui.json).

Outputs
  --out-cpp   flat extern "C" wrappers (scalars and pointers only) compiled into the WebAssembly module
  --out-luau  a chunk returning install(ImGui, Api) that defines ImGui.* functions, enums and struct handles

Luau marshalling rules
  ImVec2 <- Vector2 or {x, y}               ImVec4 <- Color3 or {x, y, z, w}
  bool* / int* / float* / double*           value in, updated value returned after the function result
  out_* pointers                            not parameters, their values are returned
  float[N] / int[N]                         table (or Color3), updated in place and returned
  char* buf + size_t buf_size               string in, edited string returned (extra trailing `capacity` parameter)
  const char* const items[] + items_count   array of strings
  const float* values + values_count        array of numbers
  const ImVec2* points + num_points         array of Vector2
  const char* x_begin + x_end               a single string
  Pointers to ImDrawList, ImGuiStyle, ImGuiIO, ... come back as handles exposing fields and methods.
  Format-string functions (Text, TextColored, ...) take Luau string.format arguments.
"""
from __future__ import annotations

import argparse
import json
import pathlib
import re

LUA_RESERVED = {
    "and", "break", "do", "else", "elseif", "end", "false", "for", "function", "if", "in", "local", "nil", "not", "or",
    "repeat", "return", "then", "true", "until", "while", "continue", "type", "export",
    # locals used inside the generated wrappers
    "f", "r", "M", "E",
}

# Functions that would break the runtime's frame loop or that need things Luau cannot provide.
SKIP_FUNCTIONS = {
    "ImGui_CreateContext", "ImGui_DestroyContext", "ImGui_GetCurrentContext", "ImGui_SetCurrentContext",
    "ImGui_NewFrame", "ImGui_EndFrame", "ImGui_Render", "ImGui_GetDrawData",
    "ImGui_SetAllocatorFunctions", "ImGui_GetAllocatorFunctions",
    "ImGui_DebugCheckVersionAndDataLayout", "ImGui_LoadIniSettingsFromDisk", "ImGui_SaveIniSettingsToDisk",
    # Docking branch: platform windows for multi-viewports, which a single Roblox screen cannot have
    "ImGui_UpdatePlatformWindows", "ImGui_RenderPlatformWindowsDefault", "ImGui_RenderPlatformWindowsDefaultEx",
    "ImGui_DestroyPlatformWindows",
}
SKIP_NAME_PARTS = ("Scalar",)
# String arguments without a C++ default that Dear ImGui still accepts as NULL (MenuItem(label, NULL, &selected))
NULLABLE_STRINGS = {"shortcut"}

# C++ struct -> Luau table holding its methods (handles returned for pointers to these types use it as metatable)
HANDLE_CLASSES = {
    "ImDrawList": "DrawList",
    "ImGuiStyle": "Style",
    "ImGuiIO": "IO",
    "ImGuiViewport": "Viewport",
    "ImGuiStorage": "Storage",
    "ImGuiPayload": "Payload",
}
FIELD_CLASSES = ["ImGuiStyle", "ImGuiIO", "ImGuiViewport", "ImGuiPayload"]

SIGNED = {"int", "signed int", "short", "signed short", "char", "signed char", "long", "signed long"}
UNSIGNED = {"unsigned int", "unsigned short", "unsigned char", "unsigned long", "size_t"}
INT64 = {"long long", "signed long long", "unsigned long long"}
BUILTIN_SCALARS = SIGNED | UNSIGNED | INT64 | {"float", "double", "bool"}

SCALAR_SLOTS = {
    "bool": ("BoolSlot", "readu8(M, {p}) ~= 0"),
    "int": ("I32Slot", "ReadI32({p})"),
    "signed int": ("I32Slot", "ReadI32({p})"),
    "unsigned int": ("U32Slot", "readu32(M, {p})"),
    "float": ("F32Slot", "readf32(M, {p})"),
    "double": ("F64Slot", "readf64(M, {p})"),
}

FIELD_KINDS = {
    "float": "f32", "double": "f64", "bool": "bool",
    "int": "i32", "signed int": "i32", "unsigned int": "u32", "size_t": "u32",
    "short": "i16", "signed short": "i16", "unsigned short": "u16",
    "char": "i8", "signed char": "i8", "unsigned char": "u8",
    "ImVec2": "vec2", "ImVec4": "vec4", "const char*": "cstr",
}

FLOAT_LITERAL = re.compile(r"(?<![\w.])(\d+\.\d*|\.\d+|\d+)[fF]\b")
VEC_DEFAULT = re.compile(r"^ImVec([24])\((.*)\)$")
ARRAY_DECL = re.compile(r"^(.+?)\s*\[(\w+)\]$")


class Unsupported(Exception):
    pass


def norm(decl: str) -> str:
    return " ".join(decl.split())


def lua_ident(name: str) -> str:
    return name + "_" if name in LUA_RESERVED else name


def lua_number(value) -> str:
    if isinstance(value, bool):
        return "1" if value else "0"
    if isinstance(value, float):
        if value.is_integer() and abs(value) < 1e15:
            return str(int(value))
        return repr(value)
    return str(value)


def split_pointer(decl: str):
    d = norm(decl)
    if not d.endswith("*") or d.endswith("**"):
        return None
    base = d[:-1].strip()
    const = base.startswith("const ")
    if const:
        base = base[6:].strip()
    return const, base


def strip_enum_prefix(enum_name: str) -> str:
    name = enum_name.rstrip("_")
    for prefix in ("ImGui", "Im"):
        if name.startswith(prefix):
            return name[len(prefix):]
    return name


class Model:
    def __init__(self, data: dict):
        self.typedefs = {t["name"]: norm(t["type"]["declaration"]) for t in data["typedefs"]}
        self.enums = [e for e in data["enums"] if not e.get("is_internal")]
        self.enum_values = {}
        for enum in data["enums"]:
            for element in enum["elements"]:
                if element.get("value") is not None:
                    self.enum_values[element["name"]] = element["value"]
        self.structs = {s["name"]: s for s in data["structs"]}
        self.functions = [f for f in data["functions"] if not f.get("is_internal")]
        self.by_name = {f["name"]: f for f in self.functions}
        self.default_helpers = {f["name"] for f in self.functions if f.get("is_default_argument_helper")}

    def resolve(self, decl: str) -> str:
        decl = norm(decl)
        for _ in range(16):
            target = self.typedefs.get(decl)
            if target is None:
                break
            if "(*" in target:
                return "fnptr"
            decl = target
        return decl

    def eval_number(self, text: str):
        expr = text.strip()
        replacements = {
            "FLT_MAX": "3.4028234663852886e38",
            "FLT_MIN": "1.1754943508222875e-38",
            "sizeof(float)": "4",
            "IM_COL32_WHITE": "4294967295",
            "IM_COL32_BLACK": "4278190080",
        }
        for key, value in replacements.items():
            expr = expr.replace(key, value)
        expr = FLOAT_LITERAL.sub(lambda m: m.group(1) + ("0" if m.group(1).endswith(".") else ""), expr)
        try:
            return eval(expr, {"__builtins__": {}}, dict(self.enum_values))  # noqa: S307 - trusted metadata
        except Exception as exc:  # pragma: no cover - reported to the user
            raise Unsupported(f"default value {text!r}") from exc

    def vec_default(self, text: str, count: int) -> list[str]:
        match = VEC_DEFAULT.match(text.strip())
        if not match or int(match.group(1)) != count:
            raise Unsupported(f"default value {text!r}")
        parts = [p.strip() for p in match.group(2).split(",")]
        if len(parts) != count:
            raise Unsupported(f"default value {text!r}")
        return [lua_number(self.eval_number(p)) for p in parts]

    def luau_name(self, func: dict) -> str:
        cls = func.get("original_class")
        prefix = f"{cls}_" if cls else "ImGui_"
        short = func["name"][len(prefix):]
        if short.endswith("Ex") and (prefix + short[:-2]) in self.default_helpers:
            short = short[:-2]
        return short


class Wrapper:
    def __init__(self, model: Model, func: dict):
        self.model = model
        self.func = func
        self.name = func["name"]
        self.cls = func.get("original_class")
        self.self_expr = None
        self.c_params: list[str] = []
        self.call_args: list[str] = []
        self.lua_params: list[str] = []
        self.lua_extra_params: list[str] = []
        self.pre: list[str] = []
        self.call_exprs: list[str] = []
        self.post_returns: list[str] = []
        self.reads_memory = False
        self.ret_ctype = "void"
        self.ret_body = "{call};"
        self.ret_lua: list[str] = []

        args = func["arguments"]
        index = 0
        while index < len(args):
            index += self.add_arg(args, index)
        self.plan_return()

    # ---------------------------------------------------------------- arguments
    def add_arg(self, args: list[dict], i: int) -> int:
        m = self.model
        a = args[i]
        name = a["name"]
        decl = norm(a["type"]["declaration"])
        default = a.get("default_value")
        nxt = args[i + 1] if i + 1 < len(args) else None
        nxt_decl = norm(nxt["type"]["declaration"]) if nxt else ""
        nxt_resolved = m.resolve(nxt_decl) if nxt else ""
        lua = lua_ident(name)
        c = "a_" + name
        resolved = m.resolve(decl)
        nullable = default in ("NULL", "nullptr")
        is_ref = bool(a["type"]["description"].get("is_reference"))  # C++ reference exposed as a pointer

        if a.get("is_instance_pointer"):
            self.c_params.append(f"void* {c}")
            self.self_expr = f"(({self.cls}*){c})"
            self.lua_params.append("self")
            self.call_exprs.append("Ptr(self)")
            return 1

        if decl == "const char*" and name.endswith("_begin") and nxt and nxt_decl == "const char*" and nxt["name"] == name[:-6] + "_end":
            base = lua_ident(name[:-6])
            self.c_params += [f"const char* {c}", f"const char* a_{nxt['name']}"]
            self.call_args += [c, f"a_{nxt['name']}"]
            self.lua_params.append(base)
            self.pre.append(f"local p_{name} = Str({base})")
            self.pre.append(f"local e_{name} = p_{name} + LastLen")
            self.call_exprs += [f"p_{name}", f"e_{name}"]
            return 2

        if decl == "const char*" and name.endswith("_end") and nullable:
            self.call_args.append("NULL")
            return 1

        if resolved == "bool":
            self.c_params.append(f"int {c}")
            self.call_args.append(f"{c} != 0")
            self.lua_params.append(lua)
            if default is not None:
                self.pre.append(f"if {lua} == nil then {lua} = {'true' if default == 'true' else 'false'} end")
            self.call_exprs.append(f"if {lua} then 1 else 0")
            return 1

        if resolved in SIGNED or resolved in UNSIGNED:
            ctype = "unsigned int" if resolved in UNSIGNED else "int"
            self.c_params.append(f"{ctype} {c}")
            self.call_args.append(f"({decl}){c}")
            self.lua_params.append(lua)
            if default is not None:
                self.pre.append(f"if {lua} == nil then {lua} = {lua_number(m.eval_number(default))} end")
            self.call_exprs.append(f"bor({lua}, 0)")
            return 1

        if resolved in ("float", "double"):
            self.c_params.append(f"double {c}")
            self.call_args.append(f"(float){c}" if resolved == "float" else c)
            self.lua_params.append(lua)
            if default is not None:
                self.pre.append(f"if {lua} == nil then {lua} = {lua_number(m.eval_number(default))} end")
            self.call_exprs.append(lua)
            return 1

        if decl == "const char*":
            self.c_params.append(f"const char* {c}")
            self.call_args.append(c)
            self.lua_params.append(lua)
            if nullable or name in NULLABLE_STRINGS:
                self.call_exprs.append(f"OptStr({lua})")
            else:
                if default is not None:
                    self.pre.append(f"if {lua} == nil then {lua} = {default} end")
                self.call_exprs.append(f"Str({lua})")
            return 1

        if decl == "char*" and nxt is not None and nxt_resolved in UNSIGNED and nxt["name"].endswith("size"):
            self.c_params += [f"char* {c}", f"unsigned int a_{nxt['name']}"]
            self.call_args += [c, f"(size_t)a_{nxt['name']}"]
            self.lua_params.append(lua)
            self.lua_extra_params.append("capacity")
            self.pre.append(f"local p_{name}, n_{name} = TextBuffer({lua}, capacity)")
            self.call_exprs += [f"p_{name}", f"n_{name}"]
            self.post_returns.append(f"ReadCString(M, p_{name})")
            self.reads_memory = True
            return 2

        if decl == "const char*const[]" and nxt is not None and nxt_resolved in SIGNED and "count" in nxt["name"]:
            self.c_params += [f"const char* const* {c}", f"int a_{nxt['name']}"]
            self.call_args += [c, f"a_{nxt['name']}"]
            self.lua_params.append(lua)
            self.pre.append(f"local p_{name}, n_{name} = StrArray({lua})")
            self.call_exprs += [f"p_{name}", f"n_{name}"]
            return 2

        if resolved in ("ImVec2", "ImVec4"):
            count = 2 if resolved == "ImVec2" else 4
            comps = ["x", "y"] if count == 2 else ["x", "y", "z", "w"]
            self.c_params += [f"double {c}_{k}" for k in comps]
            self.call_args.append(f"{resolved}(" + ", ".join(f"(float){c}_{k}" for k in comps) + ")")
            self.lua_params.append(lua)
            defaults = m.vec_default(default, count) if default is not None else ["nil"] * count
            names = [f"{k}_{name}" for k in comps]
            helper = "Vec2" if count == 2 else "Vec4"
            self.pre.append(f"local {', '.join(names)} = {helper}({lua}, {', '.join(defaults)}, \"{name}\")")
            self.call_exprs += names
            return 1

        array = ARRAY_DECL.match(decl)
        if array:
            elem = m.resolve(array.group(1))
            count = array.group(2)
            if not count.isdigit():
                raise Unsupported(f"array {decl}")
            if elem == "float":
                kind, ctype = "F32", "float*"
            elif elem in ("int", "signed int", "unsigned int"):
                kind, ctype = "I32", f"{array.group(1)}*"
            else:
                raise Unsupported(f"array {decl}")
            self.c_params.append(f"{ctype} {c}")
            self.call_args.append(c)
            self.lua_params.append(lua)
            self.pre.append(f"local p_{name} = {kind}Array({lua}, {count})")
            self.call_exprs.append(f"p_{name}")
            self.post_returns.append(f"{kind}ArrayResult(p_{name}, {lua}, {count})")
            self.reads_memory = True
            return 1

        pointer = split_pointer(decl)
        if pointer is not None:
            const, base = pointer
            rbase = m.resolve(base)
            if const and rbase == "float" and nxt is not None and nxt["name"].endswith("_count") and nxt_resolved in SIGNED:
                self.c_params += [f"const float* {c}", f"int a_{nxt['name']}"]
                self.call_args += [c, f"a_{nxt['name']}"]
                self.lua_params.append(lua)
                self.pre.append(f"local p_{name}, n_{name} = F32List({lua})")
                self.call_exprs += [f"p_{name}", f"n_{name}"]
                return 2
            if const and rbase == "ImVec2" and nxt is not None and (nxt["name"] == "num_points" or nxt["name"].endswith("_count")) and nxt_resolved in SIGNED:
                self.c_params += [f"const ImVec2* {c}", f"int a_{nxt['name']}"]
                self.call_args += [c, f"a_{nxt['name']}"]
                self.lua_params.append(lua)
                self.pre.append(f"local p_{name}, n_{name} = Vec2List({lua})")
                self.call_exprs += [f"p_{name}", f"n_{name}"]
                return 2
            slot = SCALAR_SLOTS.get(rbase)
            if slot is not None and not const:
                slot_fn, reader = slot
                self.c_params.append(f"{base}* {c}")
                self.call_args.append(f"*{c}" if is_ref else c)
                read = reader.format(p=f"p_{name}")
                if name.startswith("out_"):
                    self.pre.append(f"local p_{name} = {slot_fn}(nil)")
                    self.post_returns.append(read)
                else:
                    self.lua_params.append(lua)
                    if nullable:
                        self.pre.append(f"local p_{name} = if {lua} == nil then 0 else {slot_fn}({lua})")
                        self.post_returns.append(f"if p_{name} == 0 then nil else {read}")
                    else:
                        self.pre.append(f"local p_{name} = {slot_fn}({lua})")
                        self.post_returns.append(read)
                self.call_exprs.append(f"p_{name}")
                self.reads_memory = True
                return 1
            if rbase == "void" and nullable and ("user_data" in name or "callback_data" in name):
                # Only meaningful together with a C callback, which Luau cannot provide
                self.call_args.append("NULL")
                return 1
            if rbase == "void" or (rbase not in BUILTIN_SCALARS and rbase not in ("ImVec2", "ImVec4", "fnptr") and rbase in m.structs):
                self.c_params.append(f"void* {c}")
                self.call_args.append(f"*({decl}){c}" if is_ref else f"({decl}){c}")
                self.lua_params.append(lua)
                self.call_exprs.append(f"Ptr({lua})")
                return 1

        if nullable:
            self.call_args.append("NULL")
            return 1
        raise Unsupported(f"argument {decl} {name}")

    # ---------------------------------------------------------------- return value
    def plan_return(self) -> None:
        m = self.model
        decl = norm(self.func["return_type"]["declaration"])
        resolved = m.resolve(decl)
        if decl == "void":
            return
        if resolved == "bool":
            self.ret_ctype, self.ret_body, self.ret_lua = "int", "return {call} ? 1 : 0;", ["r ~= 0"]
        elif resolved in SIGNED:
            self.ret_ctype, self.ret_body, self.ret_lua = "int", "return (int){call};", ["(if r >= 2147483648 then r - 4294967296 else r)"]
        elif resolved in UNSIGNED:
            self.ret_ctype, self.ret_body, self.ret_lua = "unsigned int", "return (unsigned int){call};", ["r"]
        elif resolved in ("float", "double"):
            self.ret_ctype, self.ret_body, self.ret_lua = "double", "return (double){call};", ["r"]
        elif decl == "const char*":
            self.ret_ctype, self.ret_body, self.ret_lua = "const char*", "return {call};", ["ReadCString(M, r)"]
            self.reads_memory = True
        elif resolved == "ImVec2":
            self.ret_body = "ImVec2 r = {call}; g_RbxReturnSlots[0] = r.x; g_RbxReturnSlots[1] = r.y;"
            self.ret_lua = ["Vector2.new(readf32(M, RS), readf32(M, RS + 4))"]
            self.reads_memory = True
        elif resolved == "ImVec4":
            self.ret_body = "ImVec4 r = {call}; g_RbxReturnSlots[0] = r.x; g_RbxReturnSlots[1] = r.y; g_RbxReturnSlots[2] = r.z; g_RbxReturnSlots[3] = r.w;"
            self.ret_lua = ["readf32(M, RS)", "readf32(M, RS + 4)", "readf32(M, RS + 8)", "readf32(M, RS + 12)"]
            self.reads_memory = True
        elif decl == "const ImVec4*":
            self.ret_ctype, self.ret_body = "void*", "return igw_ptr({call});"
            self.ret_lua = ["Vec4Ptr(r)"]
        else:
            pointer = split_pointer(decl)
            if pointer is None:
                raise Unsupported(f"return {decl}")
            _, base = pointer
            self.ret_ctype, self.ret_body = "void*", "return igw_ptr({call});"
            self.ret_lua = [f'Handle("{base}", r)'] if base in HANDLE_CLASSES else ["r"]

    # ---------------------------------------------------------------- output
    def cpp(self) -> str:
        func = self.func
        if func.get("is_unformatted_helper"):
            base = self.model.by_name[self.name[: -len("Unformatted")]]
            callee = base["original_fully_qualified_name"]
            args = self.call_args[:-1] + ['"%s"', self.call_args[-1]]
        elif self.cls:
            method = func["original_fully_qualified_name"]
            callee = f"{self.cls}::{method}" if func.get("is_static") else f"{self.self_expr}->{method}"
            args = self.call_args
        else:
            callee = func["original_fully_qualified_name"]
            args = self.call_args
        call = f"{callee}({', '.join(args)})"
        params = ", ".join(self.c_params) or "void"
        return f"IGW {self.ret_ctype} igw_{self.name}({params}) {{ {self.ret_body.format(call=call)} }}"

    def luau(self, target: str, lua_name: str) -> str:
        params = ", ".join(self.lua_params + self.lua_extra_params)
        lines = [
            "\tdo",
            "\t\tlocal f",
            f"\t\tbinders[#binders + 1] = function(E) f = E.igw_{self.name} end",
            f"\t\t{target}.{lua_name} = function({params})",
            "\t\t\tReset()",
        ]
        lines += ["\t\t\t" + s for s in self.pre]
        call = "f[1](f" + "".join(", " + e for e in self.call_exprs) + ")"
        returns = self.ret_lua + self.post_returns
        if self.ret_lua:
            lines.append(f"\t\t\tlocal r = {call}")
        else:
            lines.append("\t\t\t" + call)
        if self.reads_memory and returns:
            lines.append("\t\t\tM = Mem()")
        if returns:
            lines.append("\t\t\treturn " + ", ".join(returns))
        lines += ["\t\tend", "\tend"]
        return "\n".join(lines)


LUAU_PRELUDE = r"""-- Generated by tools/gen_bindings.py from dear_bindings metadata (Dear ImGui __VERSION__). Do not edit.
return function(ImGui, Api)
	local bor, lshift = bit32.bor, bit32.lshift
	local readu8, readu16, readu32, readi32 = buffer.readu8, buffer.readu16, buffer.readu32, buffer.readi32
	local readf32, readf64 = buffer.readf32, buffer.readf64
	local writeu8, writeu16, writeu32 = buffer.writeu8, buffer.writeu16, buffer.writeu32
	local writef32, writef64, writestring = buffer.writef32, buffer.writef64, buffer.writestring
	local typeof = typeof or type
	local sformat, select, tostring, type = string.format, select, tostring, type
	local Mem, ReadCString = Api.Mem, Api.ReadCString

	local S0, SEnd, SP, RS = 0, 0, 0, 0 -- scratch region and return slots in linear memory
	local M = nil -- current memory buffer
	local LastLen = 0
	local malloc, free = nil, nil
	local Pending, PendingCount = {}, 0
	local binders = {}

	local function Reset()
		if PendingCount > 0 then
			for i = 1, PendingCount do
				free[1](free, Pending[i])
				Pending[i] = nil
			end
			PendingCount = 0
		end
		M = Mem()
		SP = S0
	end

	local function Reserve(size, align)
		local p = SP
		local rem = p % align
		if rem ~= 0 then
			p += align - rem
		end
		if p + size <= SEnd then
			SP = p + size
			return p
		end
		p = (malloc[1](malloc, size + 8))
		M = Mem()
		PendingCount += 1
		Pending[PendingCount] = p
		return p
	end

	local function Str(s)
		if type(s) ~= "string" then
			if s == nil then
				error("ImGui: expected a string argument", 3)
			end
			s = tostring(s)
		end
		local n = #s
		local p = Reserve(n + 1, 1)
		writestring(M, p, s)
		writeu8(M, p + n, 0)
		LastLen = n
		return p
	end

	local function OptStr(s)
		if s == nil then
			return 0
		end
		return Str(s)
	end

	local function BoolSlot(v)
		local p = Reserve(1, 1)
		writeu8(M, p, if v then 1 else 0)
		return p
	end

	local function I32Slot(v)
		local p = Reserve(4, 4)
		writeu32(M, p, (v or 0) % 4294967296)
		return p
	end
	local U32Slot = I32Slot

	local function F32Slot(v)
		local p = Reserve(4, 4)
		writef32(M, p, v or 0)
		return p
	end

	local function F64Slot(v)
		local p = Reserve(8, 8)
		writef64(M, p, v or 0)
		return p
	end

	local function ReadI32(p)
		local v = readu32(M, p)
		if v >= 2147483648 then
			v -= 4294967296
		end
		return v
	end

	local function Vec2(v, dx, dy, name)
		if v == nil then
			if dx == nil then
				error("ImGui: missing Vector2 argument '" .. name .. "'", 3)
			end
			return dx, dy
		end
		local t = typeof(v)
		if t == "Vector2" or t == "Vector3" then
			return v.X, v.Y
		elseif t == "table" then
			local x = v[1]
			if x ~= nil then
				return x, v[2] or 0
			end
			x = v.X or v.x
			if x ~= nil then
				return x, v.Y or v.y or 0
			end
		elseif t == "number" then
			return v, v
		end
		error("ImGui: expected Vector2 for '" .. name .. "'", 3)
	end

	local function Vec4(v, d1, d2, d3, d4, name)
		if v == nil then
			if d1 == nil then
				error("ImGui: missing ImVec4 argument '" .. name .. "'", 3)
			end
			return d1, d2, d3, d4
		end
		local t = typeof(v)
		if t == "Color3" then
			return v.R, v.G, v.B, 1
		elseif t == "table" then
			local x = v[1]
			if x ~= nil then
				return x, v[2] or 0, v[3] or 0, v[4] or 1
			end
			if v.R ~= nil then
				return v.R, v.G or 0, v.B or 0, v.A or 1
			end
			x = v.X or v.x
			if x ~= nil then
				return x, v.Y or v.y or 0, v.Z or v.z or 0, v.W or v.w or 1
			end
		end
		error("ImGui: expected Color3 or {x, y, z, w} for '" .. name .. "'", 3)
	end

	local function Vec4Ptr(p)
		if p == 0 then
			return nil
		end
		local m = Mem()
		return { readf32(m, p), readf32(m, p + 4), readf32(m, p + 8), readf32(m, p + 12) }
	end

	local function F32Array(v, n)
		local p = Reserve(n * 4, 4)
		if typeof(v) == "Color3" then
			writef32(M, p, v.R)
			writef32(M, p + 4, v.G)
			writef32(M, p + 8, v.B)
			for i = 3, n - 1 do
				writef32(M, p + i * 4, 1)
			end
		else
			for i = 1, n do
				writef32(M, p + (i - 1) * 4, v[i] or 0)
			end
		end
		return p
	end

	local function F32ArrayResult(p, v, n)
		if typeof(v) == "Color3" then
			return Color3.new(readf32(M, p), readf32(M, p + 4), readf32(M, p + 8))
		end
		for i = 1, n do
			v[i] = readf32(M, p + (i - 1) * 4)
		end
		return v
	end

	local function I32Array(v, n)
		local p = Reserve(n * 4, 4)
		for i = 1, n do
			writeu32(M, p + (i - 1) * 4, (v[i] or 0) % 4294967296)
		end
		return p
	end

	local function I32ArrayResult(p, v, n)
		for i = 1, n do
			v[i] = ReadI32(p + (i - 1) * 4)
		end
		return v
	end

	local function F32List(values)
		local n = #values
		local p = Reserve(n * 4, 4)
		for i = 1, n do
			writef32(M, p + (i - 1) * 4, values[i])
		end
		return p, n
	end

	local function Vec2List(points)
		local n = #points
		local p = Reserve(n * 8, 4)
		for i = 1, n do
			local x, y = Vec2(points[i], nil, nil, "points")
			writef32(M, p + (i - 1) * 8, x)
			writef32(M, p + (i - 1) * 8 + 4, y)
		end
		return p, n
	end

	local function StrArray(items)
		local n = #items
		local p = Reserve(n * 4, 4)
		for i = 1, n do
			local s = Str(items[i])
			writeu32(M, p + (i - 1) * 4, s)
		end
		return p, n
	end

	local function TextBuffer(text, capacity)
		text = if text == nil then "" else tostring(text)
		local n = #text
		local size = capacity or ImGui.InputTextCapacity or 1024
		if size < n + 1 then
			size = n + 1
		end
		local p = Reserve(size, 1)
		writestring(M, p, text)
		writeu8(M, p + n, 0)
		return p, size
	end

	local function Format(fmt, ...)
		if select("#", ...) == 0 then
			return fmt
		end
		return sformat(fmt, ...)
	end

	-- Handles for pointers to Dear ImGui structs: methods from ImGui.<Class>, fields read/written in linear memory
	local HandleMeta, HandleCache, ClassFields = {}, {}, {}
	local function Handle(className, ptr)
		if ptr == 0 then
			return nil
		end
		local cache = HandleCache[className]
		local handle = cache[ptr]
		if handle == nil then
			handle = setmetatable({ __ptr = ptr }, HandleMeta[className])
			cache[ptr] = handle
		end
		return handle
	end

	local function Ptr(v)
		if v == nil then
			return 0
		elseif type(v) == "table" then
			return v.__ptr or 0
		end
		return v
	end

	local KindSize = { f32 = 4, f64 = 8, bool = 1, i32 = 4, u32 = 4, i16 = 2, u16 = 2, i8 = 1, u8 = 1, vec2 = 8, vec4 = 16, cstr = 4, ptr = 4 }

	local function ReadScalar(m, kind, p)
		if kind == "f32" then
			return readf32(m, p)
		elseif kind == "bool" then
			return readu8(m, p) ~= 0
		elseif kind == "i32" then
			local v = readu32(m, p)
			return if v >= 2147483648 then v - 4294967296 else v
		elseif kind == "u32" or kind == "ptr" then
			return readu32(m, p)
		elseif kind == "vec2" then
			return Vector2.new(readf32(m, p), readf32(m, p + 4))
		elseif kind == "vec4" then
			return { readf32(m, p), readf32(m, p + 4), readf32(m, p + 8), readf32(m, p + 12) }
		elseif kind == "f64" then
			return readf64(m, p)
		elseif kind == "u16" then
			return readu16(m, p)
		elseif kind == "i16" then
			local v = readu16(m, p)
			return if v >= 32768 then v - 65536 else v
		elseif kind == "u8" then
			return readu8(m, p)
		elseif kind == "i8" then
			local v = readu8(m, p)
			return if v >= 128 then v - 256 else v
		elseif kind == "cstr" then
			return ReadCString(m, readu32(m, p))
		end
		return nil
	end

	local function WriteScalar(m, kind, p, v)
		if kind == "f32" then
			writef32(m, p, v)
		elseif kind == "bool" then
			writeu8(m, p, if v then 1 else 0)
		elseif kind == "i32" or kind == "u32" or kind == "ptr" then
			writeu32(m, p, Ptr(v) % 4294967296)
		elseif kind == "vec2" then
			local x, y = Vec2(v, nil, nil, "value")
			writef32(m, p, x)
			writef32(m, p + 4, y)
		elseif kind == "vec4" then
			local x, y, z, w = Vec4(v, nil, nil, nil, nil, "value")
			writef32(m, p, x)
			writef32(m, p + 4, y)
			writef32(m, p + 8, z)
			writef32(m, p + 12, w)
		elseif kind == "f64" then
			writef64(m, p, v)
		elseif kind == "u16" or kind == "i16" then
			writeu16(m, p, v % 65536)
		elseif kind == "u8" or kind == "i8" then
			writeu8(m, p, v % 256)
		else
			error("ImGui: field is read-only", 3)
		end
	end

	local function ArrayProxy(base, kind, count)
		local size = KindSize[kind]
		return setmetatable({}, {
			__index = function(_, i)
				if type(i) == "number" and i >= 0 and i < count then
					return ReadScalar(Mem(), kind, base + (i // 1) * size)
				end
				return nil
			end,
			__newindex = function(_, i, v)
				if type(i) ~= "number" or i < 0 or i >= count then
					error("ImGui: array index out of range", 2)
				end
				WriteScalar(Mem(), kind, base + (i // 1) * size, v)
			end,
			__len = function()
				return count
			end,
		})
	end

	local function DefineClass(className, methods)
		HandleCache[className] = setmetatable({}, { __mode = "v" })
		local fields = ClassFields[className]
		HandleMeta[className] = {
			__index = function(self, key)
				local method = methods[key]
				if method ~= nil then
					return method
				end
				local field = fields and fields[key]
				if field ~= nil then
					local p = rawget(self, "__ptr") + field[2]
					if field[3] > 0 then
						return ArrayProxy(p, field[1], field[3])
					end
					return ReadScalar(Mem(), field[1], p)
				end
				return nil
			end,
			__newindex = function(self, key, value)
				local field = fields and fields[key]
				if field == nil or field[3] > 0 then
					error("ImGui: " .. className .. "." .. tostring(key) .. " is not a writable field", 2)
				end
				WriteScalar(Mem(), field[1], rawget(self, "__ptr") + field[2], value)
			end,
			__tostring = function(self)
				return sformat("%s: 0x%08x", className, rawget(self, "__ptr"))
			end,
		}
	end

	ImGui.FLT_MAX = 3.4028234663852886e38
	ImGui.FLT_MIN = 1.1754943508222875e-38
	function ImGui.COL32(r, g, b, a)
		return bor(r, lshift(g, 8), lshift(b, 16), lshift(if a == nil then 255 else a, 24))
	end
"""

LUAU_EPILOGUE = r"""
	Api.Handle = Handle -- the runtime copies styles between scripts through these
	Api.ClassFields = ClassFields
	Api.OnInit = function()
		local E = Api.Exports
		S0 = Api.Scratch
		SEnd = S0 + Api.ScratchSize
		SP = S0
		RS = Api.ReturnSlots
		malloc, free = E.malloc, E.free
		for _, bind in binders do
			bind(E)
		end
		local m = Mem()
		for className, fields in ClassFields do
			local getter = E["igw_offsets_" .. className]
			local ptr = getter[1](getter)
			for _, field in fields do
				field[2] = readi32(m, ptr + field[4] * 4)
			end
		end
	end
end
"""

CPP_PRELUDE = """\
// Generated by tools/gen_bindings.py from dear_bindings metadata (Dear ImGui __VERSION__). Do not edit.
// Flat wrappers over the Dear ImGui C++ API that the Luau bindings call through the WebAssembly exports.
#include "imgui.h"
#include <emscripten/emscripten.h>
#include <stddef.h>

#if defined(__clang__)
#pragma clang diagnostic ignored "-Winvalid-offsetof"
#pragma clang diagnostic ignored "-Wformat-security"
#endif

#define IGW extern "C" EMSCRIPTEN_KEEPALIVE

extern float g_RbxReturnSlots[16];

// dear_bindings exposes C++ references as pointers: accept both forms when returning them.
template<typename T> static inline void* igw_ptr(T* p) { return (void*)p; }
template<typename T> static inline void* igw_ptr(T& r) { return (void*)&r; }

"""


def field_specs(model: Model, class_name: str) -> list[tuple[str, str, int]]:
    specs = []
    for field in model.structs[class_name]["fields"]:
        if field.get("is_internal") or field.get("conditionals") or field.get("is_anonymous"):
            continue
        decl = norm(field["type"]["declaration"])
        count = 0
        array = ARRAY_DECL.match(decl)
        if array:
            bound = array.group(2)
            count = int(bound) if bound.isdigit() else model.enum_values.get(bound, 0)
            decl = norm(array.group(1))
            if not count:
                continue
        resolved = model.resolve(decl)
        kind = FIELD_KINDS.get(decl) or FIELD_KINDS.get(resolved)
        if kind is None:
            pointer = split_pointer(decl)
            if pointer is None or resolved == "fnptr":
                continue
            kind = "ptr"
        if count and kind == "cstr":
            continue
        specs.append((field["name"], kind, count))
    return specs


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--json", required=True)
    parser.add_argument("--out-cpp", required=True)
    parser.add_argument("--out-luau", required=True)
    parser.add_argument("--exclude", default="", help="comma-separated dear_bindings function names to leave out")
    args = parser.parse_args()
    excluded = {name.strip() for name in args.exclude.split(",") if name.strip()}

    data = json.loads(pathlib.Path(args.json).read_text(encoding="utf-8"))
    model = Model(data)
    version = next((d["content"].strip('"') for d in data["defines"] if d["name"] == "IMGUI_VERSION"), "?")

    cpp = [CPP_PRELUDE.replace("__VERSION__", version)]
    luau = [LUAU_PRELUDE.replace("__VERSION__", version)]
    skipped: list[str] = []
    bound = 0
    varargs: list[dict] = []
    lua_names: dict[str, str] = {}
    bound_funcs: list[tuple[dict, str, str]] = []

    for func in model.functions:
        name = func["name"]
        cls = func.get("original_class")
        if cls is None and not name.startswith("ImGui_"):
            continue
        if cls is not None and cls not in HANDLE_CLASSES:
            continue
        if name in SKIP_FUNCTIONS or name in excluded or any(part in name for part in SKIP_NAME_PARTS):
            skipped.append(f"{name}: excluded")
            continue
        if func.get("is_default_argument_helper") or func.get("is_manual_helper") or func.get("is_imstr_helper"):
            continue
        if func.get("conditionals"):
            skipped.append(f"{name}: conditional")
            continue
        lua_name = model.luau_name(func)
        if lua_name.startswith("_"):
            continue
        if any(a["is_varargs"] for a in func["arguments"]):
            varargs.append(func)
            continue
        try:
            wrapper = Wrapper(model, func)
        except Unsupported as exc:
            skipped.append(f"{name}: {exc}")
            continue
        target = "ImGui" if cls is None else f"ImGui.{HANDLE_CLASSES[cls]}"
        cpp.append(wrapper.cpp())
        luau.append(wrapper.luau(target, lua_name))
        lua_names[name] = lua_name
        bound_funcs.append((func, target, lua_name))
        bound += 1

    for func in varargs:
        name = func["name"]
        helper = name + "Unformatted"
        if name == "ImGui_Text":
            helper = "ImGui_TextUnformattedEx"
        if helper not in lua_names:
            skipped.append(f"{name}: varargs without unformatted helper")
            continue
        fixed = [lua_ident(a["name"]) for a in func["arguments"] if not a["is_varargs"] and a["name"] != "fmt"]
        params = ", ".join(fixed + ["fmt", "..."])
        forward = ", ".join(fixed + ["Format(fmt, ...)"])
        luau.append(f"\tImGui.{model.luau_name(func)} = function({params})\n\t\treturn ImGui.{lua_names[helper]}({forward})\n\tend")
        bound += 1

    # dear_bindings disambiguates C++ overloads with suffixes (PushFontFloat, SelectableBoolPtr, ...).
    # Also expose the original C++ name when no other binding uses it, e.g. ImGui.PushFont.
    defined = {(target, lua_name) for _, target, lua_name in bound_funcs}
    defined |= {("ImGui", model.luau_name(f)) for f in varargs}
    for func, target, lua_name in bound_funcs:
        if func.get("is_unformatted_helper"):
            continue
        original = func["original_fully_qualified_name"].split("::")[-1]
        if original != lua_name and (target, original) not in defined:
            defined.add((target, original))
            luau.append(f"\t{target}.{original} = {target}.{lua_name}")

    # dear_bindings names the string-list overload ComboChar; accept both forms under the C++ name.
    luau.append(
        "\tdo\n"
        "\t\tlocal comboZeroSeparated, comboArray = ImGui.Combo, ImGui.ComboChar\n"
        "\t\tImGui.Combo = function(label, current_item, items, popup_max_height_in_items)\n"
        "\t\t\tif type(items) == \"table\" then\n"
        "\t\t\t\treturn comboArray(label, current_item, items, popup_max_height_in_items)\n"
        "\t\t\tend\n"
        "\t\t\treturn comboZeroSeparated(label, current_item, items, popup_max_height_in_items)\n"
        "\t\tend\n"
        "\tend"
    )

    for enum in model.enums:
        table = strip_enum_prefix(enum["name"])
        prefix = enum["name"] if enum["name"].endswith("_") else enum["name"] + "_"
        entries = []
        for element in enum["elements"]:
            if element.get("is_internal") or element.get("value") is None:
                continue
            key = element["name"]
            if key.startswith(prefix):
                key = key[len(prefix):]
            elif key.startswith("ImGui"):
                key = key[len("ImGui"):]
            entries.append(f'["{key}"] = {element["value"]}')
        luau.append(f"\tImGui.{table} = {{ {', '.join(entries)} }}")

    for class_name in FIELD_CLASSES:
        specs = field_specs(model, class_name)
        offsets = ", ".join(f"(int)offsetof({class_name}, {n})" for n, _, _ in specs)
        cpp.append(f"static const int igw_offsets_{class_name}_data[] = {{ {offsets} }};")
        cpp.append(f"IGW const int* igw_offsets_{class_name}(void) {{ return igw_offsets_{class_name}_data; }}")
        fields = ", ".join(f'{n} = {{ "{k}", 0, {c}, {i} }}' for i, (n, k, c) in enumerate(specs))
        luau.append(f"\tClassFields.{class_name} = {{ {fields} }}")

    for class_name, table in HANDLE_CLASSES.items():
        luau.insert(1, f"\tImGui.{table} = ImGui.{table} or {{}}")
        luau.append(f'\tDefineClass("{class_name}", ImGui.{table})')

    luau.append(LUAU_EPILOGUE)

    out_cpp = pathlib.Path(args.out_cpp)
    out_luau = pathlib.Path(args.out_luau)
    out_cpp.parent.mkdir(parents=True, exist_ok=True)
    out_luau.parent.mkdir(parents=True, exist_ok=True)
    out_cpp.write_text("\n".join(cpp) + "\n", encoding="utf-8", newline="\n")
    out_luau.write_text("\n".join(luau) + "\n", encoding="utf-8", newline="\n")
    (out_luau.parent / "skipped.txt").write_text("\n".join(skipped) + "\n", encoding="utf-8")
    print(f"bindings: {bound} functions bound, {len(skipped)} skipped (see {out_luau.parent / 'skipped.txt'})")


if __name__ == "__main__":
    main()

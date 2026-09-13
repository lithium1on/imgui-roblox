
-- ===== test footer (appended to Spider output) =====
rt_import_map.env = {
	host_measure = { function(_self, font, size, codepoint) return font * 100 + size + codepoint / 1000 end },
}
rt_export_map = {}
module()
local E = rt_export_map
local function call(name, ...) local c = E[name]; return c[1](c, ...) end
local mem = E.memory
local function buf() return mem[1][1] end
local T4, T8 = buffer.create(4), buffer.create(8)
local function f32bits(x) buffer.writef32(T4, 0, x); return buffer.readu32(T4, 0) end
local function f32val(b) buffer.writeu32(T4, 0, b); return buffer.readf32(T4, 0) end
local function i64(lo, hi) buffer.writeu32(T8, 0, lo); buffer.writeu32(T8, 4, hi); return buffer.readf64(T8, 0) end
local function i64parts(x) buffer.writef64(T8, 0, x); return buffer.readu32(T8, 0), buffer.readu32(T8, 4) end
local function cstr(ptr) local b = buf(); local n = 0; while buffer.readu8(b, ptr + n) ~= 0 do n += 1 end; return buffer.readstring(b, ptr, n) end
local function newstr(s) local p = call("malloc", #s + 1); buffer.writestring(buf(), p, s); buffer.writeu8(buf(), p + #s, 0); return p end

local fails = 0
local function check(name, got, want, tol)
	local ok = if tol then math.abs(got - want) <= tol else got == want
	print(string.format("%-8s %-6s got=%s want=%s", name, ok and "OK" or "FAIL", tostring(got), tostring(want)))
	if not ok then fails += 1 end
end

local t0 = os.clock()
call("_initialize")
check("add", (call("test_add", 2, 3)), 5)
check("add_neg", (call("test_add", 0xFFFFFFFF, 3)), 2)
local x = 1.25
check("math", (call("test_math", x)), math.sin(x) * math.cos(x) + x ^ 2.5 + math.fmod(x, 0.7) + math.atan2(x, 2.0), 1e-12)
check("float", f32val((call("test_float", f32bits(4.0)))), 8.0)
local lo, hi = i64parts((call("test_i64", i64(123456789, 0), i64(1000, 0))))
local want = 123456789 * 1000 + (123456789 // 8) - (1000 // 7)
check("i64", lo + hi * 2 ^ 32, want)
local p = call("test_alloc", 10)
check("alloc", cstr(p), "AAAAAAAAA")
check("strlen", (call("test_strlen", p)), 9)
check("import", (call("test_import", 65)), (300 + 13 + 0.065) * 2, 1e-9)
local out = call("malloc", 64)
local n = call("test_sprintf", out, 64, 3.14159)
check("sprintf", cstr(out), "v=3.142 42 ok beef")
check("sscanf", (call("test_sscanf", newstr("2.625"))), 5.25)
check("qsort", (call("test_qsort")), 100)
print(string.format("done: %d failures, %.3f ms", fails, (os.clock() - t0) * 1000))

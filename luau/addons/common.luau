-- Helpers shared by the addons' Luau sides, bundled into every addon file: calling exports and moving strings, numbers
-- and colors in and out of linear memory. Common(host) returns them for one linked module (host: see LoadAddon in
-- luau/runtime.luau).

local Signatures = ...

local floor, max = math.floor, math.max
local bor, lshift = bit32.bor, bit32.lshift
local readf64, readi32 = buffer.readf64, buffer.readi32
local writestring, writeu8, writef64, writef32, writei32, writeu32 =
	buffer.writestring, buffer.writeu8, buffer.writef64, buffer.writef32, buffer.writei32, buffer.writeu32

return function(host)
	local Mem, Malloc, Free = host.Mem, host.Malloc, host.Free
	local C = {}
	local arena = {}

	-- The translated module keeps int32 values in 0..2^32-1: int parameters are converted to that range (so -1 and
	-- other negative ints arrive intact) and int results back to signed
	local function Convert(closure, signature)
		local params, results = string.match(signature, "^(%a*):(%a*)$")
		local call = closure[1]
		if results == "i" and not string.find(params, "i", 1, true) then
			return { function(self, ...)
				local r = call(closure, ...)
				return if r >= 2147483648 then r - 4294967296 else r
			end }
		elseif not string.find(params, "i", 1, true) then
			return closure
		end
		assert(#params <= 16, "[ImGui] an addon export has more than 16 parameters")
		local k = table.create(16, false)
		for index = 1, #params do
			k[index] = string.sub(params, index, index) == "i"
		end
		local k1, k2, k3, k4, k5, k6, k7, k8 = k[1], k[2], k[3], k[4], k[5], k[6], k[7], k[8]
		local k9, k10, k11, k12, k13, k14, k15, k16 = k[9], k[10], k[11], k[12], k[13], k[14], k[15], k[16]
		local signed = results == "i"
		return { function(self, a1, a2, a3, a4, a5, a6, a7, a8, a9, a10, a11, a12, a13, a14, a15, a16)
			if k1 then a1 = bor(a1, 0) end
			if k2 then a2 = bor(a2, 0) end
			if k3 then a3 = bor(a3, 0) end
			if k4 then a4 = bor(a4, 0) end
			if k5 then a5 = bor(a5, 0) end
			if k6 then a6 = bor(a6, 0) end
			if k7 then a7 = bor(a7, 0) end
			if k8 then a8 = bor(a8, 0) end
			if k9 then a9 = bor(a9, 0) end
			if k10 then a10 = bor(a10, 0) end
			if k11 then a11 = bor(a11, 0) end
			if k12 then a12 = bor(a12, 0) end
			if k13 then a13 = bor(a13, 0) end
			if k14 then a14 = bor(a14, 0) end
			if k15 then a15 = bor(a15, 0) end
			if k16 then a16 = bor(a16, 0) end
			local r = call(closure, a1, a2, a3, a4, a5, a6, a7, a8, a9, a10, a11, a12, a13, a14, a15, a16)
			if signed and r >= 2147483648 then
				return r - 4294967296
			end
			return r
		end }
	end

	-- The module's exports prefix .. name for each name; C.Call(E.name, ...) calls one
	function C.Exports(prefix, names)
		local exports = {}
		for _, name in names do
			local closure = host.Exports[prefix .. name] or error("[ImGui] an addon module is missing " .. prefix .. name)
			local signature = Signatures[prefix .. name]
			exports[name] = if signature ~= nil then Convert(closure, signature) else closure
		end
		return exports
	end

	function C.Call(closure, ...)
		return closure[1](closure, ...)
	end

	-- Memory for a call's arguments, freed together by Release
	function C.Alloc(size)
		local ptr = Malloc(size)
		arena[#arena + 1] = ptr
		return ptr
	end

	function C.Release()
		for index = #arena, 1, -1 do
			Free(arena[index])
			arena[index] = nil
		end
	end

	-- A NUL-terminated copy of text, and its size; 0 for nil
	function C.String(text)
		if text == nil then
			return 0, 0
		end
		text = tostring(text)
		local size = #text
		local ptr = C.Alloc(size + 1)
		local mem = Mem()
		writestring(mem, ptr, text)
		writeu8(mem, ptr + size, 0)
		return ptr, size
	end

	-- An array of char* for a table of strings
	function C.Strings(texts)
		local pointers = {}
		for index, text in texts do
			pointers[index] = (C.String(text))
		end
		local ptr = C.Alloc(max(#pointers, 1) * 4)
		local mem = Mem()
		for index, pointer in pointers do
			writeu32(mem, ptr + (index - 1) * 4, pointer)
		end
		return ptr
	end

	-- A double array of the numbers in values (count defaults to #values), and the count
	function C.Doubles(values, count)
		count = count or #values
		local ptr = C.Alloc(max(count, 1) * 8)
		local mem = Mem()
		for index = 1, count do
			writef64(mem, ptr + (index - 1) * 8, values[index] or 0)
		end
		return ptr, count
	end

	-- A float array
	function C.Floats(values, count)
		count = count or #values
		local ptr = C.Alloc(max(count, 1) * 4)
		local mem = Mem()
		for index = 1, count do
			writef32(mem, ptr + (index - 1) * 4, values[index] or 0)
		end
		return ptr, count
	end

	function C.ReadDoubles(ptr, count)
		local mem, values = Mem(), table.create(count)
		for index = 1, count do
			values[index] = readf64(mem, ptr + (index - 1) * 8)
		end
		return table.unpack(values, 1, count)
	end

	function C.ReadInts(ptr, count)
		local mem, values = Mem(), table.create(count)
		for index = 1, count do
			values[index] = readi32(mem, ptr + (index - 1) * 4)
		end
		return table.unpack(values, 1, count)
	end

	function C.ReadString(ptr)
		return host.ReadCString(ptr)
	end

	-- An ImU32 from an ImU32 number, a Color3 (with an optional alpha 0-1) or an { r, g, b, a } table (0-1)
	function C.ColorU32(color, alpha)
		if color == nil then
			return 0xFFFFFFFF
		elseif type(color) == "number" then
			return color % 4294967296
		end
		local r, g, b, a
		if type(color) == "table" and color[1] ~= nil then
			r, g, b, a = color[1], color[2], color[3], color[4] or 1
		else
			r, g, b, a = color.R, color.G, color.B, if alpha == nil then 1 else alpha
		end
		return bor(floor(r * 255 + 0.5), lshift(floor(g * 255 + 0.5), 8), lshift(floor(b * 255 + 0.5), 16), lshift(floor(a * 255 + 0.5), 24))
	end

	-- The x and y of a Vector2, an { x, y } table or two numbers
	function C.XY(value, y)
		if value == nil then
			return 0, 0
		elseif type(value) == "number" then
			return value, y or 0
		elseif value.X ~= nil then
			return value.X, value.Y
		end
		return value[1] or 0, value[2] or 0
	end

	return C
end

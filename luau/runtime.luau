-- Dear ImGui for Roblox: runtime
-- Glue between the Luau translation of Dear ImGui (C++ -> WebAssembly with Emscripten -> Luau with Spider),
-- the render modes in renderer.luau (DrawingImmediate, Drawing) and UserInputService.
-- The bundle calls this chunk with (WasmInstantiate, InstallBindings, Renderer).

local WasmInstantiate, InstallBindings, Renderer = ...

local band, bor, rshift, lshift = bit32.band, bit32.bor, bit32.rshift, bit32.lshift
local readu8, readu16, readu32, readi32 = buffer.readu8, buffer.readu16, buffer.readu32, buffer.readi32
local readf32, readf64, readstring = buffer.readf32, buffer.readf64, buffer.readstring
local writeu8, writeu16, writeu32, writei32 = buffer.writeu8, buffer.writeu16, buffer.writeu32, buffer.writei32
local writef32, writef64, writestring = buffer.writef32, buffer.writef64, buffer.writestring
local bufferlen = buffer.len
local sfind, ssub, sformat, smatch, schar, srep, slower = string.find, string.sub, string.format, string.match, string.char, string.rep, string.lower
local floor, min, max, huge = math.floor, math.min, math.max, math.huge
local tconcat, tclear = table.concat, table.clear
local utf8char = utf8.char
local clock = os.clock
local warn = warn or function(...)
	print("[warn]", ...)
end

local ImGui = {}
ImGui.Version = "1.92.9b"

local Api = {} -- shared with the generated bindings
local Exports = nil -- WebAssembly exports; functions are Spider closures called as closure[1](closure, ...)
local MemoryBox = nil -- exported memory: { { buffer }, { byte_length }, maximum }

local function Mem()
	return MemoryBox[1][1]
end

local function ReadCString(mem, ptr, maxLen)
	if ptr == 0 then
		return nil
	end
	local avail = bufferlen(mem) - ptr
	if maxLen ~= nil and maxLen < avail then
		avail = maxLen
	end
	if avail <= 0 then
		return ""
	end
	local chunk = if avail < 64 then avail else 64
	local head = readstring(mem, ptr, chunk)
	local zero = sfind(head, "\0", 1, true)
	if zero then
		return ssub(head, 1, zero - 1)
	end
	local len = chunk
	while len < avail do
		chunk = min(4096, avail - len)
		zero = sfind(readstring(mem, ptr + len, chunk), "\0", 1, true)
		if zero then
			return readstring(mem, ptr, len + zero - 1)
		end
		len += chunk
	end
	return readstring(mem, ptr, len)
end

--------------------------------------------------------------------------------
-- printf family: C varargs are read from linear memory (wasm32: 4-byte ints/pointers, 8-byte aligned doubles)
--------------------------------------------------------------------------------

local FormatCache = {}
local FormatCacheSize = 0
local FormatOut = table.create(64)

local function ParseFormat(fmt)
	local segments = {}
	local count = 0
	local pos, len = 1, #fmt
	while pos <= len do
		local pct = sfind(fmt, "%", pos, true)
		if pct == nil then
			count += 1
			segments[count] = ssub(fmt, pos)
			break
		end
		if pct > pos then
			count += 1
			segments[count] = ssub(fmt, pos, pct - 1)
		end
		local s, e, flags, width, dot, prec, lenmod, conv =
			sfind(fmt, "^([-+ #0]*)(%*?%d*)(%.?)(%*?%d*)([hljztLq]*)([diouxXeEfFgGaAcspn%%])", pct + 1)
		count += 1
		if s == nil then
			segments[count] = "%"
			pos = pct + 1
		elseif conv == "%" then
			segments[count] = "%"
			pos = e + 1
		else
			segments[count] = { flags, width, dot, prec, lenmod, conv }
			pos = e + 1
		end
	end
	return segments
end

local function AlignArg8(ap)
	local rem = ap % 8
	return if rem == 0 then ap else ap + 8 - rem
end

local function FormatArgs(mem, fmtPtr, ap)
	local fmt = ReadCString(mem, fmtPtr) or ""
	local segments = FormatCache[fmt]
	if segments == nil then
		segments = ParseFormat(fmt)
		if FormatCacheSize >= 4096 then
			tclear(FormatCache)
			FormatCacheSize = 0
		end
		FormatCache[fmt] = segments
		FormatCacheSize += 1
	end

	local out = FormatOut
	local n = 0
	for i = 1, #segments do
		local seg = segments[i]
		if type(seg) == "string" then
			n += 1
			out[n] = seg
			continue
		end

		local flags, width, dot, prec, lenmod, conv = seg[1], seg[2], seg[3], seg[4], seg[5], seg[6]
		if width == "*" then
			local w = readi32(mem, ap)
			ap += 4
			if w < 0 then
				flags ..= "-"
				w = -w
			end
			width = tostring(min(w, 99))
		elseif #width > 2 then
			width = "99"
		end
		if prec == "*" then
			local p = readi32(mem, ap)
			ap += 4
			if p < 0 then
				dot, prec = "", ""
			else
				prec = tostring(min(p, 99))
			end
		elseif #prec > 2 then
			prec = "99"
		end

		local spec = "%" .. flags .. width .. dot .. prec
		local piece
		if conv == "d" or conv == "i" then
			local v
			if lenmod == "ll" or lenmod == "j" or lenmod == "q" then
				ap = AlignArg8(ap)
				v = readi32(mem, ap + 4) * 4294967296 + readu32(mem, ap)
				ap += 8
			else
				v = readi32(mem, ap)
				ap += 4
				if lenmod == "hh" then
					v = (v + 128) % 256 - 128
				elseif lenmod == "h" then
					v = (v + 32768) % 65536 - 32768
				end
			end
			piece = sformat(spec .. "d", v)
		elseif conv == "u" or conv == "x" or conv == "X" or conv == "o" then
			local v
			if lenmod == "ll" or lenmod == "j" or lenmod == "q" then
				ap = AlignArg8(ap)
				v = readu32(mem, ap + 4) * 4294967296 + readu32(mem, ap)
				ap += 8
			else
				v = readu32(mem, ap)
				ap += 4
				if lenmod == "hh" then
					v %= 256
				elseif lenmod == "h" then
					v %= 65536
				end
			end
			piece = sformat(spec .. (if conv == "u" then "d" else conv), v)
		elseif conv == "c" then
			local v = readi32(mem, ap)
			ap += 4
			piece = sformat(spec .. "s", schar(band(v, 255)))
		elseif conv == "s" then
			local p = readu32(mem, ap)
			ap += 4
			local str
			if p == 0 then
				str = "(null)"
			else
				str = ReadCString(mem, p, if dot == "." then (tonumber(prec) or 0) else nil)
			end
			if flags == "" and width == "" and dot == "" then
				piece = str
			else
				piece = sformat(spec .. "s", str)
			end
		elseif conv == "p" then
			local v = readu32(mem, ap)
			ap += 4
			piece = sformat("0x%x", v)
		elseif conv == "n" then
			local p = readu32(mem, ap)
			ap += 4
			local written = 0
			for j = 1, n do
				written += #out[j]
			end
			if p ~= 0 then
				writei32(mem, p, written)
			end
			piece = ""
		else -- e E f F g G a A
			ap = AlignArg8(ap)
			local v = readf64(mem, ap)
			ap += 8
			local c = conv
			if c == "F" then
				c = "f"
			elseif c == "a" then
				c = "e"
			elseif c == "A" then
				c = "E"
			end
			piece = sformat(spec .. c, v)
		end
		n += 1
		out[n] = piece
	end
	return tconcat(out, "", 1, n)
end

--------------------------------------------------------------------------------
-- scanf family and strtod
--------------------------------------------------------------------------------

local function MatchFloatToken(s)
	return smatch(s, "^[+-]?%d+%.?%d*[eE][+-]?%d+")
		or smatch(s, "^[+-]?%.%d+[eE][+-]?%d+")
		or smatch(s, "^[+-]?%d+%.?%d*")
		or smatch(s, "^[+-]?%.%d+")
		or smatch(s, "^[+-]?[iI][nN][fF]")
		or smatch(s, "^[+-]?[nN][aA][nN]")
end

local function FloatTokenValue(token)
	local lower = slower(token)
	if sfind(lower, "inf", 1, true) then
		return if ssub(token, 1, 1) == "-" then -huge else huge
	elseif sfind(lower, "nan", 1, true) then
		return 0 / 0
	end
	return tonumber(token) or 0
end

local function ParseIntToken(token, base)
	local sign = 1
	local first = ssub(token, 1, 1)
	if first == "-" then
		sign = -1
		token = ssub(token, 2)
	elseif first == "+" then
		token = ssub(token, 2)
	end
	if base == 16 then
		token = smatch(token, "^0[xX](.+)") or token
	end
	return sign * (tonumber(token, base) or 0)
end

local function WriteScannedInt(mem, p, lenmod, v)
	if lenmod == "hh" then
		writeu8(mem, p, v % 256)
	elseif lenmod == "h" then
		writeu16(mem, p, v % 65536)
	elseif lenmod == "ll" or lenmod == "j" or lenmod == "q" then
		writeu32(mem, p, v % 4294967296)
		writeu32(mem, p + 4, floor(v / 4294967296) % 4294967296)
	else
		writeu32(mem, p, v % 4294967296)
	end
end

local function ScanArgs(mem, strPtr, fmtPtr, ap)
	local str = ReadCString(mem, strPtr) or ""
	local fmt = ReadCString(mem, fmtPtr) or ""
	local sp, fp = 1, 1
	local slen, flen = #str, #fmt
	local assigned = 0
	local converted = false
	while fp <= flen do
		local fc = ssub(fmt, fp, fp)
		if sfind(fc, "^%s") then
			fp = sfind(fmt, "[^%s]", fp) or (flen + 1)
			sp = sfind(str, "[^%s]", sp) or (slen + 1)
		elseif fc ~= "%" then
			if ssub(str, sp, sp) ~= fc then
				break
			end
			sp += 1
			fp += 1
		else
			local s, e, suppress, width, lenmod, conv = sfind(fmt, "^%%(%*?)(%d*)([hljztLq]*)([%%diouxXeEfFgGaAcspn%[])", fp)
			if s == nil then
				break
			end
			fp = e + 1
			if conv == "%" then
				sp = sfind(str, "[^%s]", sp) or (slen + 1)
				if ssub(str, sp, sp) ~= "%" then
					break
				end
				sp += 1
			elseif conv == "n" then
				if suppress == "" then
					writei32(mem, readu32(mem, ap), sp - 1)
					ap += 4
				end
			elseif conv == "[" then
				break -- scan sets are not used by Dear ImGui
			else
				if conv ~= "c" then
					sp = sfind(str, "[^%s]", sp) or (slen + 1)
				end
				if sp > slen then
					if not converted then
						return -1
					end
					break
				end
				local w = tonumber(width)
				local field = if w then ssub(str, sp, sp + w - 1) else ssub(str, sp)
				local token, value
				if conv == "d" or conv == "u" then
					token = smatch(field, "^[+-]?%d+")
					value = token and ParseIntToken(token, 10)
				elseif conv == "i" then
					token = smatch(field, "^[+-]?0[xX]%x+")
					if token then
						value = ParseIntToken(token, 16)
					else
						token = smatch(field, "^[+-]?%d+")
						value = token and ParseIntToken(token, 10)
					end
				elseif conv == "x" or conv == "X" or conv == "p" then
					token = smatch(field, "^[+-]?0[xX]%x+") or smatch(field, "^[+-]?%x+")
					value = token and ParseIntToken(token, 16)
				elseif conv == "o" then
					token = smatch(field, "^[+-]?[0-7]+")
					value = token and ParseIntToken(token, 8)
				elseif conv == "c" then
					token = ssub(str, sp, sp + (w or 1) - 1)
					if #token < (w or 1) then
						break
					end
				elseif conv == "s" then
					token = smatch(field, "^[^%s]+")
				else
					token = MatchFloatToken(field)
					value = token and FloatTokenValue(token)
				end
				if token == nil or token == "" then
					break
				end
				sp += #token
				converted = true
				if suppress == "" then
					local p = readu32(mem, ap)
					ap += 4
					if conv == "c" then
						writestring(mem, p, token)
					elseif conv == "s" then
						writestring(mem, p, token)
						writeu8(mem, p + #token, 0)
					elseif sfind("eEfFgGaA", conv, 1, true) then
						if lenmod == "l" or lenmod == "L" then
							writef64(mem, p, value)
						else
							writef32(mem, p, value)
						end
					else
						WriteScannedInt(mem, p, lenmod, value)
					end
					assigned += 1
				end
			end
		end
	end
	return assigned
end

local function StrToD(mem, strPtr, endPtr)
	local s = ReadCString(mem, strPtr) or ""
	local ws = smatch(s, "^%s*")
	local token = MatchFloatToken(ssub(s, #ws + 1))
	local value, consumed = 0, 0
	if token then
		value = FloatTokenValue(token)
		consumed = #ws + #token
	end
	if endPtr ~= 0 then
		writeu32(mem, endPtr, strPtr + consumed)
	end
	return value
end

--------------------------------------------------------------------------------
-- WebAssembly imports
--------------------------------------------------------------------------------

local function Closure(fn)
	return { fn }
end

local function MissingImportTable(moduleName, fallbackResult)
	return setmetatable({}, {
		__index = function(self, name)
			local stub = Closure(function()
				warn(sformat("[ImGui] unimplemented import %s.%s", moduleName, tostring(name)))
				return fallbackResult
			end)
			rawset(self, name, stub)
			return stub
		end,
	})
end

local AssertsSeen = {}

local function BuildImports(options, measureGlyph)
	local msin, mcos, mtan, masin, macos, matan, matan2 = math.sin, math.cos, math.tan, math.asin, math.acos, math.atan, math.atan2
	local msinh, mcosh, mtanh, mexp, mlog, mlog10, mfmod = math.sinh, math.cosh, math.tanh, math.exp, math.log, math.log10, math.fmod

	local env = MissingImportTable("env", 0)
	env.sin = Closure(function(_, x) return msin(x) end)
	env.cos = Closure(function(_, x) return mcos(x) end)
	env.tan = Closure(function(_, x) return mtan(x) end)
	env.asin = Closure(function(_, x) return masin(x) end)
	env.acos = Closure(function(_, x) return macos(x) end)
	env.atan = Closure(function(_, x) return matan(x) end)
	env.atan2 = Closure(function(_, y, x) return matan2(y, x) end)
	env.sinh = Closure(function(_, x) return msinh(x) end)
	env.cosh = Closure(function(_, x) return mcosh(x) end)
	env.tanh = Closure(function(_, x) return mtanh(x) end)
	env.exp = Closure(function(_, x) return mexp(x) end)
	env.log = Closure(function(_, x) return mlog(x) end)
	env.log10 = Closure(function(_, x) return mlog10(x) end)
	env.log2 = Closure(function(_, x) return mlog(x, 2) end)
	env.pow = Closure(function(_, x, y) return x ^ y end)
	env.fmod = Closure(function(_, x, y) return mfmod(x, y) end)
	env.round = Closure(function(_, x)
		if x >= 0 then
			return floor(x + 0.5)
		end
		return -floor(-x + 0.5)
	end)

	env.emscripten_notify_memory_growth = Closure(function() end)

	env.vsnprintf = Closure(function(_, buf, size, fmt, args)
		local mem = Mem()
		local text = FormatArgs(mem, fmt, args)
		local total = #text
		if size > 0 and buf ~= 0 then
			local count = if total < size then total else size - 1
			if count > 0 then
				writestring(mem, buf, text, count)
			end
			writeu8(mem, buf + count, 0)
		end
		return total
	end)
	env.vsscanf = Closure(function(_, str, fmt, args)
		return ScanArgs(Mem(), str, fmt, args) % 4294967296
	end)
	env.strtod = Closure(function(_, str, endPtr)
		return StrToD(Mem(), str, endPtr)
	end)

	env.glyph_advance = Closure(function(_, slot, size, codepoint)
		return measureGlyph(slot, size, codepoint)
	end)
	env.set_clipboard = Closure(function(_, ptr)
		local text = ReadCString(Mem(), ptr) or ""
		local setter = options.SetClipboard or setclipboard or toclipboard
		if setter ~= nil then
			pcall(setter, text)
		end
	end)
	env.assert_failed = Closure(function(_, expr, file, line)
		local mem = Mem()
		local key = sformat("%d:%d", file, line)
		if not AssertsSeen[key] then
			AssertsSeen[key] = true
			warn(sformat("[ImGui] assertion failed: %s (%s:%d)", ReadCString(mem, expr) or "?", ReadCString(mem, file) or "?", line))
		end
	end)
	env.log_message = Closure(function(_, ptr)
		print("[ImGui] " .. (ReadCString(Mem(), ptr) or ""))
	end)

	local pendingOutput = ""
	local wasi = MissingImportTable("wasi_snapshot_preview1", 52) -- ENOSYS
	wasi.fd_write = Closure(function(_, _fd, iovs, iovsLen, writtenPtr)
		local mem = Mem()
		local total = 0
		for i = 0, iovsLen - 1 do
			local base = readu32(mem, iovs + i * 8)
			local len = readu32(mem, iovs + i * 8 + 4)
			if len > 0 then
				pendingOutput ..= readstring(mem, base, len)
			end
			total += len
		end
		while true do
			local newline = sfind(pendingOutput, "\n", 1, true)
			if newline == nil then
				break
			end
			print("[ImGui] " .. ssub(pendingOutput, 1, newline - 1))
			pendingOutput = ssub(pendingOutput, newline + 1)
		end
		writeu32(mem, writtenPtr, total)
		return 0
	end)
	wasi.proc_exit = Closure(function(_, code)
		error("[ImGui] WebAssembly module exited with code " .. tostring(code))
	end)

	return { env = env, wasi_snapshot_preview1 = wasi }
end

--------------------------------------------------------------------------------
-- Input: UserInputService -> Dear ImGui IO events
--------------------------------------------------------------------------------

local RobloxKeyNames = {
	Tab = "Tab", Left = "LeftArrow", Right = "RightArrow", Up = "UpArrow", Down = "DownArrow",
	PageUp = "PageUp", PageDown = "PageDown", Home = "Home", End = "End", Insert = "Insert", Delete = "Delete",
	Backspace = "Backspace", Space = "Space", Return = "Enter", Escape = "Escape",
	LeftControl = "LeftCtrl", LeftShift = "LeftShift", LeftAlt = "LeftAlt", LeftSuper = "LeftSuper",
	RightControl = "RightCtrl", RightShift = "RightShift", RightAlt = "RightAlt", RightSuper = "RightSuper", Menu = "Menu",
	Zero = "0", One = "1", Two = "2", Three = "3", Four = "4", Five = "5", Six = "6", Seven = "7", Eight = "8", Nine = "9",
	Quote = "Apostrophe", Comma = "Comma", Minus = "Minus", Period = "Period", Slash = "Slash", Semicolon = "Semicolon",
	Equals = "Equal", LeftBracket = "LeftBracket", BackSlash = "Backslash", RightBracket = "RightBracket", Backquote = "GraveAccent",
	CapsLock = "CapsLock", ScrollLock = "ScrollLock", NumLock = "NumLock", Print = "PrintScreen", Pause = "Pause",
	KeypadZero = "Keypad0", KeypadOne = "Keypad1", KeypadTwo = "Keypad2", KeypadThree = "Keypad3", KeypadFour = "Keypad4",
	KeypadFive = "Keypad5", KeypadSix = "Keypad6", KeypadSeven = "Keypad7", KeypadEight = "Keypad8", KeypadNine = "Keypad9",
	KeypadPeriod = "KeypadDecimal", KeypadDivide = "KeypadDivide", KeypadMultiply = "KeypadMultiply",
	KeypadMinus = "KeypadSubtract", KeypadPlus = "KeypadAdd", KeypadEnter = "KeypadEnter", KeypadEquals = "KeypadEqual",
}
for i = 0, 25 do
	local letter = schar(65 + i)
	RobloxKeyNames[letter] = letter
end
for i = 1, 24 do
	RobloxKeyNames["F" .. i] = "F" .. i
end

-- US keyboard layout (UserInputService exposes key codes, not text)
local PlainChars = {
	Space = " ", Zero = "0", One = "1", Two = "2", Three = "3", Four = "4", Five = "5", Six = "6", Seven = "7", Eight = "8", Nine = "9",
	Quote = "'", Comma = ",", Minus = "-", Period = ".", Slash = "/", Semicolon = ";", Equals = "=",
	LeftBracket = "[", BackSlash = "\\", RightBracket = "]", Backquote = "`",
	KeypadZero = "0", KeypadOne = "1", KeypadTwo = "2", KeypadThree = "3", KeypadFour = "4",
	KeypadFive = "5", KeypadSix = "6", KeypadSeven = "7", KeypadEight = "8", KeypadNine = "9",
	KeypadPeriod = ".", KeypadDivide = "/", KeypadMultiply = "*", KeypadMinus = "-", KeypadPlus = "+", KeypadEquals = "=",
	QuotedDouble = "\"", Hash = "#", Dollar = "$", Percent = "%", Ampersand = "&", LeftParenthesis = "(", RightParenthesis = ")",
	Asterisk = "*", Plus = "+", Colon = ":", LessThan = "<", GreaterThan = ">", Question = "?", At = "@", Caret = "^",
	Underscore = "_", LeftCurly = "{", Pipe = "|", RightCurly = "}", Tilde = "~",
}
local ShiftChars = {
	Zero = ")", One = "!", Two = "@", Three = "#", Four = "$", Five = "%", Six = "^", Seven = "&", Eight = "*", Nine = "(",
	Quote = "\"", Comma = "<", Minus = "_", Period = ">", Slash = "?", Semicolon = ":", Equals = "+",
	LeftBracket = "{", BackSlash = "|", RightBracket = "}", Backquote = "~",
}

-- Characters Dear ImGui has a key for: lets shortcut keys follow the keyboard layout
local LayoutKeys = {
	["'"] = "Apostrophe", [","] = "Comma", ["-"] = "Minus", ["."] = "Period", ["/"] = "Slash", [";"] = "Semicolon",
	["="] = "Equal", ["["] = "LeftBracket", ["\\"] = "Backslash", ["]"] = "RightBracket", ["`"] = "GraveAccent",
}
for i = 0, 25 do
	LayoutKeys[schar(65 + i)] = schar(65 + i)
end
for i = 0, 9 do
	LayoutKeys[tostring(i)] = tostring(i)
end

local KeyByName = {}
local ModKeys = {}

local function CreateUserInput(options)
	local UIS = game:GetService("UserInputService")
	local KeyCode = Enum.KeyCode
	local UserInputType = Enum.UserInputType
	local blockInput = options.BlockGameInput ~= false
	local connections = {}
	local events = {}
	local repeatKey, repeatCodepoint, repeatAt = nil, 0, 0
	local textBox = nil
	local captureRetryAt = 0
	local pasteKeyAt, pasteText, pasteTextAt = nil, nil, 0

	local function push(kind, a, b)
		events[#events + 1] = { kind, a, b }
	end

	local function isDown(left, right)
		return UIS:IsKeyDown(left) or UIS:IsKeyDown(right)
	end

	local function typing()
		return textBox ~= nil and textBox:IsFocused()
	end

	-- KeyCodes name QWERTY positions (AZERTY's A key is KeyCode.Q). GetStringForKeyCode says which character the
	-- user's layout puts on that key, so Ctrl+A, Ctrl+Z, ... match the letters printed on the keyboard.
	local keyForCode = {}
	local function ImGuiKeyFor(keyCode)
		local key = keyForCode[keyCode]
		if key == nil then
			key = RobloxKeyNames[keyCode.Name] or false
			if key then
				local ok, label = pcall(UIS.GetStringForKeyCode, UIS, keyCode)
				local layoutKey = ok and type(label) == "string" and LayoutKeys[string.upper(label)]
				if layoutKey then
					key = layoutKey
				end
			end
			keyForCode[keyCode] = key
		end
		return key or nil
	end

	-- Fallback for when the hidden TextBox cannot take focus: layout letters, US symbols
	local function charFor(keyCode)
		if isDown(KeyCode.LeftControl, KeyCode.RightControl) or isDown(KeyCode.LeftAlt, KeyCode.RightAlt) then
			return nil
		end
		local shift = isDown(KeyCode.LeftShift, KeyCode.RightShift)
		local name = keyCode.Name
		if #name == 1 and name >= "A" and name <= "Z" then
			local key = ImGuiKeyFor(keyCode)
			local letter = if key ~= nil and #key == 1 and key >= "A" and key <= "Z" then key else name
			return if shift then letter else slower(letter)
		end
		return (shift and ShiftChars[name]) or PlainChars[name]
	end

	connections[#connections + 1] = UIS.InputBegan:Connect(function(input)
		local inputType = input.UserInputType
		if inputType == UserInputType.MouseButton1 then
			push("button", 0, true)
		elseif inputType == UserInputType.MouseButton2 then
			push("button", 1, true)
		elseif inputType == UserInputType.MouseButton3 then
			push("button", 2, true)
		elseif inputType == UserInputType.Keyboard then
			local keyCode = input.KeyCode
			if typing() and ImGuiKeyFor(keyCode) == "V" and isDown(KeyCode.LeftControl, KeyCode.RightControl)
				and not isDown(KeyCode.LeftAlt, KeyCode.RightAlt) then
				pasteKeyAt = clock() -- Ctrl+V: the TextBox receives the system clipboard first (see pump)
				return
			end
			push("key", keyCode, true)
			if not typing() then
				local ch = charFor(keyCode)
				if ch then
					local codepoint = utf8.codepoint(ch)
					push("char", codepoint)
					repeatKey, repeatCodepoint, repeatAt = keyCode, codepoint, clock() + 0.45
				end
			end
		end
	end)
	connections[#connections + 1] = UIS.InputEnded:Connect(function(input)
		local inputType = input.UserInputType
		if inputType == UserInputType.MouseButton1 then
			push("button", 0, false)
		elseif inputType == UserInputType.MouseButton2 then
			push("button", 1, false)
		elseif inputType == UserInputType.MouseButton3 then
			push("button", 2, false)
		elseif inputType == UserInputType.Keyboard then
			push("key", input.KeyCode, false)
			if repeatKey == input.KeyCode then
				repeatKey = nil
			end
		end
	end)
	connections[#connections + 1] = UIS.InputChanged:Connect(function(input)
		if input.UserInputType == UserInputType.MouseWheel then
			push("wheel", 0, input.Position.Z)
		end
	end)
	connections[#connections + 1] = UIS.WindowFocused:Connect(function()
		table.clear(keyForCode) -- the layout may have changed while Roblox was in the background
		push("focus", true)
	end)
	connections[#connections + 1] = UIS.WindowFocusReleased:Connect(function()
		push("focus", false)
	end)

	local sinkGui, sinkButton, sinkScroller = nil, nil, nil
	local sinkVisible = false
	pcall(function()
		sinkGui = Instance.new("ScreenGui")
		sinkGui.Name = "DearImGuiInputSink"
		sinkGui.IgnoreGuiInset = true
		sinkGui.ResetOnSpawn = false
		sinkGui.DisplayOrder = 2147483647

		-- Typed text comes from a hidden TextBox, which receives what the keyboard layout produces (AltGr, dead keys, IME)
		textBox = Instance.new("TextBox")
		textBox.Name = "TextInput"
		textBox.BackgroundTransparency = 1
		textBox.TextTransparency = 1
		textBox.Text = ""
		textBox.ClearTextOnFocus = false
		textBox.MultiLine = true
		textBox.Size = UDim2.fromOffset(1, 1)
		textBox.Parent = sinkGui

		if blockInput then
			-- Shown while Dear ImGui wants the mouse. The modal button frees a first-person mouse; the scrolling frame
			-- marks clicks and wheel input as processed, so the default camera neither zooms nor rotates.
			sinkButton = Instance.new("TextButton")
			sinkButton.Name = "Sink"
			sinkButton.Size = UDim2.fromScale(1, 1)
			sinkButton.BackgroundTransparency = 1
			sinkButton.Text = ""
			sinkButton.AutoButtonColor = false
			sinkButton.Modal = true
			sinkButton.Visible = false
			sinkButton.Parent = sinkGui

			sinkScroller = Instance.new("ScrollingFrame")
			sinkScroller.Name = "WheelSink"
			sinkScroller.Size = UDim2.fromScale(1, 1)
			sinkScroller.BackgroundTransparency = 1
			sinkScroller.BorderSizePixel = 0
			sinkScroller.CanvasSize = UDim2.fromScale(3, 3)
			sinkScroller.ScrollBarThickness = 0
			sinkScroller.ScrollingDirection = Enum.ScrollingDirection.XY
			sinkScroller.ElasticBehavior = Enum.ElasticBehavior.Never
			sinkScroller.ZIndex = 2
			sinkScroller.Visible = false
			sinkScroller.Parent = sinkGui
		end

		-- Prefer a container game scripts cannot see. A LocalScript is not allowed in CoreGui, but assigning the parent
		-- there does not error (it stays nil), so check where the ScreenGui actually ended up.
		local parents = {
			function()
				return gethui()
			end,
			function()
				return game:GetService("CoreGui")
			end,
			function()
				return game:GetService("Players").LocalPlayer:WaitForChild("PlayerGui")
			end,
		}
		for _, getParent in parents do
			local ok, parent = pcall(getParent)
			if ok and parent ~= nil then
				pcall(function()
					sinkGui.Parent = parent
				end)
				if sinkGui.Parent == parent then
					break
				end
			end
		end
	end)
	if sinkGui ~= nil and sinkGui.Parent == nil then
		warn("[ImGui] could not place the input GUI: typed text follows the US layout and the camera may zoom on scroll")
		sinkGui:Destroy()
		sinkGui, textBox, sinkButton, sinkScroller = nil, nil, nil, nil
	end

	if textBox ~= nil then
		local clearing = false
		connections[#connections + 1] = textBox:GetPropertyChangedSignal("Text"):Connect(function()
			local text = textBox.Text
			if clearing or text == "" then
				return
			end
			clearing = true
			textBox.Text = ""
			clearing = false
			if isDown(KeyCode.LeftControl, KeyCode.RightControl) and not isDown(KeyCode.LeftAlt, KeyCode.RightAlt) then
				-- Ctrl without Alt (AltGr is Ctrl+Alt): a Ctrl+V paste, or the TextBox's own undo. Only a paste uses it.
				pasteText, pasteTextAt = text, clock()
				return
			end
			pcall(function()
				for _, codepoint in utf8.codes(text) do
					if codepoint >= 32 and codepoint ~= 127 then
						push("char", codepoint) -- Enter, Tab and Backspace reach Dear ImGui as key events instead
					end
				end
			end)
		end)
	end

	local CAS = game:GetService("ContextActionService")
	local keyboardSunk = false
	local sinkKeys = nil

	local lastX, lastY = nil, nil
	local modState = { false, false, false, false }
	local modPairs = {
		{ KeyCode.LeftControl, KeyCode.RightControl },
		{ KeyCode.LeftShift, KeyCode.RightShift },
		{ KeyCode.LeftAlt, KeyCode.RightAlt },
		{ KeyCode.LeftSuper, KeyCode.RightSuper },
	}

	local function pump()
		for i = 1, 4 do
			local pair = modPairs[i]
			local down = UIS:IsKeyDown(pair[1]) or UIS:IsKeyDown(pair[2])
			if down ~= modState[i] then
				modState[i] = down
				ImGui.AddKeyEvent(ModKeys[i - 1], down)
			end
		end
		local count = #events
		if count > 0 then
			for i = 1, count do
				local event = events[i]
				local kind = event[1]
				if kind == "button" then
					ImGui.AddMouseButtonEvent(event[2], event[3])
				elseif kind == "key" then
					local imguiName = ImGuiKeyFor(event[2])
					if imguiName then
						ImGui.AddKeyEvent(imguiName, event[3])
					end
				elseif kind == "char" then
					ImGui.AddInputCharacter(event[2])
				elseif kind == "wheel" then
					ImGui.AddMouseWheelEvent(event[2], event[3])
				elseif kind == "focus" then
					ImGui.AddFocusEvent(event[2])
					lastX, lastY = nil, nil -- Dear ImGui forgets the mouse position on focus changes: send it again
				end
			end
			tclear(events)
		end
		if pasteKeyAt ~= nil then
			local text = if pasteText ~= nil and math.abs(pasteTextAt - pasteKeyAt) < 0.25 then pasteText else nil
			if text ~= nil or clock() - pasteKeyAt > 0.1 then
				if text ~= nil then
					ImGui.SetClipboardText(text) -- Dear ImGui pastes from its own clipboard: put the system clipboard in it
				end
				local ctrl = modState[1]
				if not ctrl then
					ImGui.AddKeyEvent(ModKeys[0], true)
				end
				ImGui.AddKeyEvent("V", true)
				ImGui.AddKeyEvent("V", false)
				if not ctrl then
					ImGui.AddKeyEvent(ModKeys[0], false)
				end
				pasteKeyAt, pasteText = nil, nil
			end
		end
		local mouse = UIS:GetMouseLocation()
		if mouse.X ~= lastX or mouse.Y ~= lastY then
			lastX, lastY = mouse.X, mouse.Y
			ImGui.AddMousePosEvent(lastX, lastY)
		end
		if repeatKey then
			if typing() or not UIS:IsKeyDown(repeatKey) then
				repeatKey = nil
			elseif clock() >= repeatAt then
				ImGui.AddInputCharacter(repeatCodepoint)
				repeatAt = clock() + 0.035
			end
		end
	end

	local function post(state)
		local wantMouse = band(state, 1) ~= 0
		if wantMouse ~= sinkVisible then
			sinkVisible = wantMouse
			if sinkButton then
				sinkButton.Visible = wantMouse
			end
			if sinkScroller then
				sinkScroller.Visible = wantMouse
			end
		end
		if sinkScroller and wantMouse then
			-- Keep the canvas centered so the wheel always has room to scroll, and so stays consumed
			local size = sinkScroller.AbsoluteSize
			if sinkScroller.CanvasPosition ~= size then
				sinkScroller.CanvasPosition = size
			end
		end
		if textBox ~= nil then
			if band(state, 4) ~= 0 then
				-- A click releases the TextBox, so take focus back while the text field stays active, unless the player
				-- moved to another TextBox (chat or the game's own)
				if not textBox:IsFocused() and UIS:GetFocusedTextBox() == nil and clock() >= captureRetryAt then
					pcall(textBox.CaptureFocus, textBox)
					if not textBox:IsFocused() then
						captureRetryAt = clock() + 0.5
					end
				end
			elseif textBox:IsFocused() then
				pcall(textBox.ReleaseFocus, textBox)
			end
		end
		if blockInput then
			local wantKeyboard = band(state, 2) ~= 0
			if wantKeyboard ~= keyboardSunk then
				keyboardSunk = wantKeyboard
				if wantKeyboard then
					if sinkKeys == nil then
						sinkKeys = {}
						for name in RobloxKeyNames do
							local ok, keyCode = pcall(function()
								return KeyCode[name]
							end)
							if ok and keyCode then
								sinkKeys[#sinkKeys + 1] = keyCode
							end
						end
					end
					pcall(function()
						CAS:BindActionAtPriority("DearImGuiKeyboardSink", function()
							return Enum.ContextActionResult.Sink
						end, false, 3000, table.unpack(sinkKeys))
					end)
				else
					pcall(function()
						CAS:UnbindAction("DearImGuiKeyboardSink")
					end)
				end
			end
		end
	end

	local function cleanup()
		for _, connection in connections do
			connection:Disconnect()
		end
		if keyboardSunk then
			pcall(function()
				CAS:UnbindAction("DearImGuiKeyboardSink")
			end)
		end
		if textBox ~= nil and textBox:IsFocused() then
			pcall(textBox.ReleaseFocus, textBox)
		end
		if sinkGui then
			sinkGui:Destroy()
		end
	end

	return pump, post, cleanup
end

--------------------------------------------------------------------------------
-- Public API
--------------------------------------------------------------------------------

local Initialized = false
local Options = nil
local RenderDrawData = nil
local FrameCallbacks = {}
local Connections = {}
local InputPump, InputPost, InputCleanup = nil, nil, nil
local LastClock = nil
local IOState = 0
local FrameStats = { Input = 0, NewFrame = 0, Callbacks = 0, Render = 0, Draw = 0, Total = 0 }
local F = {} -- frequently used export closures
local Backend, RenderMode = nil, nil
local FontSlots = {} -- font slot (0-7, stored in glyph texels) -> Drawing font index
local LastFrameError, LastFrameErrorTime = nil, 0
local TextMetrics = nil -- checks glyph advances against drawn text (Renderer.CreateGlyphMeasurer)

local RequiredExports = {
	"_initialize", "malloc", "free", "emscripten_stack_get_current", "_emscripten_stack_restore",
	"rbx_init", "rbx_shutdown", "rbx_add_font", "rbx_new_frame", "rbx_render", "rbx_io_state",
	"rbx_io_mouse_pos", "rbx_io_mouse_button", "rbx_io_mouse_wheel", "rbx_io_key", "rbx_io_char", "rbx_io_focus",
	"rbx_key_named_begin", "rbx_key_named_end", "rbx_key_name", "rbx_key_mod",
	"rbx_scratch", "rbx_scratch_size", "rbx_return_slots", "rbx_save_ini", "rbx_load_ini", "rbx_set_clipboard_buffer",
	"rbx_discard_font_bakes",
}

local function GetDisplaySize()
	local size = Options.DisplaySize
	if size ~= nil then
		return size.X, size.Y
	end
	if Backend ~= nil and Backend.GetDisplaySize ~= nil then
		local w, h = Backend.GetDisplaySize()
		if w ~= nil then
			return w, h
		end
	end
	local camera = workspace and workspace.CurrentCamera
	if camera then
		local viewport = camera.ViewportSize
		return viewport.X, viewport.Y
	end
	return 1920, 1080
end

local ThemeFunctions = { Dark = "StyleColorsDark", Light = "StyleColorsLight", Classic = "StyleColorsClassic" }

local function AllocateFontSlot(font)
	for slot = 0, 7 do
		if FontSlots[slot] == font then
			return slot
		end
	end
	for slot = 0, 7 do
		if FontSlots[slot] == nil then
			FontSlots[slot] = font
			return slot
		end
	end
	error("[ImGui] at most 8 different fonts can be used at once", 3)
end

local function ResolveRenderMode(options)
	local mode = Renderer.NormalizeMode(options.RenderMode)
	if mode ~= "Auto" then
		return mode
	end
	local custom = options.Renderer
	if custom ~= nil then
		return if type(custom) == "table" and custom.FilledRectangle ~= nil then "DrawingImmediate" else "Custom"
	elseif options.DrawingImmediate ~= nil or (DrawingImmediate ~= nil and DrawingImmediate.GetPaint ~= nil) then
		return "DrawingImmediate"
	elseif options.Drawing ~= nil or (Drawing ~= nil and Drawing.new ~= nil) then
		return "Drawing"
	end
	error("[ImGui] no render mode is available here; pass RenderMode together with a DrawingImmediate or Drawing library", 3)
end

-- Returns the backend, plus the DrawingImmediate library whose GetPaint event drives frames in that mode
local function CreateBackend(mode, options)
	if mode == "DrawingImmediate" then
		local custom = options.Renderer
		local lib = options.DrawingImmediate or (if type(custom) == "table" and custom.FilledRectangle ~= nil then custom else nil) or DrawingImmediate
		if lib == nil then
			error('[ImGui] RenderMode "DrawingImmediate" needs the DrawingImmediate library (Potassium); use "Drawing" elsewhere', 3)
		end
		if options.AutoRender ~= false and lib.GetPaint == nil then
			error("[ImGui] DrawingImmediate.GetPaint is missing; set AutoRender = false and call ImGui.Step() from your own paint callback", 3)
		end
		return Renderer.DrawingImmediate(lib, FontSlots), lib
	elseif mode == "Drawing" then
		local lib = options.Drawing or Drawing
		if lib == nil or lib.new == nil then
			error('[ImGui] RenderMode "Drawing" needs the Drawing library (Drawing.new)', 3)
		end
		return Renderer.Drawing(lib, FontSlots, options), nil
	end
	if type(options.Renderer) ~= "table" then
		error("[ImGui] options.Renderer must be a table implementing Rect, Polygon and Text", 3)
	end
	return options.Renderer, nil
end

local function SafeStep()
	local ok, err = pcall(ImGui.Step)
	if not ok then
		local message = tostring(err)
		local now = clock()
		if message ~= LastFrameError or now - LastFrameErrorTime > 5 then
			LastFrameError, LastFrameErrorTime = message, now
			warn("[ImGui] " .. message)
		end
	end
end

local function StartFrameLoop(mode, options, paintLibrary)
	if options.AutoRender == false then
		return
	end
	if mode == "DrawingImmediate" then
		Connections[#Connections + 1] = paintLibrary.GetPaint(options.ZIndex or 1):Connect(SafeStep)
		return
	end
	if game == nil then
		error("[ImGui] AutoRender needs RunService; set AutoRender = false and call ImGui.Step() yourself", 3)
	end
	Connections[#Connections + 1] = game:GetService("RunService").RenderStepped:Connect(SafeStep)
end

local function ApplyStyleOptions(options)
	if options.Theme ~= nil then
		ImGui[ThemeFunctions[options.Theme]]()
	end
	local scale = options.Scale
	if scale ~= nil and scale ~= 1 then
		local style = ImGui.GetStyle()
		style:ScaleAllSizes(scale)
		style.FontScaleMain = scale
	end
	if options.IniSettings ~= nil then
		ImGui.LoadIniSettings(options.IniSettings)
	end
end

function ImGui.Init(options)
	if Initialized then
		return ImGui
	end
	options = options or {}
	if type(options) ~= "table" then
		error("[ImGui] ImGui.Init expects a table of options", 2)
	end
	if options.Theme ~= nil and ThemeFunctions[options.Theme] == nil then
		error('[ImGui] Theme must be "Dark", "Light" or "Classic"', 2)
	end
	local startTime = clock()
	local mode = ResolveRenderMode(options)
	tclear(FontSlots)
	local baseSlot = AllocateFontSlot(Renderer.ResolveFont(mode, options.Font))
	local backend, paintLibrary = CreateBackend(mode, options)

	local ok, err = pcall(function()
		Options = options
		local measureGlyph, textMetrics = Renderer.CreateGlyphMeasurer(mode, options, FontSlots)
		TextMetrics = textMetrics
		Exports = WasmInstantiate(BuildImports(options, measureGlyph))
		MemoryBox = Exports.memory
		for _, name in RequiredExports do
			local closure = Exports[name]
			if closure == nil then
				error("[ImGui] missing WebAssembly export: " .. name)
			end
			F[name] = closure
		end

		F._initialize[1](F._initialize)
		F.rbx_init[1](F.rbx_init, baseSlot, options.FontSize or 13)

		local keyBegin = F.rbx_key_named_begin[1](F.rbx_key_named_begin)
		local keyEnd = F.rbx_key_named_end[1](F.rbx_key_named_end)
		for key = keyBegin, keyEnd - 1 do
			local name = ReadCString(Mem(), (F.rbx_key_name[1](F.rbx_key_name, key)))
			if name then
				KeyByName[name] = key
			end
		end
		for i = 0, 3 do
			ModKeys[i] = (F.rbx_key_mod[1](F.rbx_key_mod, i))
		end

		Api.Exports = Exports
		Api.Scratch = (F.rbx_scratch[1](F.rbx_scratch))
		Api.ScratchSize = (F.rbx_scratch_size[1](F.rbx_scratch_size))
		Api.ReturnSlots = (F.rbx_return_slots[1](F.rbx_return_slots))
		if Api.OnInit then
			Api.OnInit()
		end
		ApplyStyleOptions(options)

		Backend, RenderMode = backend, mode
		RenderDrawData = Renderer.CreateWalker(backend, measureGlyph, options, textMetrics)
		if options.Input ~= false and game ~= nil then
			InputPump, InputPost, InputCleanup = CreateUserInput(options)
		end
	end)
	if not ok then
		if InputCleanup then
			InputCleanup()
		end
		InputPump, InputPost, InputCleanup = nil, nil, nil
		if backend.Destroy ~= nil then
			pcall(backend.Destroy)
		end
		if TextMetrics ~= nil then
			TextMetrics.Destroy()
			TextMetrics = nil
		end
		Backend, RenderMode, RenderDrawData = nil, nil, nil
		tclear(FontSlots)
		error(err, 0)
	end

	Initialized = true
	ImGui.RenderMode = mode
	StartFrameLoop(mode, options, paintLibrary)
	ImGui.InitTime = clock() - startTime
	return ImGui
end

-- Runs one Dear ImGui frame: input -> NewFrame -> OnFrame callbacks -> Render -> render mode calls.
function ImGui.Step(deltaTime, displayWidth, displayHeight)
	if not Initialized then
		error("[ImGui] call ImGui.Init() first", 2)
	end
	local now = clock()
	if deltaTime == nil then
		deltaTime = if LastClock then now - LastClock else 1 / 60
	end
	LastClock = now
	if displayWidth == nil then
		displayWidth, displayHeight = GetDisplaySize()
	end
	local t0 = clock()
	if InputPump then
		InputPump()
	end

	local t1 = clock()
	local stackPointer = (F.emscripten_stack_get_current[1](F.emscripten_stack_get_current))
	F.rbx_new_frame[1](F.rbx_new_frame, displayWidth, displayHeight, deltaTime)
	local t2 = clock()
	local callbacks = FrameCallbacks
	for i = 1, #callbacks do
		local callback = callbacks[i]
		if callback then
			local ok, err = pcall(callback, ImGui)
			if not ok then
				warn("[ImGui] frame callback error: " .. tostring(err))
				F._emscripten_stack_restore[1](F._emscripten_stack_restore, stackPointer)
			end
		end
	end
	local t3 = clock()
	local tablePtr = (F.rbx_render[1](F.rbx_render))
	local t4 = clock()
	RenderDrawData(Mem(), tablePtr)
	if TextMetrics.Step() then
		F.rbx_discard_font_bakes[1](F.rbx_discard_font_bakes) -- advances were corrected: Dear ImGui measures its glyphs again
	end
	local t5 = clock()
	IOState = (F.rbx_io_state[1](F.rbx_io_state))
	if InputPost then
		InputPost(IOState)
	end

	local stats = FrameStats
	stats.Input = t1 - t0
	stats.NewFrame = t2 - t1
	stats.Callbacks = t3 - t2
	stats.Render = t4 - t3
	stats.Draw = t5 - t4
	stats.Total = clock() - t0
end

-- Seconds spent in each part of the last ImGui.Step(): Input, NewFrame, Callbacks (your UI code),
-- Render (ImGui::Render + draw table), Draw (render mode calls) and Total.
function ImGui.GetFrameStats()
	return FrameStats
end

-- How glyph advances are measured. Source: "Drawing", "TextService", "MeasureText" or "Estimate"; Measured: glyphs
-- measured per source; Fonts: per font and size, the Scale applied after comparing with drawn text, whether that
-- comparison confirmed the advances (Verified), how many comparisons ran (Attempts) and the last Ratio.
function ImGui.GetTextMetricsInfo()
	return if TextMetrics ~= nil then TextMetrics.Info() else nil
end

function ImGui.OnFrame(callback)
	table.insert(FrameCallbacks, callback)
	return {
		Disconnect = function()
			local index = table.find(FrameCallbacks, callback)
			if index then
				table.remove(FrameCallbacks, index)
			end
		end,
	}
end

function ImGui.Shutdown()
	for _, connection in Connections do
		pcall(function()
			connection:Disconnect()
		end)
	end
	tclear(Connections)
	tclear(FrameCallbacks)
	if InputCleanup then
		InputCleanup()
	end
	InputPump, InputPost, InputCleanup = nil, nil, nil
	if Initialized then
		F.rbx_shutdown[1](F.rbx_shutdown)
	end
	if Backend ~= nil and Backend.Destroy ~= nil then
		pcall(Backend.Destroy)
	end
	if TextMetrics ~= nil then
		TextMetrics.Destroy()
		TextMetrics = nil
	end
	Backend, RenderMode, RenderDrawData = nil, nil, nil
	ImGui.RenderMode = nil
	tclear(FontSlots)
	Initialized = false
end

function ImGui.IsInitialized()
	return Initialized
end

function ImGui.AddMousePosEvent(x, y)
	F.rbx_io_mouse_pos[1](F.rbx_io_mouse_pos, x, y)
end

function ImGui.AddMouseButtonEvent(button, down)
	F.rbx_io_mouse_button[1](F.rbx_io_mouse_button, button, if down then 1 else 0)
end

function ImGui.AddMouseWheelEvent(wheelX, wheelY)
	F.rbx_io_mouse_wheel[1](F.rbx_io_mouse_wheel, wheelX, wheelY)
end

-- key: ImGuiKey value, or a Dear ImGui key name such as "Enter" or "LeftArrow"
function ImGui.AddKeyEvent(key, down)
	if type(key) == "string" then
		key = KeyByName[key]
		if key == nil then
			return
		end
	end
	F.rbx_io_key[1](F.rbx_io_key, key, if down then 1 else 0)
end

function ImGui.AddInputCharacter(codepoint)
	F.rbx_io_char[1](F.rbx_io_char, codepoint)
end

function ImGui.AddInputCharactersUTF8(text)
	for _, codepoint in utf8.codes(text) do
		F.rbx_io_char[1](F.rbx_io_char, codepoint)
	end
end

function ImGui.AddFocusEvent(focused)
	F.rbx_io_focus[1](F.rbx_io_focus, if focused then 1 else 0)
end

function ImGui.GetKeyIndex(name)
	return KeyByName[name]
end

function ImGui.WantCaptureMouse()
	return band(IOState, 1) ~= 0
end

function ImGui.WantCaptureKeyboard()
	return band(IOState, 2) ~= 0
end

function ImGui.WantTextInput()
	return band(IOState, 4) ~= 0
end

function ImGui.GetMouseCursorShape()
	return rshift(band(IOState, 0xFF00), 8) - 1
end

-- font: a font name ("UI", "System", "Plex", "Monospace") or a Drawing font index.
-- Returns the ImFont pointer for ImGui.PushFont(font, size).
function ImGui.AddFont(font, sizePixels, mergeMode)
	if not Initialized then
		error("[ImGui] call ImGui.Init() first", 2)
	end
	local slot = AllocateFontSlot(Renderer.ResolveFont(RenderMode, font))
	return (F.rbx_add_font[1](F.rbx_add_font, slot, sizePixels or 13, if mergeMode then 1 else 0))
end

function ImGui.SaveIniSettings()
	return ReadCString(Mem(), (F.rbx_save_ini[1](F.rbx_save_ini))) or ""
end

function ImGui.LoadIniSettings(ini)
	local mem = Mem()
	local ptr = (F.malloc[1](F.malloc, #ini + 1))
	mem = Mem()
	writestring(mem, ptr, ini)
	writeu8(mem, ptr + #ini, 0)
	F.rbx_load_ini[1](F.rbx_load_ini, ptr)
	F.free[1](F.free, ptr)
end

Api.ReadCString = ReadCString
Api.Mem = Mem
if InstallBindings then
	InstallBindings(ImGui, Api)
end

return ImGui

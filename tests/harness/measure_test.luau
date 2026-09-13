-- Glyph metrics inside an executor come from Drawing text objects. Checks the normal path and the fallbacks for
-- Drawing implementations that only measure visible text or report no bounds at all.
local ImGui = ImGuiBundle
local failures = 0
local function check(name, ok)
	print((if ok then "PASS " else "FAIL ") .. name)
	if not ok then
		failures += 1
	end
end

local function makeDrawing(mode)
	return {
		new = function(kind)
			assert(kind == "Text", "only Text objects are used for measuring")
			local object = { Visible = true, Font = 0, Size = 13, Text = "", Transparency = 1, Position = Vector2.new(0, 0) }
			return setmetatable({}, {
				__index = function(_, key)
					if key == "TextBounds" then
						if mode == "zero" or (mode == "visible-only" and not object.Visible) then
							return Vector2.new(0, 0)
						end
						return Vector2.new((utf8.len(object.Text) or #object.Text) * object.Size * 0.6, object.Size)
					end
					return object[key]
				end,
				__newindex = function(_, key, value)
					object[key] = value
				end,
			})
		end,
	}
end

local function measure(mode)
	Drawing = makeDrawing(mode)
	ImGui.Init({
		Renderer = MockDrawingImmediate,
		AutoRender = false,
		Input = false,
		Font = 3,
		FontSize = 13,
		DisplaySize = Vector2.new(800, 600),
	})
	local size
	ImGui.OnFrame(function()
		size = ImGui.CalcTextSize("abcd")
	end)
	ImGui.Step(1 / 60)
	ImGui.Shutdown()
	Drawing = nil
	return size
end

-- 13px * 0.6 = 7.8px per character; CalcTextSize rounds the width up
local normal = measure("normal")
check(string.format("Drawing.TextBounds metrics (%.1f x %.1f)", normal.X, normal.Y), normal.X == 32 and normal.Y == 13)
local visibleOnly = measure("visible-only")
check(string.format("fallback when invisible text reports no bounds (%.1f)", visibleOnly.X), visibleOnly.X == 32)
local zero = measure("zero")
check(string.format("fallback estimate when Drawing never reports bounds (%.1f)", zero.X), zero.X == 26)
print(string.format("RESULT %d failure(s)", failures))

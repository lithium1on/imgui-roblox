-- Exercises the ImGui.Init options the render mode tests don't cover: RenderMode auto-detection, Theme, Scale,
-- IniSettings, AddFont/PushFont, custom renderers and option errors.
local ImGui = ImGuiBundle
local W, H = 800, 600
local failures = 0

local function check(name, ok)
	print((if ok then "PASS " else "FAIL ") .. name)
	if not ok then
		failures += 1
	end
end

local function measure(_, size, text)
	return (utf8.len(text) or #text) * HarnessAdvance(size)
end

local function base(extra)
	local options = { AutoRender = false, Input = false, DisplaySize = Vector2.new(W, H), MeasureText = measure }
	for key, value in extra do
		options[key] = value
	end
	return options
end

-- RenderMode = "Auto" (the default) picks the first library that exists
DrawingImmediate = MockDrawingImmediate
ImGui.Init(base({}))
check("Auto picks DrawingImmediate when it exists", ImGui.RenderMode == "DrawingImmediate")
ImGui.Shutdown()
DrawingImmediate = nil
Drawing = MockDrawing
ImGui.Init(base({}))
check("Auto falls back to Drawing", ImGui.RenderMode == "Drawing")
ImGui.Shutdown()
Drawing = nil
local ok, err = pcall(ImGui.Init, base({}))
check("Auto outside Roblox without libraries errors", not ok and string.find(tostring(err), "no render mode is available", 1, true) ~= nil)

-- Theme, Scale and IniSettings
local ini = "[Window][Saved window]\nPos=222,111\nSize=300,200\nCollapsed=0\n\n"
ImGui.Init(base({ RenderMode = "DrawingImmediate", DrawingImmediate = MockDrawingImmediate, Theme = "Light", Scale = 1.5, IniSettings = ini }))
local style = ImGui.GetStyle()
check(string.format("Scale multiplies style sizes (WindowPadding %.1f)", style.WindowPadding.X), style.WindowPadding.X == 12)
check(string.format("Scale sets FontScaleMain (%.2f)", style.FontScaleMain), math.abs(style.FontScaleMain - 1.5) < 1e-6)
local windowBg = style.Colors[ImGui.Col.WindowBg]
check(string.format("Theme Light sets light colors (WindowBg %.2f)", windowBg[1]), windowBg[1] > 0.9)
local position
ImGui.OnFrame(function()
	ImGui.Begin("Saved window")
	position = ImGui.GetWindowPos()
	ImGui.End()
end)
ImGui.Step(1 / 60, W, H)
check(string.format("IniSettings restores the window position (%.0f, %.0f)", position.X, position.Y), position.X == 222 and position.Y == 111)
ImGui.Shutdown()

-- AddFont / PushFont
ImGui.Init(base({ RenderMode = "DrawingImmediate", DrawingImmediate = MockDrawingImmediate, Font = "Monospace" }))
local big = ImGui.AddFont("UI", 26)
check("AddFont returns an ImFont pointer", type(big) == "number" and big ~= 0)
check("AddFont reuses the slot of a font already added", ImGui.AddFont("UI", 26) ~= 0)
ImGui.OnFrame(function()
	ImGui.Begin("Fonts")
	ImGui.Text("Small")
	ImGui.PushFont(big, 26)
	ImGui.Text("Big")
	ImGui.PopFont()
	ImGui.End()
end)
for _ = 1, 3 do -- a new auto-sized window is hidden on its first frame
	table.clear(DrawCalls)
	ImGui.Step(1 / 60, W, H)
end
local small, large
for _, call in DrawCalls do
	if call[1] == "text" and call[10] == "Small" then
		small = call
	elseif call[1] == "text" and call[10] == "Big" then
		large = call
	end
end
check(string.format("default text uses the Init font (font %s, %spx; want Monospace = 3, 13px)", tostring(small and small[4]), tostring(small and small[5])),
	small ~= nil and small[4] == 3 and small[5] == 13)
check(string.format("PushFont draws with the added font (font %s, %spx; want UI = 0, 26px)", tostring(large and large[4]), tostring(large and large[5])),
	large ~= nil and large[4] == 0 and large[5] == 26)
ImGui.Shutdown()

-- Custom renderer
local counts = { rects = 0, polygons = 0, texts = 0, frames = 0 }
local custom = {}
function custom.BeginFrame()
	counts.frames += 1
end
function custom.Rect()
	counts.rects += 1
end
function custom.Polygon(_, _, n)
	assert(n >= 3, "polygons have at least 3 vertices")
	counts.polygons += 1
end
function custom.Text(_, _, slot, _, _, _, text)
	assert(slot == 0 and #text > 0, "text uses slot 0")
	counts.texts += 1
end
function custom.Destroy()
	counts.destroyed = true
end
ImGui.Init(base({ Renderer = custom }))
check("a Renderer table without FilledRectangle is a custom renderer", ImGui.RenderMode == "Custom")
ImGui.OnFrame(function() -- not the demo window: the lite build has none
	ImGui.SetNextWindowPos(Vector2.new(20, 20), ImGui.Cond.Always)
	ImGui.SetNextWindowSize(Vector2.new(300, 200), ImGui.Cond.Always)
	ImGui.Begin("Custom renderer")
	ImGui.Text("text")
	ImGui.Checkbox("checkbox", true)
	ImGui.End()
end)
ImGui.Step(1 / 60, W, H)
check(string.format("custom renderer receives rects=%d polygons=%d texts=%d frames=%d", counts.rects, counts.polygons, counts.texts, counts.frames),
	counts.rects > 0 and counts.polygons > 0 and counts.texts > 0 and counts.frames == 1)
ImGui.Shutdown()
check("Shutdown calls the renderer's Destroy", counts.destroyed == true)

-- Option errors leave nothing initialized
local cases = {
	{ "invalid Theme", base({ RenderMode = "DrawingImmediate", DrawingImmediate = MockDrawingImmediate, Theme = "Pink" }), "Theme must be" },
	{ "unknown font name", base({ RenderMode = "Drawing", Drawing = MockDrawing, Font = "Comic" }), "unknown font" },
	{ "font of the wrong type", base({ RenderMode = "Drawing", Drawing = MockDrawing, Font = {} }), "fonts are Drawing font indices" },
	{ "DrawingImmediate without GetPaint while AutoRender is on", { RenderMode = "DrawingImmediate", DrawingImmediate = { FilledRectangle = function() end }, Input = false }, "GetPaint is missing" },
	{ "the removed Studio mode", base({ RenderMode = "Studio" }), "unknown RenderMode" },
}
for _, case in cases do
	ok, err = pcall(ImGui.Init, case[2])
	check(string.format("%s is rejected (%s)", case[1], tostring(err)), not ok and string.find(tostring(err), case[3], 1, true) ~= nil)
end
if not ImGui.HasDocking then
	ok, err = pcall(ImGui.Init, base({ RenderMode = "DrawingImmediate", DrawingImmediate = MockDrawingImmediate, Docking = true }))
	check(string.format("Docking = true without a docking build is rejected (%s)", tostring(err)),
		not ok and string.find(tostring(err), "Docking needs a docking build", 1, true) ~= nil)
end
check("failed Init calls leave ImGui uninitialized", not ImGui.IsInitialized())

print(string.format("RESULT %d failure(s)", failures))

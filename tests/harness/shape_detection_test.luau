-- Regression test for shape detection: long thin rounded rectangles (tall scrollbar grabs, as in the demo's
-- Menu > Colors list) used to be detected as circles half their length in radius. Checks that only real circles
-- become circles, in DrawingImmediate and Drawing modes.
local ImGui = ImGuiBundle
local W, H = 1280, 1100
local failures = 0

local function check(name, ok)
	print((if ok then "PASS " else "FAIL ") .. name)
	if not ok then
		failures += 1
	end
end

local grab = ImGui.COL32(176, 176, 176, 204)

local function ShapesUI()
	ImGui.SetNextWindowPos(Vector2.new(10, 10), ImGui.Cond.Always)
	ImGui.SetNextWindowSize(Vector2.new(900, 1060), ImGui.Cond.Always)
	if ImGui.Begin("Shapes") then
		local dl = ImGui.GetWindowDrawList()
		local p = ImGui.GetCursorScreenPos()
		dl:AddRectFilled(p, p + Vector2.new(14, 900), grab, 9) -- tall thin rounded bar
		dl:AddRectFilled(p + Vector2.new(40, 0), p + Vector2.new(640, 14), grab, 9) -- wide thin rounded bar
		dl:AddRectFilled(p + Vector2.new(40, 40), p + Vector2.new(54, 54), grab, 9) -- small rounded square
		dl:AddRectFilled(p + Vector2.new(40, 300), p + Vector2.new(300, 400), grab, 12) -- rounded rectangle
		dl:AddCircleFilled(p + Vector2.new(200, 180), 80, ImGui.COL32(0, 200, 255)) -- big real circle
		dl:AddCircleFilled(p + Vector2.new(400, 180), 6, ImGui.COL32(255, 200, 0)) -- small real circle
		dl:AddNgonFilled(p + Vector2.new(500, 180), 30, ImGui.COL32(120, 255, 120), 10) -- regular decagon
		ImGui.SetCursorScreenPos(p + Vector2.new(660, 0))
		-- A child whose content is slightly taller than itself: a real scrollbar with a very long grab
		ImGui.BeginChild("long", Vector2.new(200, 900), ImGui.ChildFlags.Borders)
		ImGui.Text("Long list")
		ImGui.Dummy(Vector2.new(0, 980))
		ImGui.EndChild()
	end
	ImGui.End()
end

local function run(mode, library)
	local options = {
		RenderMode = mode, AutoRender = false, Input = false, DisplaySize = Vector2.new(W, H),
		MeasureText = function(_, size, text)
			return (utf8.len(text) or #text) * HarnessAdvance(size)
		end,
	}
	options[mode] = library
	ImGui.Init(options)
	ImGui.OnFrame(ShapesUI)
	for _ = 1, 3 do
		table.clear(DrawCalls)
		ImGui.Step(1 / 60, W, H)
	end
	local calls = if mode == "Drawing" then MockDrawing.Snapshot() else table.clone(DrawCalls)
	ImGui.Shutdown()

	local radii = {}
	local largest = 0
	for _, call in calls do
		if call[1] == "circle" then
			table.insert(radii, string.format("%.1f", call[4]))
			largest = math.max(largest, call[4])
		end
	end
	check(string.format("%s: no circle larger than the real one (radii %s)", mode, table.concat(radii, ", ")), largest <= 81)
	check(string.format("%s: the real circles are still circles (%d)", mode, #radii), #radii >= 3)

	local tallest = 0
	for _, call in calls do
		if call[1] == "rect" then
			tallest = math.max(tallest, call[5])
		elseif call[1] == "quad" then
			tallest = math.max(tallest, math.max(call[3], call[5], call[7], call[9]) - math.min(call[3], call[5], call[7], call[9]))
		end
	end
	check(string.format("%s: long bars are drawn as bars (tallest %.0f px)", mode, tallest), tallest >= 700)
	return calls
end

local immediate = run("DrawingImmediate", MockDrawingImmediate)
local drawing = run("Drawing", MockDrawing)

local roundedBars = 0
for _, call in immediate do
	if call[1] == "rect" and call[10] > 0 and (call[5] >= 700 or call[4] >= 500) then
		roundedBars += 1
	end
end
check(string.format("DrawingImmediate: long bars use FilledRectangle rounding (%d)", roundedBars), roundedBars >= 3)

print(string.format("RESULT %d failure(s)", failures))
print("SIZE:" .. W .. "x" .. H)
print("JSON:" .. EncodeJson({ "shape detection, DrawingImmediate", immediate }))
print("JSON:" .. EncodeJson({ "shape detection, Drawing", drawing }))

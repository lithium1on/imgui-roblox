-- Opens the demo window's Help section (long content: the window gets a tall scrollbar grab) and checks that no
-- circle larger than a bullet or radio button is drawn, at two display sizes.
local ImGui = ImGuiBundle
local failures = 0

local function check(name, ok)
	print((if ok then "PASS " else "FAIL ") .. name)
	if not ok then
		failures += 1
	end
end

local function run(mode, library, W, H)
	local options = {
		RenderMode = mode, AutoRender = false, Input = false, FontSize = 14, DisplaySize = Vector2.new(W, H),
		MeasureText = function(_, size, text)
			return (utf8.len(text) or #text) * HarnessAdvance(size)
		end,
	}
	options[mode] = library
	ImGui.Init(options)
	ImGui.OnFrame(function()
		ImGui.ShowDemoWindow()
	end)

	local function snapshot()
		return if mode == "Drawing" then MockDrawing.Snapshot() else table.clone(DrawCalls)
	end
	local function step(count)
		for _ = 1, count do
			table.clear(DrawCalls)
			ImGui.Step(1 / 60, W, H)
		end
	end

	step(3)
	local hx, hy
	for _, call in snapshot() do
		if call[1] == "text" and call[10] == "Help" then
			hx, hy = call[2] + 10, call[3] + call[5] / 2
		end
	end
	check(string.format("%s %dx%d: found the Help header", mode, W, H), hx ~= nil)
	if hx then
		ImGui.AddMousePosEvent(hx, hy)
		step(1)
		ImGui.AddMouseButtonEvent(0, true)
		step(1)
		ImGui.AddMouseButtonEvent(0, false)
		step(1)
		ImGui.AddMousePosEvent(5, 5)
		step(3)
	end

	local calls = snapshot()
	local helpOpen, radii, largest, tallest = false, {}, 0, 0
	for _, call in calls do
		if call[1] == "text" and string.find(call[10], "ABOUT THIS DEMO", 1, true) then
			helpOpen = true
		elseif call[1] == "circle" then
			radii[#radii + 1] = string.format("%.1f", call[4])
			largest = math.max(largest, call[4])
		elseif call[1] == "rect" and call[10] and call[10] > 0 then
			tallest = math.max(tallest, call[5])
		end
	end
	check(string.format("%s %dx%d: Help section opened", mode, W, H), helpOpen)
	check(string.format("%s %dx%d: no big circles (%d circles, largest radius %.1f)", mode, W, H, #radii, largest), largest < 20)
	if mode == "DrawingImmediate" then
		check(string.format("%s %dx%d: scrollbar grab drawn as a rounded bar (tallest %.0f px)", mode, W, H, tallest), tallest > 100)
	end
	ImGui.Shutdown()
	return calls
end

local immediate = run("DrawingImmediate", MockDrawingImmediate, 1568, 793)
run("DrawingImmediate", MockDrawingImmediate, 1920, 1009)
run("Drawing", MockDrawing, 1568, 793)
run("Drawing", MockDrawing, 1920, 1009)

print(string.format("RESULT %d failure(s)", failures))
print("SIZE:1568x793")
print("JSON:" .. EncodeJson({ "demo Help section, DrawingImmediate", immediate }))

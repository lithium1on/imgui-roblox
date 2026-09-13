-- Runs the shared widgets window through the DrawingImmediate and Drawing render modes. Checks that both modes draw
-- the same shapes and text, that Drawing objects are pooled, and that Shutdown removes them. Emits one frame per mode
-- for the viewer.
local ImGui = ImGuiBundle
local W, H = 1280, 800
local failures = 0

local function check(name, ok)
	print((if ok then "PASS " else "FAIL ") .. name)
	if not ok then
		failures += 1
	end
end

local function count(calls)
	local counts = {}
	for _, call in calls do
		counts[call[1]] = (counts[call[1]] or 0) + 1
	end
	return counts
end

local function texts(calls)
	local list = {}
	for _, call in calls do
		if call[1] == "text" then
			list[#list + 1] = call[10]
		end
	end
	return table.concat(list, "|")
end

local function run(mode, library)
	local state = WidgetsState()
	local options = {
		RenderMode = mode, AutoRender = false, Input = false, Font = "Monospace", FontSize = 13, DisplaySize = Vector2.new(W, H),
		MeasureText = function(_, size, text)
			return (utf8.len(text) or #text) * HarnessAdvance(size)
		end,
	}
	options[mode] = library
	ImGui.Init(options)
	check(mode .. ": ImGui.RenderMode", ImGui.RenderMode == mode)
	ImGui.OnFrame(function()
		WidgetsUI(ImGui, state)
	end)
	for _ = 1, 3 do
		table.clear(DrawCalls)
		ImGui.Step(1 / 60, W, H)
	end
	local calls
	if mode == "Drawing" then
		local created = MockDrawing.Created
		local writes = MockDrawing.Writes
		for _ = 1, 10 do
			ImGui.Step(1 / 60, W, H)
		end
		check(string.format("Drawing: objects pooled across frames (%d created)", created), MockDrawing.Created == created)
		check(string.format("Drawing: static frames write few properties (%d writes over 10 frames)", MockDrawing.Writes - writes), MockDrawing.Writes - writes < 200)
		calls = MockDrawing.Snapshot()
	else
		table.clear(DrawCalls)
		ImGui.Step(1 / 60, W, H)
		calls = table.clone(DrawCalls)
	end
	local stats = ImGui.GetFrameStats()
	local c = count(calls)
	print(string.format("%s: %d primitives (rect=%d quad=%d tri=%d circle=%d text=%d), frame %.2f ms",
		mode, #calls, c.rect or 0, c.quad or 0, c.tri or 0, c.circle or 0, c.text or 0, stats.Total * 1000))
	check(mode .. ": radio buttons and circles drawn natively", (c.circle or 0) >= 4)
	check(mode .. ": text runs", string.find(texts(calls), "Click me", 1, true) ~= nil and string.find(texts(calls), "Scrolling line 1", 1, true) ~= nil)
	ImGui.Shutdown()
	check(mode .. ": Shutdown resets RenderMode", ImGui.RenderMode == nil and not ImGui.IsInitialized())
	return calls
end

local immediate = run("DrawingImmediate", MockDrawingImmediate)
local drawing = run("Drawing", MockDrawing)

local removed = 0
for _, object in MockDrawing.Objects do
	if object.Removed then
		removed += 1
	end
end
check(string.format("Drawing: Shutdown removed every object (%d/%d)", removed, #MockDrawing.Objects), removed == #MockDrawing.Objects)
check("DrawingImmediate and Drawing draw the same text", texts(immediate) == texts(drawing))

local roundedTabs = 0
for _, call in immediate do
	if call[1] == "rect" and (call[10] or 0) > 0 then
		roundedTabs += 1
	end
end
check(string.format("DrawingImmediate: uniformly rounded rectangles use FilledRectangle rounding (%d)", roundedTabs), roundedTabs >= 1)

local ok, err = pcall(ImGui.Init, { RenderMode = "Nope" })
check("unknown RenderMode is rejected: " .. tostring(err), not ok and string.find(tostring(err), "unknown RenderMode", 1, true) ~= nil)
ok, err = pcall(ImGui.Init, { RenderMode = "Drawing", AutoRender = false, Input = false })
check("Drawing mode without a Drawing library is rejected: " .. tostring(err), not ok and string.find(tostring(err), "needs the Drawing library", 1, true) ~= nil)
check("failed Init leaves ImGui uninitialized", not ImGui.IsInitialized())

print(string.format("RESULT %d failure(s)", failures))
print("JSON:" .. EncodeJson({ "DrawingImmediate mode", immediate }))
print("JSON:" .. EncodeJson({ "Drawing mode (objects in ZIndex order)", drawing }))

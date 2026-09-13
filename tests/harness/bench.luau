-- Benchmark: Dear ImGui's demo window with most sections open, plus the Metrics window and the Style Editor, on a tall
-- display so most of it is laid out and drawn. Deterministic (no input), so bundles and Luau optimization levels can be
-- compared back to back: LUAU_FLAGS=-O1 TAG=_o1 tests/harness/run.sh tests/harness/bench.luau
local ImGui = ImGuiBundle
local W, H = 1600, 2400
local FRAMES = 120

local function median(values)
	local sorted = table.clone(values)
	table.sort(sorted)
	return sorted[(#sorted + 1) // 2]
end

local initStart = os.clock()
ImGui.Init({
	Renderer = MockDrawingImmediate,
	AutoRender = false,
	Input = false,
	Font = 3,
	FontSize = 13,
	DisplaySize = Vector2.new(W, H),
	MeasureText = function(_, size, text)
		return (utf8.len(text) or #text) * HarnessAdvance(size)
	end,
})
local initMs = (os.clock() - initStart) * 1000

local sections = {
	"Help", "Configuration", "Window options", "Widgets", "Basic", "Tree Nodes", "Collapsing Headers", "Text", "Combo",
	"List Boxes", "Selectables", "Text Input", "Tabs", "Plotting", "Progress Bars", "Color/Picker Widgets",
	"Drag/Slider Flags", "Range Widgets", "Data Types", "Multi-component Widgets", "Vertical Sliders",
	"Layout & Scrolling", "Popups & Modal windows", "Tables & Columns", "Inputs & Focus",
}
local opened = false
ImGui.OnFrame(function()
	ImGui.SetNextWindowPos(Vector2.new(0, 0), ImGui.Cond.Always)
	ImGui.SetNextWindowSize(Vector2.new(820, H), ImGui.Cond.Always)
	if not opened then
		opened = true
		ImGui.Begin("Dear ImGui Demo")
		local storage = ImGui.GetStateStorage()
		for _, label in sections do
			storage:SetInt(ImGui.GetID(label), 1)
		end
		ImGui.End()
	end
	ImGui.ShowDemoWindow()

	ImGui.SetNextWindowPos(Vector2.new(830, 0), ImGui.Cond.Always)
	ImGui.SetNextWindowSize(Vector2.new(760, 1190), ImGui.Cond.Always)
	ImGui.ShowMetricsWindow()

	ImGui.SetNextWindowPos(Vector2.new(830, 1200), ImGui.Cond.Always)
	ImGui.SetNextWindowSize(Vector2.new(760, 1190), ImGui.Cond.Always)
	if ImGui.Begin("Style Editor") then
		ImGui.ShowStyleEditor()
	end
	ImGui.End()
end)

for _ = 1, 5 do
	table.clear(DrawCalls)
	ImGui.Step(1 / 60, W, H)
end

local total, newFrame, callbacks, render, draw = {}, {}, {}, {}, {}
for i = 1, FRAMES do
	table.clear(DrawCalls)
	ImGui.Step(1 / 60, W, H)
	local stats = ImGui.GetFrameStats()
	total[i], newFrame[i], callbacks[i] = stats.Total * 1000, stats.NewFrame * 1000, stats.Callbacks * 1000
	render[i], draw[i] = stats.Render * 1000, stats.Draw * 1000
end

local counts = {}
for _, call in DrawCalls do
	counts[call[1]] = (counts[call[1]] or 0) + 1
end
print(string.format(
	"BENCH init %.1f ms | frame median %.2f ms, fastest %.2f ms | NewFrame %.2f, callbacks %.2f, Render %.2f, draw %.2f | %d calls (rect=%d quad=%d tri=%d circle=%d text=%d)",
	initMs, median(total), math.min(table.unpack(total)), median(newFrame), median(callbacks), median(render), median(draw),
	#DrawCalls, counts.rect or 0, counts.quad or 0, counts.tri or 0, counts.circle or 0, counts.text or 0
))
print("SIZE:" .. W .. "x" .. H)
print("JSON:" .. EncodeJson({ "benchmark scene", DrawCalls }))

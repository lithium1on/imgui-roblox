-- Stress test: clicks through Dear ImGui's demo window (sections, tree nodes, scrolling) and opens every window
-- from the Examples and Tools menus, then runs frames with everything open. Reports assertion warnings, errors
-- and timings. Labels are located through the recorded DrawingImmediate text calls, like a user would see them.
local ImGui = ImGuiBundle
local W, H = 1600, 900

local warnings = 0
local realPrint = print
print = function(first, ...)
	if first == "[warn]" then
		warnings += 1
	end
	realPrint(first, ...)
end

ImGui.Init({
	Renderer = MockDrawingImmediate,
	AutoRender = false,
	Input = false,
	Font = 3,
	FontSize = 13,
	DisplaySize = Vector2.new(W, H),
	MeasureText = function(_, size, text)
		return (utf8.len(text) or #text) * math.floor(size * 0.55 + 0.5)
	end,
})

ImGui.OnFrame(function()
	ImGui.SetNextWindowPos(Vector2.new(10, 10), ImGui.Cond.FirstUseEver)
	ImGui.SetNextWindowSize(Vector2.new(760, 880), ImGui.Cond.FirstUseEver)
	ImGui.ShowDemoWindow()
end)

local frames = 0
local function step(count)
	for _ = 1, count or 1 do
		frames += 1
		table.clear(DrawCalls)
		ImGui.Step(1 / 60, W, H)
	end
end

local function findText(needle)
	local best = nil
	for _, call in DrawCalls do
		if call[1] == "text" then
			local text = call[10]
			local advance = math.floor(call[5] * 0.55 + 0.5)
			if text == needle then
				return call[2] + advance, call[3] + call[5] / 2
			elseif best == nil then
				local start = string.find(text, needle, 1, true)
				if start then
					best = { call[2] + (start - 1) * advance + advance, call[3] + call[5] / 2 }
				end
			end
		end
	end
	if best then
		return best[1], best[2]
	end
	return nil
end

local function click(x, y)
	ImGui.AddMousePosEvent(x, y)
	step()
	ImGui.AddMouseButtonEvent(0, true)
	step()
	ImGui.AddMouseButtonEvent(0, false)
	step()
end

local function clickText(needle)
	local x, y = findText(needle)
	if x == nil then
		return false
	end
	click(x, y)
	return true
end

local opened, missing = {}, {}
step(3)

-- Demo window sections, scrolling down when labels are out of view
local sections = {
	"Help", "Configuration", "Window options", "Widgets", "Basic", "Tooltips", "Tree Nodes", "Collapsing Headers",
	"Text", "Images", "Combo", "List Boxes", "Selectables", "Text Input", "Tabs", "Plotting", "Progress Bars",
	"Color/Picker Widgets", "Drag/Slider Flags", "Range Widgets", "Data Types", "Multi-component Widgets",
	"Vertical Sliders", "Drag and drop", "Disable Blocks", "Layout & Scrolling", "Popups & Modal windows",
	"Tables & Columns", "Inputs & Focus",
}
local pending = table.clone(sections)
local scrolls = 0
while #pending > 0 and scrolls < 60 do
	local progressed = false
	for i = #pending, 1, -1 do
		local label = pending[i]
		if clickText(label) then
			table.insert(opened, label)
			table.remove(pending, i)
			progressed = true
			ImGui.AddMousePosEvent(740, 400)
			step(2)
			break
		end
	end
	if not progressed then
		ImGui.AddMousePosEvent(380, 450)
		ImGui.AddMouseWheelEvent(0, -4)
		step(2)
		scrolls += 1
	end
end
for _, label in pending do
	table.insert(missing, label)
end
local afterSections = frames

-- Every window from the Examples and Tools menus
local menuItems = {
	Examples = {
		"Main menu bar", "Assets Browser", "Console", "Custom rendering", "Documents", "Log", "Property editor",
		"Simple layout", "Simple overlay", "Fullscreen window", "Long text display", "Manipulating window titles",
		"Auto-resizing window", "Constrained-resizing window",
	},
	Tools = { "Metrics/Debugger", "Debug Log", "ID Stack Tool", "Style Editor", "About Dear ImGui" },
}
for _, menu in { "Examples", "Tools" } do
	for _, item in menuItems[menu] do
		ImGui.AddMousePosEvent(W - 5, H - 5)
		step()
		if clickText(menu) and clickText(item) then
			table.insert(opened, menu .. " > " .. item)
		else
			table.insert(missing, menu .. " > " .. item)
			ImGui.AddKeyEvent("Escape", true)
			step()
			ImGui.AddKeyEvent("Escape", false)
			step()
		end
	end
end

-- Keyboard: type into the console example if it is open
if clickText("Input") then
	ImGui.AddInputCharactersUTF8("HELP")
	step()
	ImGui.AddKeyEvent("Enter", true)
	step()
	ImGui.AddKeyEvent("Enter", false)
	step()
end

ImGui.AddMousePosEvent(W - 5, H - 5)
local times = {}
for i = 1, 60 do
	table.clear(DrawCalls)
	local t0 = os.clock()
	ImGui.Step(1 / 60, W, H)
	times[i] = (os.clock() - t0) * 1000
	frames += 1
end
table.sort(times)

local counts = {}
for _, call in DrawCalls do
	counts[call[1]] = (counts[call[1]] or 0) + 1
end
print(string.format("STRESS: %d frames, opened %d items (%d before menus), missing %d: %s", frames, #opened, afterSections, #missing, table.concat(missing, ", ")))
print(string.format("STRESS: everything open -> median %.1f ms, max %.1f ms, %d calls (rect=%d quad=%d tri=%d text=%d)",
	times[30], times[60], #DrawCalls, counts.rect or 0, counts.quad or 0, counts.tri or 0, counts.text or 0))
if ImGui.GetFrameStats then
	local stats = ImGui.GetFrameStats()
	print(string.format("STRESS: last frame breakdown (ms): input %.2f, NewFrame %.2f, callbacks %.2f, Render %.2f, draw translation %.2f, total %.2f",
		stats.Input * 1000, stats.NewFrame * 1000, stats.Callbacks * 1000, stats.Render * 1000, stats.Draw * 1000, stats.Total * 1000))
end
print(string.format("RESULT %d warning(s)", warnings))
realPrint("SIZE:" .. W .. "x" .. H)
realPrint("JSON:" .. EncodeJson({ "stress: demo sections + example windows + tools", DrawCalls }))

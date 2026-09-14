-- Docking builds (docking.luau, docking_debug.luau): docking is on by default, windows dock into a dockspace and show
-- as tabs, docked windows draw their contents, and ImGui.Init({ Docking = false }) turns docking off: the flag is
-- cleared and DockSpace() makes no dock target.
local ImGui = ImGuiBundle
local W, H = 1000, 700
local failures = 0

local warnings = 0
local realPrint = print
print = function(first, ...)
	if first == "[warn]" then
		warnings += 1
	end
	realPrint(first, ...)
end

local function check(name, ok)
	realPrint((if ok then "PASS " else "FAIL ") .. name)
	if not ok then
		failures += 1
	end
end

check("ImGui.HasDocking is true", ImGui.HasDocking == true)

local function run(extra)
	local options = {
		Renderer = MockDrawingImmediate, AutoRender = false, Input = false, Font = 3, FontSize = 13,
		DisplaySize = Vector2.new(W, H),
		MeasureText = function(_, size, text)
			return (utf8.len(text) or #text) * HarnessAdvance(size)
		end,
	}
	for key, value in extra do
		options[key] = value
	end
	ImGui.Init(options)

	local state = { docked = {}, dockIds = {} }
	ImGui.OnFrame(function()
		state.dockspace = ImGui.DockSpaceOverViewport(0, nil, ImGui.DockNodeFlags.PassthruCentralNode)
		for _, name in { "Left panel", "Right panel" } do
			ImGui.SetNextWindowDockID(state.dockspace, ImGui.Cond.Always)
			if ImGui.Begin(name) then
				ImGui.Text("contents of %s", name)
			end
			state.docked[name] = ImGui.IsWindowDocked()
			state.dockIds[name] = ImGui.GetWindowDockID()
			ImGui.End()
		end
		ImGui.SetNextWindowPos(Vector2.new(600, 400), ImGui.Cond.Always)
		ImGui.SetNextWindowSize(Vector2.new(300, 200), ImGui.Cond.Always)
		if ImGui.Begin("Dock host") then
			state.innerDockspace = ImGui.DockSpace(ImGui.GetID("MyDockspace"), Vector2.new(0, 0))
		end
		ImGui.End()
	end)
	for _ = 1, 4 do
		table.clear(DrawCalls)
		ImGui.Step(1 / 60, W, H)
	end
	state.flags = ImGui.GetIO().ConfigFlags
	state.texts = {}
	for _, call in DrawCalls do
		if call[1] == "text" then
			state.texts[call[10]] = true
		end
	end
	ImGui.Shutdown()
	return state
end

local dockingFlag = ImGui.ConfigFlags.DockingEnable
local before = warnings
local on = run({})
check("docking is enabled by default", bit32.band(on.flags, dockingFlag) ~= 0)
check(string.format("both windows dock into the dockspace (%s, %s)", tostring(on.docked["Left panel"]), tostring(on.docked["Right panel"])),
	on.docked["Left panel"] == true and on.docked["Right panel"] == true)
check("docked windows share a dock node", on.dockIds["Left panel"] ~= 0 and on.dockIds["Left panel"] == on.dockIds["Right panel"])
check("both tabs are drawn", on.texts["Left panel"] == true and on.texts["Right panel"] == true)
check("the selected tab draws its contents", on.texts["contents of Left panel"] == true or on.texts["contents of Right panel"] == true)
check(string.format("DockSpace() inside a window makes a dock target (id %s)", tostring(on.innerDockspace)), on.innerDockspace ~= 0)
check(string.format("no warnings or assertions while docking (%d)", warnings - before), warnings == before)

local off = run({ Docking = false })
check("Docking = false clears the docking flag", bit32.band(off.flags, dockingFlag) == 0)
check(string.format("with docking off, DockSpace() makes no dock target (id %s)", tostring(off.innerDockspace)), off.innerDockspace == 0)

realPrint(string.format("RESULT %d failure(s)", failures))

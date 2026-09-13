-- Runs the examples from the wiki's Luau API guide so they keep working: every snippet must run without an error or a
-- Dear ImGui assertion.
local ImGui = ImGuiBundle
local W, H = 1280, 900
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

local big = ImGui.AddFont("UI", 22)
local state = {
	volume = 0.5, muted = false, name = "player", color = { 1, 0.4, 0.2, 1 }, count = 3, speed = 1, amount = 5,
	position = { 1, 2, 3 }, mode = 0, item = 0, choice = 0, selected = 0, notes = "", search = "", autosave = false,
}
local items = { { name = "a" }, { name = "b" } }
local players = { { Name = "p1", Health = 100, Team = "Red" }, { Name = "p2", Health = 80, Team = "Blue" } }
local fpsHistory = { 60, 58, 61, 59 }
local health, maxHealth = 50, 100
local value = 0.5
local open = true
local popupOpened = false
local function save() end
local function reset() end
local function toggle() end

local snippets = {
	{ "values that change", function()
		if ImGui.Begin("Settings") then
			local changed
			changed, state.volume = ImGui.SliderFloat("Volume", state.volume, 0, 1)
			local _
			_, state.muted = ImGui.Checkbox("Muted", state.muted)
			_, state.name = ImGui.InputText("Name", state.name)
			_, state.color = ImGui.ColorEdit4("Color", state.color)
			assert(type(changed) == "boolean" and type(state.volume) == "number" and type(state.name) == "string")
		end
		ImGui.End()
	end },
	{ "windows", function()
		ImGui.SetNextWindowPos(Vector2.new(100, 100), ImGui.Cond.FirstUseEver)
		ImGui.SetNextWindowSize(Vector2.new(400, 300), ImGui.Cond.FirstUseEver)
		local flags = bit32.bor(ImGui.WindowFlags.NoCollapse, ImGui.WindowFlags.MenuBar)
		local visible
		visible, open = ImGui.Begin("Tools", open, flags)
		if visible then
			ImGui.BeginChild("log", Vector2.new(0, 150), ImGui.ChildFlags.Borders)
			ImGui.Text("child")
			ImGui.EndChild()
		end
		ImGui.End()
		assert(open == true)
	end },
	{ "labels and IDs", function()
		ImGui.Begin("IDs")
		ImGui.Button("Delete##first")
		ImGui.Button("Delete##second")
		local _
		_, value = ImGui.SliderFloat("##hidden", value, 0, 1)
		for index, item in items do
			ImGui.PushID(index)
			if ImGui.Button("Remove") then
				error("not clicked")
			end
			ImGui.PopID()
			ImGui.PushID(item.name)
			ImGui.PopID()
		end
		ImGui.End()
	end },
	{ "common widgets", function()
		ImGui.Begin("Widgets")
		ImGui.Text("Health: %d / %d", health, maxHealth)
		ImGui.TextColored(Color3.new(1, 0.3, 0.3), "Low health")
		ImGui.TextWrapped("A long paragraph wraps at the window's edge.")
		ImGui.BulletText("Bullet")
		ImGui.SeparatorText("Section")
		ImGui.Button("Run")
		ImGui.SameLine()
		ImGui.SmallButton("?")
		local _
		_, state.count = ImGui.SliderInt("Count", state.count, 1, 10)
		_, state.speed = ImGui.DragFloat("Speed", state.speed, 0.1, 0, 100)
		_, state.amount = ImGui.InputInt("Amount", state.amount)
		_, state.position = ImGui.DragFloat3("Position", state.position)
		_, state.mode = ImGui.Combo("Mode", state.mode, { "Off", "Boxes", "Tracers" })
		_, state.item = ImGui.ListBox("Items", state.item, { "One", "Two", "Three" })
		if ImGui.RadioButton("First", state.choice == 0) then state.choice = 0 end
		ImGui.SameLine()
		if ImGui.RadioButton("Second", state.choice == 1) then state.choice = 1 end
		if ImGui.Selectable("Row", state.selected == 1) then state.selected = 1 end
		_, state.notes = ImGui.InputTextMultiline("Notes", state.notes, Vector2.new(-1, 80), 0, 4096)
		_, state.search = ImGui.InputTextWithHint("##search", "Search...", state.search)
		ImGui.ProgressBar(0.6, Vector2.new(-1, 0))
		ImGui.PlotLines("FPS", fpsHistory, 0, nil, 0, 120, Vector2.new(0, 60))
		ImGui.End()
		assert(type(state.position) == "table" and #state.position == 3 and type(state.notes) == "string")
	end },
	{ "trees, headers and tabs", function()
		ImGui.Begin("Trees")
		if ImGui.CollapsingHeader("Advanced") then
			ImGui.Text("inside")
		end
		if ImGui.TreeNode("Players") then
			ImGui.Text("...")
			ImGui.TreePop()
		end
		if ImGui.BeginTabBar("tabs") then
			if ImGui.BeginTabItem("Main") then
				ImGui.Text("First tab")
				ImGui.EndTabItem()
			end
			if ImGui.BeginTabItem("Settings") then
				ImGui.EndTabItem()
			end
			ImGui.EndTabBar()
		end
		ImGui.End()
	end },
	{ "menus, popups and tooltips", function()
		ImGui.Begin("Menus", nil, ImGui.WindowFlags.MenuBar)
		if ImGui.BeginMenuBar() then
			if ImGui.BeginMenu("File") then
				if ImGui.MenuItem("Save", "Ctrl+S") then save() end
				ImGui.EndMenu()
			end
			ImGui.EndMenuBar()
		end
		local clicked
		clicked, state.autosave = ImGui.MenuItemBoolPtr("Autosave", nil, state.autosave)
		assert(type(clicked) == "boolean" and type(state.autosave) == "boolean")
		if ImGui.Button("Reset...") or not popupOpened then
			popupOpened = true
			ImGui.OpenPopup("Confirm reset")
		end
		if ImGui.BeginPopupModal("Confirm reset", nil, ImGui.WindowFlags.AlwaysAutoResize) then
			ImGui.Text("Reset every setting?")
			if ImGui.Button("Yes") then
				reset()
				ImGui.CloseCurrentPopup()
			end
			ImGui.SameLine()
			if ImGui.Button("No") then
				ImGui.CloseCurrentPopup()
			end
			ImGui.EndPopup()
		end
		ImGui.Button("Hover me")
		if ImGui.IsItemHovered() then
			ImGui.SetTooltip("Explains the button")
		end
		ImGui.End()
	end },
	{ "tables", function()
		ImGui.Begin("Tables")
		if ImGui.BeginTable("players", 3, bit32.bor(ImGui.TableFlags.Borders, ImGui.TableFlags.RowBg)) then
			ImGui.TableSetupColumn("Name")
			ImGui.TableSetupColumn("Health")
			ImGui.TableSetupColumn("Team")
			ImGui.TableHeadersRow()
			for _, player in players do
				ImGui.TableNextRow()
				ImGui.TableNextColumn()
				ImGui.Text("%s", player.Name)
				ImGui.TableNextColumn()
				ImGui.Text("%d", player.Health)
				ImGui.TableNextColumn()
				ImGui.Text("%s", player.Team)
			end
			ImGui.EndTable()
		end
		ImGui.End()
	end },
	{ "draw lists", function()
		ImGui.Begin("Drawing")
		local drawList = ImGui.GetWindowDrawList()
		local origin = ImGui.GetCursorScreenPos()
		drawList:AddRectFilled(origin, origin + Vector2.new(120, 20), ImGui.COL32(80, 160, 255), 4)
		drawList:AddCircleFilled(origin + Vector2.new(140, 10), 8, ImGui.COL32(255, 80, 80))
		drawList:AddLine(origin, origin + Vector2.new(160, 20), ImGui.COL32(255, 255, 255), 2)
		drawList:AddText(origin + Vector2.new(0, 24), ImGui.COL32(255, 255, 0), "label")
		ImGui.Dummy(Vector2.new(0, 44))
		ImGui.End()
		local overlay = ImGui.GetForegroundDrawList()
		overlay:AddRect(Vector2.new(10, 10), Vector2.new(200, 100), ImGui.COL32(0, 255, 0), 0, 2)
	end },
	{ "style, colors and fonts", function()
		local style = ImGui.GetStyle()
		style.WindowRounding = 6
		style.FrameRounding = 4
		style.Colors[ImGui.Col.WindowBg] = { 0.08, 0.08, 0.10, 0.95 }
		style.ItemSpacing = Vector2.new(8, 6)
		ImGui.StyleColorsLight()
		ImGui.StyleColorsDark()
		ImGui.Begin("Style")
		ImGui.PushStyleColor(ImGui.Col.Button, ImGui.COL32(200, 60, 60))
		ImGui.Button("Danger")
		ImGui.PopStyleColor(1)
		ImGui.PushFont(big, 22)
		ImGui.Text("Title")
		ImGui.PopFont()
		ImGui.End()
		assert(type(ImGui.GetIO().Framerate) == "number" and type(ImGui.GetIO().DeltaTime) == "number")
		assert(style.ItemSpacing.X == 8 and style.ItemSpacing.Y == 6)
	end },
	{ "keyboard and mouse", function()
		if ImGui.IsKeyPressed(ImGui.Key.F) and not ImGui.WantTextInput() then
			toggle()
		end
		local mouse = ImGui.GetMousePos()
		assert(mouse ~= nil and type(ImGui.WantCaptureMouse()) == "boolean")
	end },
	{ "saving window layout", function()
		local ini = ImGui.SaveIniSettings()
		assert(type(ini) == "string")
		ImGui.LoadIniSettings(ini)
	end },
}

local errors = {}
ImGui.OnFrame(function()
	for _, snippet in snippets do
		local ok, err = pcall(snippet[2])
		if not ok and errors[snippet[1]] == nil then
			errors[snippet[1]] = tostring(err)
		end
	end
end)

for _ = 1, 4 do
	table.clear(DrawCalls)
	ImGui.Step(1 / 60, W, H)
end

for _, snippet in snippets do
	local err = errors[snippet[1]]
	check("API guide: " .. snippet[1] .. (if err then " (" .. err .. ")" else ""), err == nil)
end
check(string.format("no warnings or Dear ImGui assertions (%d)", warnings), warnings == 0)
realPrint(string.format("RESULT %d failure(s)", failures))

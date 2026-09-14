-- Docking (docking.luau or docking_debug.luau): the screen is a dockspace. Drag a panel by its title bar onto another
-- panel to add it as a tab, or onto the edge of the screen or of another panel to split it. PassthruCentralNode keeps
-- the game visible wherever nothing is docked. The main menu bar reopens closed panels.

local ImGui = loadstring(game:HttpGet("https://github.com/lithium1on/imgui-roblox/releases/latest/download/docking.luau"))()
ImGui.Init({ Font = "Monospace", FontSize = 14 })

local objects = { "Baseplate", "SpawnLocation", "Camera", "Lighting" }
local properties = {}
for _, name in objects do
	properties[name] = { transparency = 0, anchored = true, color = { 0.64, 0.64, 0.64 } }
end
local selected = objects[1]
local log = { "Drag a title bar to dock a panel." }

local panels = {
	{ name = "Scene", open = true, pos = Vector2.new(40, 60) },
	{ name = "Inspector", open = true, pos = Vector2.new(360, 60) },
	{ name = "Log", open = true, pos = Vector2.new(40, 360) },
}

local function drawPanel(name)
	if name == "Scene" then
		for _, object in objects do
			if ImGui.Selectable(object, selected == object) then
				selected = object
				table.insert(log, "Selected " .. object)
			end
		end
	elseif name == "Inspector" then
		local item = properties[selected]
		ImGui.Text("%s", selected)
		ImGui.Separator()
		local _
		_, item.transparency = ImGui.SliderFloat("Transparency", item.transparency, 0, 1)
		_, item.anchored = ImGui.Checkbox("Anchored", item.anchored)
		_, item.color = ImGui.ColorEdit3("Color", item.color)
	elseif name == "Log" then
		if ImGui.SmallButton("Clear") then
			table.clear(log)
		end
		for _, line in log do
			ImGui.TextUnformatted(line)
		end
	end
end

ImGui.OnFrame(function()
	if ImGui.BeginMainMenuBar() then
		if ImGui.BeginMenu("Panels") then
			for _, panel in panels do
				local _
				_, panel.open = ImGui.MenuItemBoolPtr(panel.name, nil, panel.open)
			end
			ImGui.EndMenu()
		end
		ImGui.EndMainMenuBar()
	end

	-- After the menu bar, so the dockspace starts below it
	ImGui.DockSpaceOverViewport(0, nil, ImGui.DockNodeFlags.PassthruCentralNode)

	for _, panel in panels do
		if panel.open then
			ImGui.SetNextWindowPos(panel.pos, ImGui.Cond.FirstUseEver)
			ImGui.SetNextWindowSize(Vector2.new(300, 260), ImGui.Cond.FirstUseEver)
			local visible
			visible, panel.open = ImGui.Begin(panel.name, panel.open)
			if visible then
				ImGui.TextDisabled(if ImGui.IsWindowDocked() then "docked" else "floating")
				drawPanel(panel.name)
			end
			ImGui.End()
		end
	end
end)

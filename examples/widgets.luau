-- A tour of the common widgets. Each widget returns whether it changed and then its new value: keep the value in `state`
-- and pass it back every frame.

local ImGui = loadstring(game:HttpGet("https://github.com/lithium1on/imgui-roblox/releases/latest/download/imgui.luau"))()
ImGui.Init({ Font = "Monospace", FontSize = 14 })

local state = {
	clicks = 0,
	enabled = true,
	mode = 0,
	volume = 0.5,
	count = 3,
	speed = 1,
	angle = 0,
	name = "",
	amount = 10,
	color = { 0.26, 0.59, 0.98, 1 },
	fruit = 0,
	selected = 1,
	progress = 0,
	histogram = { 0.2, 0.8, 0.4, 0.9, 0.6, 0.3, 0.7 },
	equalizer = { 0.5, 0.7, 0.4 },
}
local MODES = { "Off", "Low", "High" }
local FRUITS = { "Apple", "Banana", "Cherry" }
local ITEMS = { "First", "Second", "Third", "Fourth" }

ImGui.OnFrame(function()
	ImGui.SetNextWindowSize(Vector2.new(420, 560), ImGui.Cond.FirstUseEver)
	if not ImGui.Begin("Widgets") then
		ImGui.End() -- End is needed even when the window is collapsed
		return
	end
	local _

	ImGui.SeparatorText("Buttons")
	if ImGui.Button("Click me") then
		state.clicks += 1
	end
	if ImGui.IsItemHovered() then
		ImGui.SetTooltip("Counts your clicks")
	end
	ImGui.SameLine()
	ImGui.Text("clicked %d times", state.clicks)
	_, state.enabled = ImGui.Checkbox("Enable the sliders", state.enabled)
	for index, label in MODES do
		if index > 1 then
			ImGui.SameLine()
		end
		if ImGui.RadioButton(label, state.mode == index - 1) then
			state.mode = index - 1
		end
	end

	ImGui.SeparatorText("Sliders and inputs")
	ImGui.BeginDisabled(not state.enabled)
	_, state.volume = ImGui.SliderFloat("Volume", state.volume, 0, 1, "%.2f")
	_, state.count = ImGui.SliderInt("Count", state.count, 1, 10)
	_, state.speed = ImGui.DragFloat("Speed", state.speed, 0.05, 0, 10, "%.2f")
	_, state.angle = ImGui.SliderAngle("Angle", state.angle)
	ImGui.EndDisabled()
	_, state.name = ImGui.InputTextWithHint("Name", "type a name", state.name)
	_, state.amount = ImGui.InputInt("Amount", state.amount)
	_, state.color = ImGui.ColorEdit4("Color", state.color)

	ImGui.SeparatorText("Lists")
	_, state.fruit = ImGui.Combo("Fruit", state.fruit, FRUITS) -- the index starts at 0, like in C++
	if ImGui.BeginListBox("##items", Vector2.new(-1, 80)) then
		for index, item in ITEMS do
			if ImGui.Selectable(item, state.selected == index) then
				state.selected = index
			end
		end
		ImGui.EndListBox()
	end

	ImGui.SeparatorText("Layout")
	if ImGui.CollapsingHeader("Collapsing header") then
		ImGui.TextWrapped("Headers and tree nodes hide their contents until they are opened.")
		if ImGui.TreeNode("Tree node") then
			ImGui.BulletText("Nested item")
			ImGui.TreePop()
		end
	end
	if ImGui.BeginTabBar("tabs") then
		if ImGui.BeginTabItem("Progress") then
			state.progress = (state.progress + ImGui.GetIO().DeltaTime * 0.25) % 1
			ImGui.ProgressBar(state.progress, Vector2.new(-1, 0))
			ImGui.EndTabItem()
		end
		if ImGui.BeginTabItem("Plots") then
			ImGui.PlotHistogram("Histogram", state.histogram, 0, nil, 0, 1, Vector2.new(0, 60))
			for index = 1, #state.equalizer do
				if index > 1 then
					ImGui.SameLine()
				end
				ImGui.PushID(index) -- the three sliders share a label, so give each its own ID
				_, state.equalizer[index] = ImGui.VSliderFloat("##band", Vector2.new(24, 80), state.equalizer[index], 0, 1, "")
				ImGui.PopID()
			end
			ImGui.EndTabItem()
		end
		ImGui.EndTabBar()
	end
	ImGui.End()
end)

-- Shared test window used by the render mode tests: every kind of primitive the renderers handle.
-- Defines WidgetsUI(ImGui, state) and WidgetsState().
function WidgetsState()
	return {
		clicks = 0, checked = true, slider = 0.35, text = "hello", color = { 1, 0.5, 0.25, 1 }, combo = 1,
		drag = { 1, 2, 3 }, radio = 1, progress = 0.6, rects = {},
	}
end

function WidgetsUI(ImGui, state)
	ImGui.SetNextWindowPos(Vector2.new(40, 40), ImGui.Cond.Always)
	ImGui.SetNextWindowSize(Vector2.new(460, 640), ImGui.Cond.Always)
	if ImGui.Begin("Render modes") then
		ImGui.Text("Dear ImGui %s - clicks %d", ImGui.GetVersion(), state.clicks)
		if ImGui.Button("Click me") then
			state.clicks += 1
		end
		state.rects.button = { ImGui.GetItemRectMin(), ImGui.GetItemRectMax() }
		local _
		_, state.checked = ImGui.Checkbox("Checkbox", state.checked)
		for i = 0, 2 do
			if i > 0 then
				ImGui.SameLine()
			end
			if ImGui.RadioButton("Radio " .. i, state.radio == i) then
				state.radio = i
			end
		end
		_, state.slider = ImGui.SliderFloat("Slider", state.slider, 0, 1)
		_, state.text = ImGui.InputText("Input", state.text)
		_, state.color = ImGui.ColorEdit4("Color", state.color)
		_, state.combo = ImGui.Combo("Combo", state.combo, { "Apple", "Banana", "Cherry" })
		ImGui.ProgressBar(state.progress, Vector2.new(-1, 0))
		ImGui.PlotLines("Plot", { 0.1, 0.5, 0.3, 0.9, 0.2, 0.7 }, 0, nil, 0, 1, Vector2.new(0, 40))
		ImGui.BulletText("Bullet text")
		if ImGui.BeginTabBar("tabs") then
			if ImGui.BeginTabItem("First tab") then
				ImGui.TextColored(Color3.new(1, 0.4, 0.4), "Colored text in a tab")
				ImGui.EndTabItem()
			end
			if ImGui.BeginTabItem("Second") then
				ImGui.EndTabItem()
			end
			ImGui.EndTabBar()
		end
		if ImGui.TreeNode("Tree node") then
			ImGui.Text("Inside the tree node")
			ImGui.TreePop()
		end
		ImGui.SeparatorText("Draw list")
		local drawList = ImGui.GetWindowDrawList()
		local p = ImGui.GetCursorScreenPos()
		drawList:AddRectFilled(p, Vector2.new(p.X + 80, p.Y + 24), ImGui.COL32(255, 128, 0), 6)
		drawList:AddCircleFilled(Vector2.new(p.X + 110, p.Y + 12), 12, ImGui.COL32(0, 200, 255))
		drawList:AddTriangleFilled(Vector2.new(p.X + 135, p.Y + 24), Vector2.new(p.X + 150, p.Y), Vector2.new(p.X + 165, p.Y + 24), ImGui.COL32(120, 255, 120))
		drawList:AddLine(Vector2.new(p.X + 180, p.Y), Vector2.new(p.X + 240, p.Y + 24), ImGui.COL32(255, 255, 255), 3)
		drawList:AddRectFilledMultiColor(Vector2.new(p.X + 255, p.Y), Vector2.new(p.X + 335, p.Y + 24),
			ImGui.COL32(255, 0, 0), ImGui.COL32(0, 0, 255), ImGui.COL32(0, 0, 255), ImGui.COL32(255, 0, 0))
		drawList:AddNgonFilled(Vector2.new(p.X + 360, p.Y + 12), 12, ImGui.COL32(255, 220, 0), 5)
		ImGui.Dummy(Vector2.new(0, 28))
		ImGui.BeginChild("scroll", Vector2.new(0, 70), ImGui.ChildFlags.Borders)
		for i = 1, 12 do
			ImGui.Text("Scrolling line %d", i)
		end
		ImGui.EndChild()
	end
	ImGui.End()
end

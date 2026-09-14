-- Dear ImGui through Potassium: DrawingImmediate renders it, UserInputService drives it.
-- Other executors: use RenderMode = "Drawing" (Drawing library).
-- imgui_debug.luau has the demo window this script opens; imgui.luau is the smaller build without it.

local ImGui = loadstring(game:HttpGet("https://github.com/lithium1on/imgui-roblox/releases/latest/download/imgui_debug.luau"))()

ImGui.Init({
	RenderMode = "DrawingImmediate",
	Font = Drawing.Fonts.Monospace, -- font for every Dear ImGui glyph: UI, System, Plex or Monospace
	FontSize = 14,
	ZIndex = 1000, -- DrawingImmediate.GetPaint layer
	-- BlockGameInput = false, -- set to keep the game reacting to clicks/keys that land on ImGui windows
})

local UserInputService = game:GetService("UserInputService")
local visible = true
UserInputService.InputBegan:Connect(function(input)
	if input.KeyCode == Enum.KeyCode.RightShift then
		visible = not visible
	end
end)

local state = {
	showDemo = true,
	walkSpeed = 16,
	jumpPower = 50,
	name = "",
	espColor = { 1, 0.2, 0.3, 1 },
	mode = 0,
	flags = { fly = false, noclip = false },
}

ImGui.OnFrame(function()
	if not visible then
		return
	end

	if state.showDemo then
		state.showDemo = ImGui.ShowDemoWindow(true) -- returns false once the window is closed
	end

	ImGui.SetNextWindowPos(Vector2.new(40, 60), ImGui.Cond.FirstUseEver)
	ImGui.SetNextWindowSize(Vector2.new(380, 330), ImGui.Cond.FirstUseEver)
	if ImGui.Begin("Potassium x Dear ImGui") then
		ImGui.Text("Dear ImGui %s - %.0f FPS", ImGui.GetVersion(), ImGui.GetIO().Framerate)
		ImGui.TextDisabled("RightShift toggles the UI")
		ImGui.Separator()

		local _
		_, state.showDemo = ImGui.Checkbox("Show demo window", state.showDemo)
		_, state.walkSpeed = ImGui.SliderFloat("WalkSpeed", state.walkSpeed, 0, 200, "%.0f")
		_, state.jumpPower = ImGui.DragFloat("JumpPower", state.jumpPower, 0.5, 0, 500)
		_, state.name = ImGui.InputTextWithHint("Name", "type something", state.name)
		_, state.espColor = ImGui.ColorEdit4("Color", state.espColor)
		_, state.mode = ImGui.Combo("Mode", state.mode, { "Off", "Boxes", "Tracers" })

		if ImGui.CollapsingHeader("Toggles") then
			_, state.flags.fly = ImGui.Checkbox("Fly", state.flags.fly)
			ImGui.SameLine()
			_, state.flags.noclip = ImGui.Checkbox("Noclip", state.flags.noclip)
		end

		-- How glyph widths were measured, and whether they were checked against drawn text (see docs/init.md, Fonts)
		if ImGui.CollapsingHeader("Text metrics") then
			local info = ImGui.GetTextMetricsInfo()
			ImGui.Text("Measured with %s", info.Source)
			for _, font in info.Fonts do
				ImGui.BulletText("font %s, %.0f px: scale %.3f, %s", tostring(font.Font), font.Size, font.Scale,
					if font.Verified then "verified" else string.format("not verified (%d checks)", font.Attempts))
			end
		end

		if ImGui.Button("Apply") then
			local character = game:GetService("Players").LocalPlayer.Character
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")
			if humanoid then
				humanoid.WalkSpeed = state.walkSpeed
				humanoid.UseJumpPower = true
				humanoid.JumpPower = state.jumpPower
			end
		end
		if ImGui.IsItemHovered() then
			ImGui.SetTooltip("Applies WalkSpeed and JumpPower to your character")
		end

		-- Custom drawing through the window draw list
		local drawList = ImGui.GetWindowDrawList()
		local origin = ImGui.GetCursorScreenPos()
		local r, g, b = state.espColor[1] * 255, state.espColor[2] * 255, state.espColor[3] * 255
		drawList:AddRectFilled(origin, origin + Vector2.new(120, 16), ImGui.COL32(r, g, b, 255), 4)
		ImGui.Dummy(Vector2.new(0, 20))
	end
	ImGui.End()
end)

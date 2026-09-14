-- The smallest Dear ImGui script: one window with some text.
-- Works in any executor with DrawingImmediate (Potassium) or the Drawing library.

local ImGui = loadstring(game:HttpGet("https://github.com/lithium1on/imgui-roblox/releases/latest/download/imgui.luau"))()
ImGui.Init()

ImGui.OnFrame(function()
	ImGui.Begin("Hello, world!")
	ImGui.Text("This is Dear ImGui %s running in Roblox.", ImGui.GetVersion())
	ImGui.Text("Render mode: %s", ImGui.RenderMode)
	ImGui.End()
end)

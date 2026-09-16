-- Move, rotate and scale a part in the world with the ImGuizmo addon (imguizmo.luau):
-- - handles are drawn over the game at the part and follow the camera;
-- - a small window picks the operation, world or local axes, and snapping;
-- - scaling changes the part's Size; closing the window removes the part.

local GizmoAddon = loadstring(game:HttpGet("https://github.com/lithium1on/imgui-roblox/releases/latest/download/imguizmo.luau"))()
local ImGui = loadstring(game:HttpGet("https://github.com/lithium1on/imgui-roblox/releases/latest/download/imgui.luau"))()
ImGui.Init({ Font = "Monospace", FontSize = 13, Addons = GizmoAddon })
local ImGuizmo = ImGui.ImGuizmo

local part = Instance.new("Part")
part.Name = "GizmoPart"
part.Anchored = true
part.Size = Vector3.new(4, 4, 4)
part.CFrame = CFrame.new(0, 8, 0)
part.Parent = workspace

local OPERATIONS = {
	{ "Move", ImGuizmo.OPERATION.TRANSLATE },
	{ "Rotate", ImGuizmo.OPERATION.ROTATE },
	{ "Scale", ImGuizmo.OPERATION.SCALE },
}
local operation, mode = ImGuizmo.OPERATION.TRANSLATE, ImGuizmo.MODE.WORLD
local snap, open = false, true

ImGui.OnFrame(function()
	if not open then
		return
	end
	ImGui.SetNextWindowPos(Vector2.new(20, 220), ImGui.Cond.FirstUseEver)
	local visible
	visible, open = ImGui.Begin("Gizmo", open, ImGui.WindowFlags.AlwaysAutoResize)
	if visible then
		for index, entry in OPERATIONS do
			if index > 1 then
				ImGui.SameLine()
			end
			if ImGui.RadioButton(entry[1], operation == entry[2]) then
				operation = entry[2]
			end
		end
		if ImGui.RadioButton("World axes", mode == ImGuizmo.MODE.WORLD) then
			mode = ImGuizmo.MODE.WORLD
		end
		ImGui.SameLine()
		if ImGui.RadioButton("Local axes", mode == ImGuizmo.MODE.LOCAL) then
			mode = ImGuizmo.MODE.LOCAL
		end
		local _
		_, snap = ImGui.Checkbox("Snap (1 stud, 15 degrees)", snap)
		local x, y, z = part.CFrame:GetComponents()
		ImGui.TextDisabled("position %.1f, %.1f, %.1f", x, y, z)
		ImGui.TextDisabled("size %.1f, %.1f, %.1f", part.Size.X, part.Size.Y, part.Size.Z)
	end
	ImGui.End()

	if not open then
		part:Destroy()
		ImGui.Shutdown()
		return
	end

	local scaling = operation == ImGuizmo.OPERATION.SCALE
	local changed, cframe, scale = ImGuizmo.ManipulateCFrame(part.CFrame, operation, mode, {
		Size = if scaling then part.Size else nil,
		Snap = if snap then (if operation == ImGuizmo.OPERATION.ROTATE then 15 else 1) else nil,
	})
	if changed then
		part.CFrame = cframe
		if scaling then
			part.Size = scale
		end
	end
end)

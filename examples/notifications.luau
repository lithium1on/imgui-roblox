-- Toast notifications with the notify addon (notify.luau):
-- - one button per toast type: success, warning, error and info;
-- - a "deleted" toast with an Undo button that runs a function;
-- - RenderNotifications once per frame, after the windows.

local NotifyAddon = loadstring(game:HttpGet("https://github.com/lithium1on/imgui-roblox/releases/latest/download/notify.luau"))()
local ImGui = loadstring(game:HttpGet("https://github.com/lithium1on/imgui-roblox/releases/latest/download/imgui.luau"))()
ImGui.Init({ Font = "UI", FontSize = 14, Addons = NotifyAddon })

local items = { "Sword", "Shield", "Potion" }

ImGui.OnFrame(function()
	ImGui.SetNextWindowSize(Vector2.new(300, 260), ImGui.Cond.FirstUseEver)
	if ImGui.Begin("Notifications") then
		if ImGui.Button("Success") then
			ImGui.InsertNotification({ Type = "Success", Title = "Saved", Content = "Your settings were saved." })
		end
		ImGui.SameLine()
		if ImGui.Button("Warning") then
			ImGui.InsertNotification("Warning", "Ping is above 200 ms.")
		end
		ImGui.SameLine()
		if ImGui.Button("Error") then
			ImGui.InsertNotification({ Type = "Error", Title = "Failed", Content = "Could not reach the server.", DismissTime = 5000 })
		end
		ImGui.SameLine()
		if ImGui.Button("Info") then
			ImGui.InsertNotification("Info", "A new version is available.")
		end

		ImGui.SeparatorText("Inventory")
		for index, item in items do
			ImGui.PushID(index)
			if ImGui.SmallButton("Drop") then
				table.remove(items, index)
				ImGui.InsertNotification({
					Type = "Info",
					Content = item .. " dropped",
					ButtonLabel = "Undo",
					DismissTime = 6000,
					OnButtonPress = function()
						table.insert(items, math.min(index, #items + 1), item)
					end,
				})
			end
			ImGui.SameLine()
			ImGui.Text(item)
			ImGui.PopID()
		end
	end
	ImGui.End()

	ImGui.RenderNotifications()
end)

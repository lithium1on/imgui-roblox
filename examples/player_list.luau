-- A live list of the players in the server, in a table with a search box, row selection and a right-click menu on
-- each row. It shows the same names, display names and teams as the game's own player list.

local Players = game:GetService("Players")
local ImGui = loadstring(game:HttpGet("https://github.com/lithium1on/imgui-roblox/releases/latest/download/imgui.luau"))()
ImGui.Init({ Font = "Monospace", FontSize = 14 })

local search = ""
local selectedUserId = nil
local TABLE_FLAGS = bit32.bor(
	ImGui.TableFlags.Borders,
	ImGui.TableFlags.RowBg,
	ImGui.TableFlags.Resizable,
	ImGui.TableFlags.ScrollY,
	ImGui.TableFlags.SizingStretchProp
)

local function matches(player, needle)
	return needle == ""
		or string.find(string.lower(player.Name), needle, 1, true) ~= nil
		or string.find(string.lower(player.DisplayName), needle, 1, true) ~= nil
end

ImGui.OnFrame(function()
	ImGui.SetNextWindowSize(Vector2.new(520, 360), ImGui.Cond.FirstUseEver)
	if ImGui.Begin("Players") then
		local players = Players:GetPlayers()
		local _
		_, search = ImGui.InputTextWithHint("##search", "Search by name", search)
		ImGui.SameLine()
		ImGui.Text("%d in this server", #players)

		local height = ImGui.GetContentRegionAvail().Y
		if ImGui.BeginTable("players", 3, TABLE_FLAGS, Vector2.new(0, height)) then
			ImGui.TableSetupScrollFreeze(0, 1) -- keep the header row visible while scrolling
			ImGui.TableSetupColumn("Display name")
			ImGui.TableSetupColumn("Username")
			ImGui.TableSetupColumn("Team")
			ImGui.TableHeadersRow()

			local needle = string.lower(search)
			for _, player in players do
				if not matches(player, needle) then
					continue
				end
				ImGui.PushID(player.UserId) -- two players can share a display name
				ImGui.TableNextRow()
				ImGui.TableNextColumn()
				if ImGui.Selectable(player.DisplayName, selectedUserId == player.UserId, ImGui.SelectableFlags.SpanAllColumns) then
					selectedUserId = player.UserId
				end
				if ImGui.BeginPopupContextItem() then
					ImGui.TextDisabled("%s (@%s)", player.DisplayName, player.Name)
					if ImGui.MenuItem("Copy username") then
						ImGui.SetClipboardText(player.Name)
					end
					if ImGui.MenuItem("Copy user ID") then
						ImGui.SetClipboardText(tostring(player.UserId))
					end
					ImGui.EndPopup()
				end
				ImGui.TableNextColumn()
				ImGui.Text("@%s", player.Name)
				ImGui.TableNextColumn()
				ImGui.Text("%s", if player.Team then player.Team.Name else "-")
				ImGui.PopID()
			end
			ImGui.EndTable()
		end
	end
	ImGui.End()
end)

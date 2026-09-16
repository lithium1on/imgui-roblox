-- A help window written in Markdown with the markdown addon (markdown.luau):
-- - headings, emphasis, bullet lists, links and rules from one string;
-- - clicking a link copies it to the clipboard (Roblox can't open a browser);
-- - a larger font for the top heading, the other headings scale the current font.

local MarkdownAddon = loadstring(game:HttpGet("https://github.com/lithium1on/imgui-roblox/releases/latest/download/markdown.luau"))()
local ImGui = loadstring(game:HttpGet("https://github.com/lithium1on/imgui-roblox/releases/latest/download/imgui.luau"))()
ImGui.Init({ Font = "UI", FontSize = 14, Addons = MarkdownAddon })

local titleFont = ImGui.AddFont("UI", 24)
local HELP = [[
# My Script
Welcome! This window explains the *controls* and where to get help.
## Keys
  * **RightShift** shows and hides every window
  * **Ctrl+Z** undoes the last change
## Links
Read the [documentation](https://github.com/lithium1on/imgui-roblox/wiki) or [report a bug](https://github.com/lithium1on/imgui-roblox/issues).
___
Version 1.0
]]

local copied = nil
ImGui.OnFrame(function()
	ImGui.SetNextWindowSize(Vector2.new(460, 340), ImGui.Cond.FirstUseEver)
	if ImGui.Begin("Help") then
		local link = ImGui.Markdown(HELP, { H1 = { Font = titleFont, Size = 24 } })
		if link ~= nil then
			copied = link
			if setclipboard then
				setclipboard(link)
			end
		end
		if copied ~= nil then
			ImGui.Separator()
			ImGui.TextDisabled("Copied: %s", copied)
		end
	end
	ImGui.End()
end)

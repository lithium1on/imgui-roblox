-- A Luau script editor with syntax highlighting, undo/redo, find/replace (Ctrl+F) and a Run button:
-- - ImGui.TextEditor is ImGuiColorTextEdit, in imgui_editor.luau, docking_editor.luau and the _debug builds;
-- - it lays text out on a grid of equal-width cells, so the example uses the Monospace font;
-- - Run compiles the text with loadstring and shows what the chunk returned, or the error.

local ImGui = loadstring(game:HttpGet("https://github.com/lithium1on/imgui-roblox/releases/latest/download/imgui_editor.luau"))()
ImGui.Init({ Font = "Monospace", FontSize = 14 })

local editor = ImGui.TextEditor.new()
editor:SetLanguage("Luau")
editor:SetShowWhitespacesEnabled(false) -- no dots for spaces and arrows for tabs
editor:SetText(table.concat({
	"-- Press Run to run this script",
	"local Players = game:GetService(\"Players\")",
	"local names = {}",
	"for _, player in Players:GetPlayers() do",
	"\ttable.insert(names, player.Name)",
	"end",
	"return `{#names} player(s): {table.concat(names, \", \")}`",
}, "\n"))

local languages = ImGui.TextEditor.Languages
local languageIndex = table.find(languages, "Luau") - 1
local lightPalette = false
local output = "Output appears here"

local function run()
	local chunk, compileError = loadstring(editor:GetText(), "=editor")
	if not chunk then
		output = "Compile error: " .. tostring(compileError)
		return
	end
	local results = table.pack(pcall(chunk))
	if not results[1] then
		output = "Error: " .. tostring(results[2])
		return
	end
	local parts = {}
	for i = 2, results.n do
		table.insert(parts, tostring(results[i]))
	end
	output = if #parts > 0 then "Returned " .. table.concat(parts, ", ") else "Done, nothing returned"
end

ImGui.OnFrame(function()
	ImGui.SetNextWindowSize(Vector2.new(640, 460), ImGui.Cond.FirstUseEver)
	if ImGui.Begin("Script editor") then
		if ImGui.Button("Run") then
			run()
		end
		ImGui.SameLine()
		ImGui.BeginDisabled(not editor:CanUndo())
		if ImGui.Button("Undo") then
			editor:Undo()
		end
		ImGui.EndDisabled()
		ImGui.SameLine()
		ImGui.BeginDisabled(not editor:CanRedo())
		if ImGui.Button("Redo") then
			editor:Redo()
		end
		ImGui.EndDisabled()
		ImGui.SameLine()
		if ImGui.Button("Find") then
			editor:OpenFindReplaceWindow()
		end
		ImGui.SameLine()
		ImGui.SetNextItemWidth(120)
		local changed
		changed, languageIndex = ImGui.Combo("##language", languageIndex, languages)
		if changed then
			editor:SetLanguage(languages[languageIndex + 1])
		end
		ImGui.SameLine()
		changed, lightPalette = ImGui.Checkbox("Light", lightPalette)
		if changed then
			editor:SetPalette(if lightPalette then "Light" else "Dark")
		end

		-- The editor fills the window except two lines for the status and the output
		editor:Render("##source", Vector2.new(0, -ImGui.GetFrameHeightWithSpacing() * 2))

		local line, column = editor:GetMainCursorPosition()
		ImGui.TextDisabled("Ln %d, Col %d  |  %d lines  |  %s", line + 1, column + 1, editor:GetLineCount(), editor:GetLanguageName())
		ImGui.TextWrapped("%s", output)
	end
	ImGui.End()
end)

-- ImGui.TextEditor (ImGuiColorTextEdit): text in and out (UTF-8), languages, options, palette colors, cursors and
-- selections, find/replace, undo/redo, markers and squiggles; rendering in a window draws the code and typed characters
-- reach a focused editor; Destroy and Shutdown free editors.
local ImGui = ImGuiBundle
local W, H = 800, 600
local failures = 0

local function check(name, ok)
	print((if ok then "PASS " else "FAIL ") .. name)
	if not ok then
		failures += 1
	end
end

local options = {
	RenderMode = "DrawingImmediate", DrawingImmediate = MockDrawingImmediate, AutoRender = false, Input = false,
	DisplaySize = Vector2.new(W, H), Font = "Monospace",
	MeasureText = function(_, size, text)
		return (utf8.len(text) or #text) * HarnessAdvance(size)
	end,
}
ImGui.Init(options)

check("Languages lists Luau", table.find(ImGui.TextEditor.Languages, "Luau") ~= nil and #ImGui.TextEditor.Colors == 22)

local editor = ImGui.TextEditor.new()
local source = "local x = 1\nprint(`value {x}`)\n-- comment\nreturn x"
editor:SetText(source)
check("GetText returns the text", editor:GetText() == source)
check("GetLineCount and GetLineText", editor:GetLineCount() == 4 and editor:GetLineText(1) == "print(`value {x}`)")
check("GetSectionText", editor:GetSectionText(0, 0, 0, 5) == "local")
local unicode = "héllo ✓ 日本"
editor:SetText(unicode)
check("UTF-8 text round-trips", editor:GetText() == unicode)
editor:SetText(source)

editor:SetLanguage("Luau")
check("SetLanguage", editor:GetLanguageName() == "Luau" and editor:HasLanguage())
check("an unknown language is an error", not pcall(editor.SetLanguage, editor, "Cobol"))
editor:SetLanguage(nil)
check("SetLanguage(nil) is plain text", not editor:HasLanguage() and editor:GetLanguageName() == "None")
editor:SetLanguage("Luau")

editor:SetTabSize(2)
editor:SetShowLineNumbersEnabled(false)
editor:SetLineSpacing(1.5)
check("number and flag options", editor:GetTabSize() == 2 and not editor:IsShowLineNumbersEnabled() and editor:GetLineSpacing() == 1.5)
editor:SetShowLineNumbersEnabled(true)
editor:SetMiddleMousePanMode()
local pan = editor:IsMiddleMousePanMode()
editor:SetMiddleMouseScrollMode()
check("middle mouse modes", pan and not editor:IsMiddleMousePanMode())

editor:SetPalette("Light")
local red = ImGui.COL32(255, 0, 0, 255)
editor:SetPaletteColor("Keyword", red)
editor:SetPaletteColor("Comment", Color3.new(0, 1, 0))
check("palette colors", editor:GetPaletteColor("Keyword") == red and editor:GetPaletteColor("Comment") == ImGui.COL32(0, 255, 0, 255))
check("an unknown palette color is an error", not pcall(editor.SetPaletteColor, editor, "Nope", red))
editor:SetPalette("Dark")

editor:SetCursor(1, 6)
local line, index = editor:GetMainCursorPosition()
check(string.format("SetCursor (%d, %d)", line, index), line == 1 and index == 6)
editor:SelectRegion(0, 6, 0, 7)
local sl, si, el, ei = editor:GetMainCursorSelection()
check(string.format("SelectRegion (%d, %d)-(%d, %d)", sl, si, el, ei), sl == 0 and si == 6 and el == 0 and ei == 7
	and editor:MainCursorHasSelection() and editor:GetCursorText(0) == "x")

editor:SelectAllOccurrencesOf("x", true, true)
check(string.format("SelectAllOccurrencesOf makes a cursor per match (%d)", editor:GetNumberOfCursors()), editor:GetNumberOfCursors() == 3)
editor:ReplaceTextInAllCursors("count")
local replaced = editor:GetText()
check("ReplaceTextInAllCursors", string.find(replaced, "local count = 1", 1, true) ~= nil and string.find(replaced, "return count", 1, true) ~= nil)
check("CanUndo after an edit", editor:CanUndo())
editor:Undo()
check("Undo restores the text", editor:GetText() == source and editor:CanRedo())
editor:Redo()
check("Redo applies it again", editor:GetText() == replaced)
editor:SetText(source)

editor:ReplaceSectionText(3, 0, 3, 6, "yield")
check("ReplaceSectionText", editor:GetLineText(3) == "yield x")
editor:SelectRegion(0, 0, 0, 5)
editor:SelectionToUpperCase()
check("SelectionToUpperCase", editor:GetLineText(0) == "LOCAL x = 1")
editor:SetText(source)

editor:AddMarker(0, ImGui.COL32(255, 0, 0, 255), ImGui.COL32(80, 0, 0, 255), "line tooltip", "text tooltip")
editor:AddSquiggle(0, 0, 0, 5, 0, red, "squiggle tooltip")
check("markers and squiggles", editor:HasMarkers() and editor:HasSquiggles())
editor:ClearMarkers()
editor:ClearSquiggles()
check("ClearMarkers and ClearSquiggles", not editor:HasMarkers() and not editor:HasSquiggles())
editor:IsTextChanged() -- forget the changes so far

local focused = false
local frameError = nil
ImGui.OnFrame(function()
	ImGui.SetNextWindowPos(Vector2.new(20, 20), ImGui.Cond.Always)
	ImGui.SetNextWindowSize(Vector2.new(500, 300), ImGui.Cond.Always)
	ImGui.Begin("Editor")
	local ok, result = pcall(editor.Render, editor, "##code")
	if ok then
		focused = result
	else
		frameError = result
	end
	ImGui.End()
end)

local function frame()
	table.clear(DrawCalls)
	ImGui.Step(1 / 60, W, H)
	local texts = {}
	for _, call in DrawCalls do
		if call[1] == "text" then
			table.insert(texts, call[10])
		end
	end
	return table.concat(texts)
end

local drawn = frame()
check("Render runs inside a window" .. (if frameError then ": " .. tostring(frameError) else ""), frameError == nil)
check("Render draws the code", string.find(drawn, "print", 1, true) ~= nil and string.find(drawn, "comment", 1, true) ~= nil)
check(string.format("glyph size comes from the font (%.1f x %.1f)", editor:GetGlyphWidth(), editor:GetLineHeight()),
	editor:GetGlyphWidth() > 0 and editor:GetLineHeight() > 0)

editor:SetFocus()
frame()
editor:SetCursor(0, 0)
frame()
ImGui.AddInputCharacter(string.byte("Z"))
frame()
check("typed characters reach the focused editor (" .. editor:GetLineText(0) .. ")", focused and editor:GetLineText(0) == "Zlocal x = 1")
frame()
check("IsTextChanged after typing, then false", editor:IsTextChanged() and not editor:IsTextChanged())

local start = os.clock()
local big = table.create(2000)
for i = 1, 2000 do
	big[i] = string.format("local value%d = %d -- line %d", i, i * 3, i)
end
editor:SetText(table.concat(big, "\n"))
editor:ScrollToLine(1000, "Top")
frame()
frame()
print(string.format("2000 lines: set and two frames in %.2f s, first visible row %d", os.clock() - start, editor:GetFirstVisibleRow()))
check("ScrollToLine scrolls a long document", editor:GetFirstVisibleRow() >= 990 and editor:GetFirstVisibleRow() <= 1000)

local second = ImGui.TextEditor.new()
second:SetText("temporary")
second:Destroy()
check("a destroyed editor refuses calls", not second:IsValid() and not pcall(second.GetText, second))

ImGui.Shutdown()
check("Shutdown frees every editor", not editor:IsValid() and not pcall(editor.GetText, editor))
ImGui.Init(options)
check("editors stay invalid after Init", not editor:IsValid())
local third = ImGui.TextEditor.new()
third:SetText("again")
check("new editors work after Init again", third:GetText() == "again")
ImGui.Shutdown()

print(string.format("RESULT %d failure(s)", failures))

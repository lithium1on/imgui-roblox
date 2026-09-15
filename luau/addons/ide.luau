-- IDE addon: ImGuiColorTextEdit (github.com/goossens/ImGuiColorTextEdit, MIT) as ImGui.TextEditor.
--
--     local IDE = loadstring(game:HttpGet(".../ide.luau"))()
--     local ImGui = loadstring(game:HttpGet(".../imgui.luau"))()
--     ImGui.Init({ Addons = IDE })
--
-- ide.luau calls this chunk with its WebAssembly side modules, one per Dear ImGui branch. The runtime links the one for
-- the bundle's branch into the Dear ImGui context and calls IDE.Install(host). ImGui.TextEditor.new() then creates a
-- code editor (syntax highlighting, undo/redo, find/replace, multiple cursors) and editor:Render(title, size) draws it
-- in the current window. Methods keep TextEditor's names, with zero-based lines and indexes. An editor belongs to the
-- script that created it: editor:Destroy() or the script's ImGui.Shutdown() frees it, and when the script moves to
-- another bundle's context, the editor's text, cursor and settings move along.

local Modules = ...

local sformat, ssub, tconcat, tclear, tfind = string.format, string.sub, table.concat, table.clear, table.find
local floor = math.floor
local bor, lshift = bit32.bor, bit32.lshift
local readstring, readi32, writestring, writeu8 = buffer.readstring, buffer.readi32, buffer.writestring, buffer.writeu8

local EditorLanguages = { "C", "Cpp", "Cs", "AngelScript", "Lua", "Luau", "Python", "Glsl", "Hlsl", "Json", "Markdown", "Sql" }
local EditorColors = {
	"Text", "Keyword", "Declaration", "Number", "String", "Punctuation", "Preprocessor", "Identifier", "KnownIdentifier",
	"Comment", "Background", "Cursor", "Selection", "Whitespace", "MatchingBracketBackground", "MatchingBracketActive",
	"MatchingBracketLevel1", "MatchingBracketLevel2", "MatchingBracketLevel3", "MatchingBracketError", "LineNumber",
	"CurrentLineNumber",
}
-- { setter, getter, value is a flag }, in rbx_te_set_option order
local EditorOptions = {
	{ "SetTabSize", "GetTabSize" }, { "SetInsertSpacesOnTabs", "IsInsertSpacesOnTabs", true },
	{ "SetLineSpacing", "GetLineSpacing" }, { "SetWordWrapEnabled", "IsWordWrapEnabled", true },
	{ "SetReadOnlyEnabled", "IsReadOnlyEnabled", true }, { "SetCaretsVisible", "IsCaretsVisible", true },
	{ "SetAutoIndentEnabled", "IsAutoIndentEnabled", true }, { "SetShowWhitespacesEnabled", "IsShowWhitespacesEnabled", true },
	{ "SetShowSpacesEnabled", "IsShowSpacesEnabled", true }, { "SetShowTabsEnabled", "IsShowTabsEnabled", true },
	{ "SetShowLineNumbersEnabled", "IsShowLineNumbersEnabled", true }, { "SetShowMiniMapEnabled", "IsShowMiniMapEnabled", true },
	{ "SetMiniMapColumns", "GetMiniMapColumns" }, { "SetShowScrollbarMiniMapEnabled", "IsShowScrollbarMiniMapEnabled", true },
	{ "SetShowPanScrollIndicatorEnabled", "IsShowPanScrollIndicatorEnabled", true },
	{ "SetShowMatchingBrackets", "IsShowingMatchingBrackets", true }, { "SetCompletePairedGlyphs", "IsCompletingPairedGlyphs", true },
	{ "SetLineFoldingEnabled", "IsLineFoldingEnabled", true }, { "SetOverwriteEnabled", "IsOverwriteEnabled", true },
	{ false, "IsMiddleMousePanMode", true }, { "SetLineNumberLeftMargin", "GetLineNumberLeftMargin" },
	{ "SetDecorationLeftMargin", "GetDecorationLeftMargin" }, { "SetTextLeftMargin", "GetTextLeftMargin" },
}
-- In rbx_te_command order
local EditorCommands = {
	"Cut", "Copy", "Paste", "Undo", "Redo", "SelectAll", "ClearCursors", "SetFocus", "ClearText", "OpenFindReplaceWindow",
	"CloseFindReplaceWindow", "FindNext", "FindAll", "ClearMarkers", "ClearSquiggles", "GrowSelections", "ShrinkSelections",
	"IndentLines", "DeindentLines", "MoveUpLines", "MoveDownLines", "ToggleComments", "SelectionToLowerCase",
	"SelectionToUpperCase", "StripTrailingWhitespaces", "TabsToSpaces", "SpacesToTabs", "UnfoldAll",
}
-- { name, result is a flag }, in rbx_te_query order
local EditorQueries = {
	{ "CanUndo", true }, { "CanRedo", true }, { "GetUndoIndex" }, { "IsEmpty", true }, { "GetLineCount" },
	{ "GetNumberOfCursors" }, { "AnyCursorHasSelection", true }, { "AllCursorsHaveSelection", true },
	{ "MainCursorHasSelection", true }, { "CurrentCursorHasSelection", true }, { "HasMarkers", true },
	{ "HasSquiggles", true }, { "HasFindString", true }, { "GetFirstVisibleRow" }, { "GetLastVisibleRow" },
	{ "GetFirstVisibleColumn" }, { "GetLastVisibleColumn" }, { "GetLineHeight" }, { "GetGlyphWidth" }, { "HasLanguage", true },
}
local RequiredExports = {
	"new", "free", "render", "take_changed", "buffer_size", "set_text", "get_text", "get_line_text", "get_cursor_text",
	"get_language_name", "get_section_text", "replace_section_text", "set_language", "set_palette", "set_palette_color",
	"get_palette_color", "set_option", "get_option", "command", "query", "line", "region", "cursor", "mouse",
	"get_word_at_mouse_pos", "find", "string", "add_marker", "add_squiggle",
}
local EditorColorIndex = {}
for index, name in EditorColors do
	EditorColorIndex[name] = index - 1
end
local ScrollAlignments = { Top = 0, Middle = 1, Bottom = 2 }

local IDE = {
	Name = "IDE",
	Protocol = 1, -- the runtime's addon interface
	ImGuiVersion = "1.92.9b",
	Modules = Modules,
	Languages = table.clone(EditorLanguages),
	Colors = table.clone(EditorColors),
}

-- An ImU32 (ImGui.COL32), or a Color3 with an optional alpha
local function ColorU32(color, alpha)
	if color == nil then
		return 0
	elseif type(color) == "number" then
		return color % 4294967296
	end
	local a = if alpha == nil then 1 else alpha
	return bor(floor(color.R * 255 + 0.5), lshift(floor(color.G * 255 + 0.5), 8), lshift(floor(color.B * 255 + 0.5), 16),
		lshift(floor(a * 255 + 0.5), 24))
end

local function PaletteIndex(color)
	local index = if type(color) == "number" then color else EditorColorIndex[color]
	if index == nil or index < 0 or index >= #EditorColors then
		error(sformat('[ImGui] unknown TextEditor palette color "%s" (see ImGui.TextEditor.Colors)', tostring(color)), 3)
	end
	return index
end

-- host: { Exports (the linked module's), Mem(), Malloc(size), Free(ptr), Alive() } from the runtime
function IDE.Install(host)
	local Mem, Malloc, Free = host.Mem, host.Malloc, host.Free
	local E = {} -- exports without their "rbx_te_" prefix
	for _, name in RequiredExports do
		E[name] = host.Exports["rbx_te_" .. name] or error("[ImGui] the IDE module is missing rbx_te_" .. name)
	end
	local token = {} -- marks the editors of this installation
	local EditorsByScript = {} -- script record -> { [editor] = true }

	local EditorMethods = {}
	local EditorMeta = {
		__index = EditorMethods,
		__tostring = function(self)
			return sformat("TextEditor: 0x%08x", self.__ptr)
		end,
	}

	local function Call(name, ...)
		local closure = E[name]
		return closure[1](closure, ...)
	end

	local function Alive(editor)
		return editor.__token == token and host.Alive()
	end

	local function Ptr(editor)
		if not Alive(editor) then
			error("[ImGui] this TextEditor was destroyed, by editor:Destroy() or by ImGui.Shutdown()", 3)
		end
		return editor.__ptr
	end

	-- Calls fn(pointer, size) with `text` copied into linear memory, NUL-terminated
	local function WithText(text, fn)
		text = if text == nil then "" else tostring(text)
		local size = #text
		local ptr = Malloc(size + 1)
		local mem = Mem()
		writestring(mem, ptr, text)
		writeu8(mem, ptr + size, 0)
		local result = fn(ptr, size)
		Free(ptr)
		return result
	end

	local function String(ptr, resultPtr)
		return readstring(Mem(), resultPtr, (Call("buffer_size", ptr)))
	end

	local function Positions(resultPtr)
		local mem = Mem()
		return readi32(mem, resultPtr), readi32(mem, resultPtr + 4), readi32(mem, resultPtr + 8), readi32(mem, resultPtr + 12)
	end

	local function Own(script, editor)
		local owned = EditorsByScript[script]
		if owned == nil then
			owned = {}
			EditorsByScript[script] = owned
		end
		owned[editor] = true
	end

	local function CreateEditor(script)
		if not host.Alive() then
			error("[ImGui] call ImGui.Init() first", 3)
		end
		local editor = setmetatable({
			__ptr = (Call("new")), __token = token, __script = script, __settings = { Options = {}, Colors = {}, Labels = {} },
		}, EditorMeta)
		Own(script, editor)
		return editor
	end

	local function DestroyEditor(editor)
		if Alive(editor) then
			Call("free", editor.__ptr)
		end
		editor.__token = nil
		local owned = EditorsByScript[editor.__script]
		if owned ~= nil then
			owned[editor] = nil
		end
	end

	local function SnapshotEditor(editor)
		if not Alive(editor) then
			return false
		end
		local ptr = editor.__ptr
		local line, index = Positions((Call("cursor", ptr, 1, 0)))
		return { Text = String(ptr, (Call("get_text", ptr))), Line = line, Index = index }
	end

	-- Recreates an editor of another context in this one, with its settings, text and cursor
	local function RestoreEditor(script, editor, snapshot)
		if not snapshot then
			editor.__token = nil
			return
		end
		local ptr = (Call("new"))
		editor.__ptr, editor.__token = ptr, token
		setmetatable(editor, EditorMeta)
		Own(script, editor)
		local settings = editor.__settings
		if settings.Language ~= nil then
			Call("set_language", ptr, settings.Language)
		end
		if settings.Palette ~= nil then
			Call("set_palette", ptr, if settings.Palette == "Light" then 1 else 0)
		end
		for index, color in settings.Colors do
			Call("set_palette_color", ptr, index, color)
		end
		for id, value in settings.Options do
			Call("set_option", ptr, id, value)
		end
		for op, text in settings.Labels do
			WithText(text, function(textPtr, size)
				Call("string", ptr, op, textPtr, size)
			end)
		end
		WithText(snapshot.Text, function(textPtr, size)
			Call("set_text", ptr, textPtr, size)
		end)
		Call("region", ptr, 0, snapshot.Line, snapshot.Index, 0, 0)
	end

	function EditorMethods.Destroy(self)
		DestroyEditor(self)
	end

	function EditorMethods.IsValid(self)
		return Alive(self)
	end

	-- size: Vector2, zero or missing components fill the window. Returns whether the editor has keyboard focus.
	function EditorMethods.Render(self, title, size, childFlags, windowFlags)
		local ptr = Ptr(self)
		local width, height = 0, 0
		if size ~= nil then
			width, height = size.X, size.Y
		end
		return WithText(title, function(titlePtr)
			return Call("render", ptr, titlePtr, width, height, childFlags or 0, windowFlags or -1) ~= 0
		end)
	end

	-- True once after the text changed (typing, undo, SetText...); the change is seen by Render
	function EditorMethods.IsTextChanged(self)
		return Call("take_changed", Ptr(self)) ~= 0
	end

	function EditorMethods.SetText(self, text)
		local ptr = Ptr(self)
		WithText(text, function(textPtr, size)
			Call("set_text", ptr, textPtr, size)
		end)
	end

	function EditorMethods.GetText(self)
		local ptr = Ptr(self)
		return String(ptr, (Call("get_text", ptr)))
	end

	function EditorMethods.GetLineText(self, line)
		local ptr = Ptr(self)
		return String(ptr, (Call("get_line_text", ptr, line)))
	end

	function EditorMethods.GetCursorText(self, cursor)
		local ptr = Ptr(self)
		return String(ptr, (Call("get_cursor_text", ptr, cursor or 0)))
	end

	function EditorMethods.GetSectionText(self, startLine, startIndex, endLine, endIndex)
		local ptr = Ptr(self)
		return String(ptr, (Call("get_section_text", ptr, startLine, startIndex, endLine, endIndex)))
	end

	function EditorMethods.ReplaceSectionText(self, startLine, startIndex, endLine, endIndex, text)
		local ptr = Ptr(self)
		WithText(text, function(textPtr, size)
			Call("replace_section_text", ptr, startLine, startIndex, endLine, endIndex, textPtr, size)
		end)
	end

	-- name: one of ImGui.TextEditor.Languages, or nil for plain text
	function EditorMethods.SetLanguage(self, name)
		local ptr = Ptr(self)
		local id = if name == nil or name == "None" then 0 else tfind(EditorLanguages, name)
		if id == nil then
			error(sformat('[ImGui] unknown TextEditor language "%s" (expected None, %s)', tostring(name), tconcat(EditorLanguages, ", ")), 2)
		end
		self.__settings.Language = id
		Call("set_language", ptr, id)
	end

	function EditorMethods.GetLanguageName(self)
		local ptr = Ptr(self)
		return String(ptr, (Call("get_language_name", ptr)))
	end

	-- "Dark" (the default) or "Light"; resets colors set with SetPaletteColor
	function EditorMethods.SetPalette(self, name)
		local ptr = Ptr(self)
		if name ~= "Dark" and name ~= "Light" then
			error('[ImGui] TextEditor palettes are "Dark" and "Light"', 2)
		end
		self.__settings.Palette = name
		tclear(self.__settings.Colors)
		Call("set_palette", ptr, if name == "Light" then 1 else 0)
	end

	-- color: a name from ImGui.TextEditor.Colors; value: an ImU32 (ImGui.COL32) or a Color3 with an optional alpha
	function EditorMethods.SetPaletteColor(self, color, value, alpha)
		local ptr = Ptr(self)
		local index, u32 = PaletteIndex(color), ColorU32(value, alpha)
		self.__settings.Colors[index] = u32
		Call("set_palette_color", ptr, index, u32)
	end

	function EditorMethods.GetPaletteColor(self, color)
		return (Call("get_palette_color", Ptr(self), PaletteIndex(color))) % 4294967296
	end

	for index, option in EditorOptions do
		local id, setter, getter, flag = index - 1, option[1], option[2], option[3]
		if setter then
			EditorMethods[setter] = function(self, value)
				local ptr = Ptr(self)
				local number = if flag then (if value then 1 else 0) else tonumber(value) or 0
				self.__settings.Options[id] = number
				Call("set_option", ptr, id, number)
			end
		end
		EditorMethods[getter] = function(self)
			local value = Call("get_option", Ptr(self), id)
			if flag then
				return value ~= 0
			end
			return value
		end
	end

	for value, name in { [0] = "SetMiddleMouseScrollMode", [1] = "SetMiddleMousePanMode" } do
		EditorMethods[name] = function(self)
			local ptr = Ptr(self)
			self.__settings.Options[19] = value
			Call("set_option", ptr, 19, value)
		end
	end

	for index, name in EditorCommands do
		local id = index - 1
		EditorMethods[name] = function(self)
			Call("command", Ptr(self), id)
		end
	end

	for index, query in EditorQueries do
		local id, name, flag = index - 1, query[1], query[2]
		EditorMethods[name] = function(self)
			local value = Call("query", Ptr(self), id)
			if flag then
				return value ~= 0
			end
			return value
		end
	end

	function EditorMethods.SelectLine(self, line)
		Call("line", Ptr(self), 0, line, 0)
	end

	function EditorMethods.SelectLines(self, startLine, endLine)
		Call("line", Ptr(self), 1, startLine, endLine)
	end

	-- alignment: "Top", "Middle" (the default) or "Bottom"
	function EditorMethods.ScrollToLine(self, line, alignment)
		Call("line", Ptr(self), 2, line, ScrollAlignments[alignment or "Middle"] or 1)
	end

	for op, name in { [3] = "FoldAroundLine", [4] = "UnfoldAroundLine", [5] = "ToggleAtLine" } do
		EditorMethods[name] = function(self, line)
			Call("line", Ptr(self), op, line, 0)
		end
	end

	for op, name in { [6] = "IsLineFoldable", [7] = "IsLineFolded", [8] = "IsLineVisible", [9] = "IsLineHidden" } do
		EditorMethods[name] = function(self, line)
			return Call("line", Ptr(self), op, line, 0) ~= 0
		end
	end

	function EditorMethods.SelectToBrackets(self, includeBrackets)
		Call("line", Ptr(self), 10, 0, if includeBrackets == false then 0 else 1)
	end

	function EditorMethods.AddNextOccurrence(self, wholeWord)
		Call("line", Ptr(self), 11, 0, if wholeWord then 1 else 0)
	end

	function EditorMethods.SelectAllOccurrences(self, wholeWord)
		Call("line", Ptr(self), 12, 0, if wholeWord then 1 else 0)
	end

	function EditorMethods.SetCursor(self, line, index)
		Call("region", Ptr(self), 0, line, index, 0, 0)
	end

	function EditorMethods.SelectRegion(self, startLine, startIndex, endLine, endIndex)
		Call("region", Ptr(self), 1, startLine, startIndex, endLine, endIndex)
	end

	-- Without arguments, removes every squiggle
	function EditorMethods.ClearSquiggles(self, startLine, startIndex, endLine, endIndex)
		local ptr = Ptr(self)
		if startLine == nil then
			Call("command", ptr, 14)
		else
			Call("region", ptr, 2, startLine, startIndex, endLine, endIndex)
		end
	end

	-- Return line, index
	for which, name in { [0] = "GetCursorPosition", [1] = "GetMainCursorPosition", [2] = "GetCurrentCursorPosition" } do
		EditorMethods[name] = function(self, cursor)
			local line, index = Positions((Call("cursor", Ptr(self), which, cursor or 0)))
			return line, index
		end
	end

	-- Return startLine, startIndex, endLine, endIndex
	for which, name in { [3] = "GetCursorSelection", [4] = "GetMainCursorSelection", [5] = "GetCurrentCursorSelection" } do
		EditorMethods[name] = function(self, cursor)
			return Positions((Call("cursor", Ptr(self), which, cursor or 0)))
		end
	end

	function EditorMethods.IsMousePosOverGlyph(self, pos)
		return Call("mouse", Ptr(self), 0, pos.X, pos.Y) ~= 0
	end

	function EditorMethods.IsMousePosOverTextArea(self, pos)
		return Call("mouse", Ptr(self), 1, pos.X, pos.Y) ~= 0
	end

	function EditorMethods.GetDocPosAtMousePos(self, pos)
		local line, index = Positions((Call("mouse", Ptr(self), 2, pos.X, pos.Y)))
		return line, index
	end

	function EditorMethods.GetWordAtMousePos(self, pos)
		local ptr = Ptr(self)
		return String(ptr, (Call("get_word_at_mouse_pos", ptr, pos.X, pos.Y)))
	end

	-- (text, caseSensitive = true, wholeWord = false)
	for op, name in { [0] = "SelectFirstOccurrenceOf", [1] = "SelectNextOccurrenceOf", [2] = "SelectAllOccurrencesOf" } do
		EditorMethods[name] = function(self, text, caseSensitive, wholeWord)
			local ptr = Ptr(self)
			WithText(text, function(textPtr, size)
				Call("find", ptr, op, textPtr, size, if caseSensitive == false then 0 else 1, if wholeWord then 1 else 0)
			end)
		end
	end

	for op, name in {
		[0] = "ReplaceTextInCurrentCursor", [1] = "ReplaceTextInAllCursors", [2] = "SetFindButtonLabel",
		[3] = "SetFindAllButtonLabel", [4] = "SetReplaceButtonLabel", [5] = "SetReplaceAllButtonLabel",
	} do
		EditorMethods[name] = function(self, text)
			local ptr = Ptr(self)
			if op >= 2 then
				self.__settings.Labels[op] = tostring(text)
			end
			WithText(text, function(textPtr, size)
				Call("string", ptr, op, textPtr, size)
			end)
		end
	end

	function EditorMethods.AddMarker(self, line, lineNumberColor, textColor, lineNumberTooltip, textTooltip)
		local ptr = Ptr(self)
		local numberColor, lineColor = ColorU32(lineNumberColor), ColorU32(textColor)
		WithText(lineNumberTooltip, function(numberPtr, numberSize)
			WithText(textTooltip, function(textPtr, textSize)
				Call("add_marker", ptr, line, numberColor, lineColor, numberPtr, numberSize, textPtr, textSize)
			end)
		end)
	end

	function EditorMethods.AddSquiggle(self, startLine, startIndex, endLine, endIndex, kind, color, tooltip)
		local ptr = Ptr(self)
		local u32 = ColorU32(color)
		WithText(tooltip, function(textPtr, size)
			Call("add_squiggle", ptr, startLine, startIndex, endLine, endIndex, kind or 0, u32, textPtr, size)
		end)
	end

	return {
		-- The fields added to the ImGui table of a script that loads the addon
		Bind = function(script)
			return {
				TextEditor = {
					new = function()
						return CreateEditor(script)
					end,
					Languages = table.clone(EditorLanguages),
					Colors = table.clone(EditorColors),
				},
			}
		end,
		-- The script shut down: free its editors
		Leave = function(script)
			local owned = EditorsByScript[script]
			if owned ~= nil then
				for editor in table.clone(owned) do
					DestroyEditor(editor)
				end
				EditorsByScript[script] = nil
			end
		end,
		-- The script moves to another context: what Restore needs there
		Snapshot = function(script)
			local snapshots = {}
			for editor in EditorsByScript[script] or {} do
				snapshots[editor] = SnapshotEditor(editor)
			end
			return snapshots
		end,
		Restore = function(script, snapshots)
			for editor, snapshot in snapshots do
				RestoreEditor(script, editor, snapshot)
			end
		end,
	}
end

return IDE

-- imnodes addon (github.com/Nelarius/imnodes, MIT) as ImGui.ImNodes: an immediate-mode node editor.
--
--     local NodesAddon = loadstring(game:HttpGet(".../imnodes.luau"))()
--     ImGui.Init({ Addons = NodesAddon })
--     local ImNodes = ImGui.ImNodes
--     ImNodes.BeginNodeEditor()
--     ImNodes.BeginNode(1)
--     ImNodes.BeginNodeTitleBar() ImGui.Text("Add") ImNodes.EndNodeTitleBar()
--     ImNodes.BeginOutputAttribute(2) ImGui.Text("result") ImNodes.EndOutputAttribute()
--     ImNodes.EndNode()
--     ImNodes.EndNodeEditor()
--     local created, from, to = ImNodes.IsLinkCreated()
--
-- Functions keep imnodes' C++ names. Out parameters come back as extra return values. Node, attribute and link ids are
-- numbers the script chooses; they must be unique within an editor.

local Modules, Enums, Common = ...

local ImNodesAddon = { Name = "ImNodes", Protocol = 1, ImGuiVersion = "1.92.9b", Modules = Modules }

function ImNodesAddon.Install(host)
	local C = Common(host)
	local Call, Release, String, XY, ColorU32 = C.Call, C.Release, C.String, C.XY, C.ColorU32
	local E = C.Exports("rbx_imnodes_", {
		"init", "ints", "editor_create", "editor_free", "editor_set", "get_panning", "reset_panning", "move_to_node",
		"style_colors", "begin_editor", "end_editor", "minimap", "push_color", "pop_color", "push_style_var", "pop_style_var",
		"begin_node", "end_node", "begin_title_bar", "end_title_bar", "get_node_dimensions", "begin_attribute",
		"end_attribute", "push_attribute_flag", "pop_attribute_flag", "link", "set_node_draggable", "snap_node_to_grid",
		"set_node_pos", "get_node_pos", "query", "select", "selected", "save_state", "load_state", "io",
	})
	Call(E.init)
	local ints = (Call(E.ints))
	local editorsByScript = {} -- script record -> { [editor] = true }
	local tables = setmetatable({}, { __mode = "k" }) -- script record -> its ImNodes table

	local ImNodes = {}
	for name, values in Enums do
		ImNodes[name] = table.clone(values)
	end
	ImNodes.Modifier = { None = 0, Ctrl = 1, Shift = 2, Alt = 3, Super = 4 }

	local function Vector(ptr)
		local x, y = C.ReadDoubles(ptr, 2)
		return Vector2.new(x, y)
	end

	local function Int(index)
		return (C.ReadInts(ints + index * 4, 1))
	end

	local function Query(op, arg)
		return Call(E.query, op, arg or 0)
	end

	---------------------------------------------------------------------------- editors and style

	-- nil: the default editor
	function ImNodes.EditorContextSet(editor)
		Call(E.editor_set, if editor ~= nil then editor.__ptr else 0)
	end

	function ImNodes.EditorContextFree(editor)
		if editor.__ptr ~= 0 then
			Call(E.editor_set, 0)
			Call(E.editor_free, editor.__ptr)
			editor.__ptr = 0
		end
		local owned = editorsByScript[editor.__script]
		if owned ~= nil then
			owned[editor] = nil
		end
	end

	function ImNodes.EditorContextGetPanning()
		return Vector((Call(E.get_panning)))
	end

	function ImNodes.EditorContextResetPanning(position)
		local x, y = XY(position)
		Call(E.reset_panning, x, y)
	end

	function ImNodes.EditorContextMoveToNode(nodeId)
		Call(E.move_to_node, nodeId)
	end

	for which, name in { [0] = "StyleColorsDark", [1] = "StyleColorsClassic", [2] = "StyleColorsLight" } do
		ImNodes[name] = function()
			Call(E.style_colors, which)
		end
	end

	function ImNodes.BeginNodeEditor()
		Call(E.begin_editor)
	end

	function ImNodes.EndNodeEditor()
		Call(E.end_editor)
	end

	-- Call between the last node and EndNodeEditor. location: ImNodes.MiniMapLocation (TopLeft by default)
	function ImNodes.MiniMap(fraction, location)
		Call(E.minimap, fraction or 0.2, location or ImNodes.MiniMapLocation.TopLeft)
	end

	function ImNodes.PushColorStyle(item, color)
		Call(E.push_color, item, ColorU32(color))
	end

	function ImNodes.PopColorStyle()
		Call(E.pop_color)
	end

	-- value: a number, or a Vector2 for the ImVec2 variables
	function ImNodes.PushStyleVar(item, value)
		if type(value) == "number" then
			Call(E.push_style_var, item, value, 0, 0)
		else
			local x, y = XY(value)
			Call(E.push_style_var, item, x, y, 1)
		end
	end

	function ImNodes.PopStyleVar(count)
		Call(E.pop_style_var, count or 1)
	end

	---------------------------------------------------------------------------- nodes, attributes and links

	function ImNodes.BeginNode(id)
		Call(E.begin_node, id)
	end

	function ImNodes.EndNode()
		Call(E.end_node)
	end

	function ImNodes.GetNodeDimensions(id)
		return Vector((Call(E.get_node_dimensions, id)))
	end

	function ImNodes.BeginNodeTitleBar()
		Call(E.begin_title_bar)
	end

	function ImNodes.EndNodeTitleBar()
		Call(E.end_title_bar)
	end

	-- shape: ImNodes.PinShape (CircleFilled by default)
	function ImNodes.BeginInputAttribute(id, shape)
		Call(E.begin_attribute, 0, id, shape or ImNodes.PinShape.CircleFilled)
	end

	function ImNodes.EndInputAttribute()
		Call(E.end_attribute, 0)
	end

	function ImNodes.BeginOutputAttribute(id, shape)
		Call(E.begin_attribute, 1, id, shape or ImNodes.PinShape.CircleFilled)
	end

	function ImNodes.EndOutputAttribute()
		Call(E.end_attribute, 1)
	end

	function ImNodes.BeginStaticAttribute(id)
		Call(E.begin_attribute, 2, id, 0)
	end

	function ImNodes.EndStaticAttribute()
		Call(E.end_attribute, 2)
	end

	function ImNodes.PushAttributeFlag(flag)
		Call(E.push_attribute_flag, flag)
	end

	function ImNodes.PopAttributeFlag()
		Call(E.pop_attribute_flag)
	end

	function ImNodes.Link(id, startAttributeId, endAttributeId)
		Call(E.link, id, startAttributeId, endAttributeId)
	end

	function ImNodes.SetNodeDraggable(nodeId, draggable)
		Call(E.set_node_draggable, nodeId, if draggable == false then 0 else 1)
	end

	for space, name in { [0] = "Screen", [1] = "Editor", [2] = "Grid" } do
		ImNodes["SetNode" .. name .. "SpacePos"] = function(nodeId, position)
			local x, y = XY(position)
			Call(E.set_node_pos, space, nodeId, x, y)
		end
		ImNodes["GetNode" .. name .. "SpacePos"] = function(nodeId)
			return Vector((Call(E.get_node_pos, space, nodeId)))
		end
	end

	function ImNodes.SnapNodeToGrid(nodeId)
		Call(E.snap_node_to_grid, nodeId)
	end

	---------------------------------------------------------------------------- queries (after EndNodeEditor)

	function ImNodes.IsEditorHovered()
		return Query(0) ~= 0
	end

	-- Return hovered, id
	for op, name in { [1] = "IsNodeHovered", [2] = "IsLinkHovered", [3] = "IsPinHovered" } do
		ImNodes[name] = function()
			local hovered = Query(op) ~= 0
			return hovered, if hovered then Int(0) else nil
		end
	end

	function ImNodes.NumSelectedNodes()
		return Query(4)
	end

	function ImNodes.NumSelectedLinks()
		return Query(5)
	end

	-- Return a table of ids
	for links, name in { [0] = "GetSelectedNodes", [1] = "GetSelectedLinks" } do
		ImNodes[name] = function()
			local count = Query(4 + links)
			local ids = {}
			if count > 0 then
				ids = { C.ReadInts((Call(E.selected, links)), count) }
			end
			return ids
		end
	end

	-- Without an id, clears the whole selection
	function ImNodes.ClearNodeSelection(nodeId)
		Call(E.select, if nodeId ~= nil then 1 else 4, nodeId or 0)
	end

	function ImNodes.ClearLinkSelection(linkId)
		Call(E.select, if linkId ~= nil then 3 else 5, linkId or 0)
	end

	function ImNodes.SelectNode(nodeId)
		Call(E.select, 0, nodeId)
	end

	function ImNodes.SelectLink(linkId)
		Call(E.select, 2, linkId)
	end

	function ImNodes.IsNodeSelected(nodeId)
		return Query(6, nodeId) ~= 0
	end

	function ImNodes.IsLinkSelected(linkId)
		return Query(7, linkId) ~= 0
	end

	function ImNodes.IsAttributeActive()
		return Query(8) ~= 0
	end

	-- Return active, attributeId
	function ImNodes.IsAnyAttributeActive()
		local active = Query(9) ~= 0
		return active, if active then Int(0) else nil
	end

	-- Return started, attributeId
	function ImNodes.IsLinkStarted()
		local started = Query(10) ~= 0
		return started, if started then Int(0) else nil
	end

	-- Return dropped, attributeId
	function ImNodes.IsLinkDropped(includingDetachedLinks)
		local dropped = Query(11, if includingDetachedLinks == false then 0 else 1) ~= 0
		return dropped, if dropped then Int(0) else nil
	end

	-- Return destroyed, linkId
	function ImNodes.IsLinkDestroyed()
		local destroyed = Query(12) ~= 0
		return destroyed, if destroyed then Int(0) else nil
	end

	-- Return created, startAttributeId, endAttributeId, createdFromSnap
	function ImNodes.IsLinkCreated()
		if Query(13) == 0 then
			return false
		end
		return true, Int(0), Int(1), Int(2) ~= 0
	end

	-- The other C++ overload. Return created, startNodeId, startAttributeId, endNodeId, endAttributeId, createdFromSnap
	function ImNodes.IsLinkCreatedWithNodes()
		if Query(14) == 0 then
			return false
		end
		return true, Int(0), Int(1), Int(2), Int(3), Int(4) ~= 0
	end

	-- Node positions and panning of the current editor, as text for LoadCurrentEditorStateFromIniString
	function ImNodes.SaveCurrentEditorStateToIniString()
		local ptr = (Call(E.save_state))
		return buffer.readstring(host.Mem(), ptr, Int(0))
	end

	function ImNodes.LoadCurrentEditorStateFromIniString(text)
		local ptr, size = String(text)
		Call(E.load_state, ptr, size)
		Release()
	end

	-- io.LinkDetachWithModifierClick = ImNodes.Modifier.Ctrl; also EmulateThreeButtonMouse, MultipleSelectModifier
	-- (modifiers), AltMouseButton and AutoPanningSpeed. Settings apply to every editor.
	local IO_FIELDS = { EmulateThreeButtonMouse = 0, LinkDetachWithModifierClick = 1, MultipleSelectModifier = 2, AltMouseButton = 3, AutoPanningSpeed = 4 }
	local IO = setmetatable({}, {
		__newindex = function(_, key, value)
			local op = IO_FIELDS[key] or error(string.format('[ImGui] ImNodes IO has no setting "%s"', tostring(key)), 2)
			Call(E.io, op, value)
		end,
	})

	function ImNodes.GetIO()
		return IO
	end

	local function Own(script, editor)
		editor.__script = script
		local owned = editorsByScript[script]
		if owned == nil then
			owned = {}
			editorsByScript[script] = owned
		end
		owned[editor] = true
	end

	return {
		Bind = function(script)
			local scriptTable = tables[script]
			if scriptTable == nil then
				scriptTable = setmetatable({}, { __index = ImNodes })
				-- An editor of this script's own, freed by EditorContextFree or when the script shuts down
				function scriptTable.EditorContextCreate()
					local editor = { __ptr = (Call(E.editor_create)) }
					Own(script, editor)
					return editor
				end
				tables[script] = scriptTable
			end
			return { ImNodes = scriptTable }
		end,
		Leave = function(script)
			for editor in table.clone(editorsByScript[script] or {}) do
				ImNodes.EditorContextFree(editor)
			end
			editorsByScript[script] = nil
		end,
		Snapshot = function(script)
			local states = {}
			for editor in editorsByScript[script] or {} do
				Call(E.editor_set, editor.__ptr)
				states[editor] = ImNodes.SaveCurrentEditorStateToIniString()
			end
			Call(E.editor_set, 0)
			return states
		end,
		Restore = function(script, states)
			for editor, state in states do
				editor.__ptr = (Call(E.editor_create))
				Own(script, editor)
				Call(E.editor_set, editor.__ptr)
				ImNodes.LoadCurrentEditorStateFromIniString(state)
			end
			Call(E.editor_set, 0)
		end,
	}
end

return ImNodesAddon

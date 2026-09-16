-- The imnodes addon (imnodes.luau) linked into the bundle: nodes with title bars, attributes, a link and a minimap draw
-- inside a window, positions and selection work, the editor state saves and loads, and editors of a script's own are
-- created, used and freed; nothing asserts.
local ImGui = ImGuiBundle
local W, H = 900, 700
local failures, warnings, stepErrors = 0, 0, 0

local realPrint = print
print = function(first, ...)
	if first == "[warn]" then
		warnings += 1
	end
	realPrint(first, ...)
end

local function check(name, ok)
	realPrint((if ok then "PASS " else "FAIL ") .. name)
	if not ok then
		failures += 1
	end
end

ImGui.Init({
	RenderMode = "DrawingImmediate", DrawingImmediate = MockDrawingImmediate, AutoRender = false, Input = false,
	DisplaySize = Vector2.new(W, H), Addons = ImGuiAddons.imnodes,
	MeasureText = function(_, size, text)
		return (utf8.len(text) or #text) * HarnessAdvance(size)
	end,
})
local ImNodes = ImGui.ImNodes
check("ImGui.ImNodes and its enums", ImNodes ~= nil and ImNodes.PinShape.CircleFilled == 1 and ImNodes.Col.NodeBackground == 0
	and ImNodes.MiniMapLocation.BottomRight ~= nil)

local ownEditor = nil
local placed = false
local seen = {}
ImGui.OnFrame(function()
	ImGui.SetNextWindowPos(Vector2.new(10, 10), ImGui.Cond.Always)
	ImGui.SetNextWindowSize(Vector2.new(860, 660), ImGui.Cond.Always)
	ImGui.Begin("Graph")
	if ownEditor ~= nil then
		ImNodes.EditorContextSet(ownEditor)
	end
	ImNodes.BeginNodeEditor()
	if not placed then
		ImNodes.SetNodeGridSpacePos(1, Vector2.new(40, 40))
		ImNodes.SetNodeGridSpacePos(2, Vector2.new(300, 60))
		placed = true
	end
	ImNodes.BeginNode(1)
	ImNodes.BeginNodeTitleBar()
	ImGui.Text("Source")
	ImNodes.EndNodeTitleBar()
	ImNodes.BeginOutputAttribute(11)
	ImGui.Text("out")
	ImNodes.EndOutputAttribute()
	ImNodes.EndNode()

	ImNodes.PushColorStyle(ImNodes.Col.TitleBar, Color3.new(0.6, 0.2, 0.2))
	ImNodes.BeginNode(2)
	ImNodes.BeginNodeTitleBar()
	ImGui.Text("Sink")
	ImNodes.EndNodeTitleBar()
	ImNodes.BeginInputAttribute(20, ImNodes.PinShape.Triangle)
	ImGui.Text("in")
	ImNodes.EndInputAttribute()
	ImNodes.BeginStaticAttribute(21)
	ImGui.Text("static")
	ImNodes.EndStaticAttribute()
	ImNodes.EndNode()
	ImNodes.PopColorStyle()

	ImNodes.Link(100, 11, 20)
	ImNodes.MiniMap(0.2, ImNodes.MiniMapLocation.BottomRight)
	ImNodes.EndNodeEditor()
	seen.created = ImNodes.IsLinkCreated()
	seen.destroyed = ImNodes.IsLinkDestroyed()
	seen.hovered = ImNodes.IsEditorHovered()
	ImGui.End()
	if ownEditor ~= nil then
		ImNodes.EditorContextSet(nil)
	end
end)

local function frame()
	table.clear(DrawCalls)
	local ok, err = pcall(ImGui.Step, 1 / 60, W, H)
	if not ok then
		stepErrors += 1
		realPrint("  step error: " .. tostring(err))
	end
end

local function drawn(text)
	for _, call in DrawCalls do
		if call[1] == "text" and string.find(call[10], text, 1, true) then
			return true
		end
	end
	return false
end

frame()
frame()
check(string.format("frames run without errors (%d) or assertions (%d)", stepErrors, warnings), stepErrors == 0 and warnings == 0)
check("node titles and attributes are drawn", drawn("Source") and drawn("Sink") and drawn("out") and drawn("static"))
local position = ImNodes.GetNodeGridSpacePos(2)
check(string.format("SetNodeGridSpacePos sticks (%.0f, %.0f)", position.X, position.Y), position.X == 300 and position.Y == 60)
check("GetNodeDimensions measures a drawn node", ImNodes.GetNodeDimensions(1).X > 10)
check("no link is created or destroyed without input", seen.created == false and seen.destroyed == false)

ImNodes.SelectNode(1)
local selected = ImNodes.GetSelectedNodes()
check("SelectNode and GetSelectedNodes", ImNodes.NumSelectedNodes() == 1 and selected[1] == 1 and ImNodes.IsNodeSelected(1))
ImNodes.ClearNodeSelection()
check("ClearNodeSelection", ImNodes.NumSelectedNodes() == 0)

local state = ImNodes.SaveCurrentEditorStateToIniString()
check("the editor state saves node positions", string.find(state, "[node.2]", 1, true) ~= nil)
ImNodes.SetNodeGridSpacePos(2, Vector2.new(0, 0))
ImNodes.LoadCurrentEditorStateFromIniString(state)
frame()
check("loading the state puts nodes back", ImNodes.GetNodeGridSpacePos(2).X == 300)

ownEditor = ImNodes.EditorContextCreate()
placed = false
frame()
frame()
ImNodes.EditorContextSet(ownEditor)
local ownPosition = ImNodes.GetNodeGridSpacePos(2)
ImNodes.EditorContextSet(nil)
check("an editor of the script's own draws and keeps its own positions", ownEditor.__ptr ~= 0 and ownPosition.X == 300 and drawn("Sink"))
ImNodes.EditorContextFree(ownEditor)
ownEditor = nil
frame()
check(string.format("still no errors (%d) or assertions (%d)", stepErrors, warnings), stepErrors == 0 and warnings == 0)

ImGui.Shutdown()
realPrint(string.format("RESULT %d failure(s)", failures))

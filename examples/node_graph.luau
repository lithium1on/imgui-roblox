-- A small calculator graph with the imnodes addon (imnodes.luau):
-- - "Number" nodes feed an "Add" node, whose sum shows on the "Output" node;
-- - drag from one pin to another to link them, Ctrl+click a link to take it off;
-- - "Add number" puts another node on the canvas; the minimap sits in the corner.

local NodesAddon = loadstring(game:HttpGet("https://github.com/lithium1on/imgui-roblox/releases/latest/download/imnodes.luau"))()
local ImGui = loadstring(game:HttpGet("https://github.com/lithium1on/imgui-roblox/releases/latest/download/imgui.luau"))()
ImGui.Init({ Font = "Monospace", FontSize = 13, Addons = NodesAddon })
local ImNodes = ImGui.ImNodes
ImNodes.GetIO().LinkDetachWithModifierClick = ImNodes.Modifier.Ctrl

-- Pins are node id * 10 + pin number
local nodes = {
	{ id = 1, kind = "Number", value = 2 },
	{ id = 2, kind = "Number", value = 3 },
	{ id = 3, kind = "Add" },
	{ id = 4, kind = "Output" },
}
local links = { { id = 1, from = 11, to = 31 }, { id = 2, from = 21, to = 32 }, { id = 3, from = 33, to = 41 } }
local nextNode, nextLink = 5, 4
local placed = {}

local function findNode(id)
	for _, node in nodes do
		if node.id == id then
			return node
		end
	end
	return nil
end

local function isOutput(pin)
	local node = findNode(pin // 10)
	return node ~= nil and ((node.kind == "Number" and pin % 10 == 1) or (node.kind == "Add" and pin % 10 == 3))
end

local valueOf
local function inputValue(pin, depth)
	for _, link in links do
		if link.to == pin then
			return valueOf(link.from, depth + 1)
		end
	end
	return 0
end

function valueOf(pin, depth)
	local node = findNode(pin // 10)
	if node == nil or depth > 32 then
		return 0
	elseif node.kind == "Number" then
		return node.value
	end
	return inputValue(node.id * 10 + 1, depth) + inputValue(node.id * 10 + 2, depth)
end

ImGui.OnFrame(function()
	ImGui.SetNextWindowSize(Vector2.new(720, 440), ImGui.Cond.FirstUseEver)
	if ImGui.Begin("Node graph") then
		if ImGui.Button("Add number") then
			table.insert(nodes, { id = nextNode, kind = "Number", value = 1 })
			nextNode += 1
		end
		ImGui.SameLine()
		ImGui.TextDisabled("drag between pins to link, Ctrl+click a link to remove it")

		ImNodes.BeginNodeEditor()
		for index, node in nodes do
			if not placed[node.id] then
				local column = if node.kind == "Number" then 0 elseif node.kind == "Add" then 1 else 2
				ImNodes.SetNodeGridSpacePos(node.id, Vector2.new(20 + column * 210, 30 + (index - 1) % 3 * 110))
				placed[node.id] = true
			end
			ImNodes.BeginNode(node.id)
			ImNodes.BeginNodeTitleBar()
			ImGui.Text(node.kind)
			ImNodes.EndNodeTitleBar()
			if node.kind == "Number" then
				ImGui.SetNextItemWidth(90)
				local _
				_, node.value = ImGui.DragFloat("##value" .. node.id, node.value, 0.1)
				ImNodes.BeginOutputAttribute(node.id * 10 + 1)
				ImGui.Text("value")
				ImNodes.EndOutputAttribute()
			elseif node.kind == "Add" then
				ImNodes.BeginInputAttribute(node.id * 10 + 1)
				ImGui.Text("a")
				ImNodes.EndInputAttribute()
				ImNodes.BeginInputAttribute(node.id * 10 + 2)
				ImGui.Text("b")
				ImNodes.EndInputAttribute()
				ImNodes.BeginOutputAttribute(node.id * 10 + 3)
				ImGui.Text("sum")
				ImNodes.EndOutputAttribute()
			else
				ImNodes.BeginInputAttribute(node.id * 10 + 1)
				ImGui.Text("result: %.2f", inputValue(node.id * 10 + 1, 0))
				ImNodes.EndInputAttribute()
			end
			ImNodes.EndNode()
		end
		for _, link in links do
			ImNodes.Link(link.id, link.from, link.to)
		end
		ImNodes.MiniMap(0.15, ImNodes.MiniMapLocation.BottomRight)
		ImNodes.EndNodeEditor()

		local created, from, to = ImNodes.IsLinkCreated()
		if created then
			if not isOutput(from) then
				from, to = to, from
			end
			if isOutput(from) and not isOutput(to) then
				for i = #links, 1, -1 do
					if links[i].to == to then
						table.remove(links, i) -- an input takes one link
					end
				end
				table.insert(links, { id = nextLink, from = from, to = to })
				nextLink += 1
			end
		end
		local destroyed, linkId = ImNodes.IsLinkDestroyed()
		if destroyed then
			for i = #links, 1, -1 do
				if links[i].id == linkId then
					table.remove(links, i)
				end
			end
		end
	end
	ImGui.End()
end)

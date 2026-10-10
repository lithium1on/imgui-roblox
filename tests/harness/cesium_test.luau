-- The Cesium render mode (Roblox UI instances) against a fake Roblox: Frames, TextLabels, UICorner and UIGradient in a
-- ScreenGui. Checks the draw order, that a frame that did not change writes nothing, that ImGui.Cesium.Parent moves the
-- ScreenGui, and that the instances cover the same pixels as the DrawingImmediate calls for the same window.
local ImGui = ImGuiBundle
local W, H = 1280, 800
local failures = 0

local function check(name, ok)
	print((if ok then "PASS " else "FAIL ") .. name)
	if not ok then
		failures += 1
	end
end

--------------------------------------------------------------------------------
-- Fake Roblox
--------------------------------------------------------------------------------

UDim = { new = function(s, o) return { Scale = s, Offset = o } end }
UDim2 = { new = function(sx, ox, sy, oy) return { X = { Scale = sx, Offset = ox }, Y = { Scale = sy, Offset = oy } } end }
NumberSequenceKeypoint = { new = function(t, v) return { Time = t, Value = v } end }
NumberSequence = {
	new = function(a, b)
		if type(a) == "table" then
			return { Keypoints = a }
		end
		return { Keypoints = { { Time = 0, Value = a }, { Time = 1, Value = b } } }
	end,
}
ColorSequence = { new = function(a, b) return { A = a, B = b or a } end }
Enum = {
	ZIndexBehavior = { Sibling = "Sibling" }, ScreenInsets = { None = "None" },
	Font = { BuilderSans = "BuilderSans", Arial = "Arial", SourceSans = "SourceSans", RobotoMono = "RobotoMono" },
	TextXAlignment = { Left = "Left" }, TextYAlignment = { Top = "Top" },
}

local writes = 0
local writeLog = {}
local all = {}
warn = function() end
local function NewInstance(className)
	local props = { ClassName = className, Children = {}, Visible = true, ZIndex = 1 }
	if className == "ScreenGui" then
		props.AbsoluteSize = Vector2.new(W, H)
	end
	local object
	object = setmetatable({}, {
		__index = function(_, key)
			if key == "Destroy" then
				return function()
					props.Destroyed = true
					if props.Parent then
						local siblings = props.Parent.Children
						local at = table.find(siblings, object)
						if at then table.remove(siblings, at) end
					end
					for _, child in props.Children do child:Destroy() end
				end
			end
			return props[key]
		end,
		__newindex = function(_, key, value)
			if props.Destroyed then error("write to a destroyed instance") end
			writes += 1
			writeLog[className .. "." .. tostring(key)] = (writeLog[className .. "." .. tostring(key)] or 0) + 1
			if key == "Parent" then
				if props.Parent then
					local siblings = props.Parent.Children
					local at = table.find(siblings, object)
					if at then table.remove(siblings, at) end
				end
				if value ~= nil and value.Locked then return end -- a container scripts may not use
				props.Parent = value
				if value then table.insert(value.Children, object) end
				return
			end
			props[key] = value
		end,
	})
	table.insert(all, object)
	return object
end
Instance = { new = NewInstance }

local container = NewInstance("Folder")
local other = NewInstance("Folder")
local locked = NewInstance("Folder")
locked.Locked = true
local TextService = { GetTextSize = function(_, text, size) return Vector2.new(#text * HarnessAdvance(size), size) end }
game = {
	GetService = function(_, name)
		if name == "TextService" then return TextService end
		return container
	end,
}
gethui = function() return container end

--------------------------------------------------------------------------------
-- What the instances show
--------------------------------------------------------------------------------

local function resolve(udim2, parentW, parentH)
	return udim2.X.Scale * parentW + udim2.X.Offset, udim2.Y.Scale * parentH + udim2.Y.Offset
end

-- Region of a frame inside its parent, as a function (x, y) -> bool in the parent's pixels, with a bounding box
local function region(frame, parentW, parentH)
	local px, py = resolve(frame.Position, parentW, parentH)
	local w, h = resolve(frame.Size, parentW, parentH)
	local anchor = frame.AnchorPoint or Vector2.new(0, 0)
	local rot = math.rad(frame.Rotation or 0)
	local cx, cy = px - anchor.X * w + w / 2, py - anchor.Y * h + h / 2 -- center, whichever the anchor
	if frame.Rotation and frame.Rotation ~= 0 then
		cx, cy = px, py -- rotated frames are anchored at their center
	end
	local radius, mask = 0, nil
	for _, child in frame.Children do
		if child.ClassName == "UICorner" then
			radius = child.CornerRadius.Offset
		elseif child.ClassName == "UIGradient" and child.Enabled ~= false then
			local keys = child.Transparency and child.Transparency.Keypoints
			if keys and #keys == 4 then
				mask = math.rad(child.Rotation or 0)
			end
		end
	end
	local cr, sr = math.cos(rot), math.sin(rot)
	local reach = math.abs(w * cr) / 2 + math.abs(h * sr) / 2
	local reachY = math.abs(w * sr) / 2 + math.abs(h * cr) / 2
	local function contains(x, y)
		local dx, dy = x - cx, y - cy
		local lx, ly = dx * cr + dy * sr + w / 2, -dx * sr + dy * cr + h / 2 -- into the frame's own pixels
		if lx < 0 or ly < 0 or lx > w or ly > h then return false end
		if radius > 0 then
			local r = math.min(radius, w / 2, h / 2)
			local qx, qy = math.max(r - lx, lx - (w - r), 0), math.max(r - ly, ly - (h - r), 0)
			if qx * qx + qy * qy > r * r then return false end
		end
		if mask then
			local dxm, dym = math.cos(mask), math.sin(mask)
			local lo, hi = math.min(0, w * dxm) + math.min(0, h * dym), math.max(0, w * dxm) + math.max(0, h * dym)
			if (lx * dxm + ly * dym - lo) / (hi - lo) > 0.5 then return false end
		end
		return true
	end
	return contains, cx - reach, cy - reachY, cx + reach, cy + reachY, w, h
end

-- Pixels painted by the ScreenGui, as a set of "x,y" cells (1 pixel)
local function paintedBy(gui)
	local cells = {}
	local function mark(contains, x0, y0, x1, y1, clip, color)
		for y = math.floor(y0), math.ceil(y1) do
			for x = math.floor(x0), math.ceil(x1) do
				local sx, sy = x + 0.5, y + 0.5
				if contains(sx, sy) and (clip == nil or clip(sx, sy)) then
					cells[x .. "," .. y] = color
				end
			end
		end
	end
	local function colorOf(frame, gradient)
		if gradient then return "grad" end
		local c = frame.BackgroundColor3
		return c.r .. "," .. c.g .. "," .. c.b
	end
	local function hasGradient(frame)
		for _, child in frame.Children do
			if child.ClassName == "UIGradient" and child.Enabled ~= false and child.Transparency and #child.Transparency.Keypoints == 2 then return true end
		end
		return false
	end
	for _, slot in gui.Children do
		if slot.ClassName == "Frame" and slot.Visible then
			local contains, x0, y0, x1, y1, w, h = region(slot, W, H)
			if slot.BackgroundTransparency < 1 then
				mark(contains, x0, y0, x1, y1, nil, colorOf(slot, hasGradient(slot)))
			end
			for _, child in slot.Children do
				if child.ClassName == "Frame" and child.Visible then
					local inner, bx0, by0, bx1, by1 = region(child, w, h)
					local ox, oy = resolve(slot.Position, W, H)
					ox, oy = ox - (slot.AnchorPoint and slot.AnchorPoint.X or 0) * w, oy - (slot.AnchorPoint and slot.AnchorPoint.Y or 0) * h
					if child.BackgroundTransparency < 1 then
						mark(function(x, y) return inner(x - ox, y - oy) end, bx0 + ox, by0 + oy, bx1 + ox, by1 + oy, function(x, y) return contains(x, y) end, colorOf(child, false))
					end
				end
			end
		end
	end
	return cells
end

-- Pixels painted by DrawingImmediate calls (text left out)
local function paintedByCalls(calls)
	local cells = {}
	local function inTriangle(x, y, ax, ay, bx, by, cx, cy)
		local d1 = (x - bx) * (ay - by) - (ax - bx) * (y - by)
		local d2 = (x - cx) * (by - cy) - (bx - cx) * (y - cy)
		local d3 = (x - ax) * (cy - ay) - (cx - ax) * (y - ay)
		return not ((d1 < 0 or d2 < 0 or d3 < 0) and (d1 > 0 or d2 > 0 or d3 > 0))
	end
	local color
	local function fill(x0, y0, x1, y1, test)
		for y = math.floor(y0), math.ceil(y1) do
			for x = math.floor(x0), math.ceil(x1) do
				if test(x + 0.5, y + 0.5) then cells[x .. "," .. y] = color end
			end
		end
	end
	for _, c in calls do
		local kind = c[1]
		if kind == "rect" then color = c[6] .. "," .. c[7] .. "," .. c[8]
		elseif kind == "quad" then color = c[10] .. "," .. c[11] .. "," .. c[12]
		elseif kind == "tri" then color = c[8] .. "," .. c[9] .. "," .. c[10]
		elseif kind == "circle" then color = c[5] .. "," .. c[6] .. "," .. c[7] end
		if kind == "rect" then
			local x, y, w, h, r = c[2], c[3], c[4], c[5], math.min(c[10] or 0, c[4] / 2, c[5] / 2)
			fill(x, y, x + w, y + h, function(px, py)
				if px < x or py < y or px > x + w or py > y + h then return false end
				local qx, qy = math.max(x + r - px, px - (x + w - r), 0), math.max(y + r - py, py - (y + h - r), 0)
				return qx * qx + qy * qy <= r * r
			end)
		elseif kind == "quad" then
			local p = c
			fill(math.min(p[2], p[4], p[6], p[8]), math.min(p[3], p[5], p[7], p[9]), math.max(p[2], p[4], p[6], p[8]), math.max(p[3], p[5], p[7], p[9]), function(x, y)
				return inTriangle(x, y, p[2], p[3], p[4], p[5], p[6], p[7]) or inTriangle(x, y, p[2], p[3], p[6], p[7], p[8], p[9])
			end)
		elseif kind == "tri" then
			fill(math.min(c[2], c[4], c[6]), math.min(c[3], c[5], c[7]), math.max(c[2], c[4], c[6]), math.max(c[3], c[5], c[7]), function(x, y)
				return inTriangle(x, y, c[2], c[3], c[4], c[5], c[6], c[7])
			end)
		elseif kind == "circle" then
			fill(c[2] - c[4], c[3] - c[4], c[2] + c[4], c[3] + c[4], function(x, y)
				return (x - c[2]) ^ 2 + (y - c[3]) ^ 2 <= c[4] ^ 2
			end)
		end
	end
	return cells
end

local function options(mode, extra)
	local o = {
		RenderMode = mode, AutoRender = false, Input = false, Font = "Monospace", FontSize = 13, DisplaySize = Vector2.new(W, H),
		MeasureText = function(_, size, text) return (utf8.len(text) or #text) * HarnessAdvance(size) end,
	}
	if extra then
		for k, v in extra do o[k] = v end
	end
	return o
end

--------------------------------------------------------------------------------
-- Reference: the same window through DrawingImmediate
--------------------------------------------------------------------------------

local state = WidgetsState()
ImGui.Init(options("DrawingImmediate", { DrawingImmediate = MockDrawingImmediate }))
ImGui.OnFrame(function() WidgetsUI(ImGui, state) end)
for _ = 1, 3 do
	table.clear(DrawCalls)
	ImGui.Step(1 / 60, W, H)
end
local reference = table.clone(DrawCalls)
ImGui.Shutdown()
local referenceTexts = {}
for _, c in reference do
	if c[1] == "text" then table.insert(referenceTexts, c[10]) end
end

--------------------------------------------------------------------------------
-- Cesium
--------------------------------------------------------------------------------

check("ImGui.Cesium.Parent can be set before Init", pcall(function() ImGui.Cesium.Parent = other end) and ImGui.Cesium.Parent == other)
state = WidgetsState()
ImGui.Init(options("Cesium"))
check("Cesium: ImGui.RenderMode", ImGui.RenderMode == "Cesium")
local gui = ImGui.Cesium.ScreenGui
check("Cesium: the ScreenGui goes where ImGui.Cesium.Parent says", gui ~= nil and gui.Parent == other and gui.IgnoreGuiInset == true)
ImGui.OnFrame(function() WidgetsUI(ImGui, state) end)
for _ = 1, 3 do ImGui.Step(1 / 60, W, H) end

local visible, ordered, lastZ, labels = 0, true, -1, {}
local function collectLabels(frame)
	for _, child in frame.Children do
		if child.ClassName == "TextLabel" and child.Visible then table.insert(labels, child.Text) end
	end
end
for _, slot in gui.Children do
	if slot.ClassName == "Frame" and slot.Visible then
		visible += 1
		if slot.ZIndex <= lastZ then ordered = false end
		lastZ = slot.ZIndex
		collectLabels(slot)
	end
end
print(string.format("Cesium: %d slots, %d instances in total", visible, #gui.Children))
check("Cesium: slots are in strictly increasing ZIndex order", ordered and visible > 50)
check("Cesium: draws the same text as DrawingImmediate", table.concat(labels, "|") == table.concat(referenceTexts, "|"))

local before = writes
table.clear(writeLog)
for _ = 1, 10 do ImGui.Step(1 / 60, W, H) end
for key, n in writeLog do print("  repeated write", key, n) end
check(string.format("Cesium: an unchanged frame writes nothing (%d writes over 10 frames)", writes - before), writes - before == 0)

local mine, theirs = paintedBy(gui), paintedByCalls(reference)
local union, differ = 0, 0
for key, color in mine do
	union += 1
	local other = theirs[key]
	if other == nil or (other ~= color and color ~= "grad") then differ += 1 end
end
for key in theirs do
	if mine[key] == nil then
		union += 1
		differ += 1
	end
end
local fraction = differ / math.max(union, 1)
print(string.format("Cesium covers %d pixels, DrawingImmediate %d, %.2f%% differ", (function() local n = 0 for _ in mine do n += 1 end return n end)(), (function() local n = 0 for _ in theirs do n += 1 end return n end)(), fraction * 100))
check("Cesium: the instances cover the pixels DrawingImmediate draws (under 0.05% differ)", fraction < 0.0005)

ImGui.Cesium.Parent = container
check("Cesium: setting Parent moves the live ScreenGui", gui.Parent == container)
ImGui.Cesium.Parent = locked
check("Cesium: a parent the script cannot use leaves it where it is", gui.Parent == container)
local ok = pcall(function() ImGui.Cesium.Parent = 5 end)
check("Cesium: Parent must be an Instance", not ok)
ok = pcall(function() ImGui.Cesium.Other = 1 end)
check("Cesium: other fields cannot be set", not ok)

ImGui.Shutdown()
check("Cesium: Shutdown destroys the ScreenGui", gui.Destroyed == true and ImGui.RenderMode == nil)
check("Cesium: the ScreenGui is gone from ImGui.Cesium", ImGui.Cesium.ScreenGui == nil)

ImGui.Cesium.Parent = container
local okInit, err = pcall(ImGui.Init, options("cesium"))
check("Cesium: the mode name ignores case: " .. tostring(err), okInit and ImGui.RenderMode == "Cesium")
ImGui.Shutdown()

print(string.format("RESULT %d failure(s)", failures))

-- Minimal Roblox / executor stand-ins so the bundle runs under the standalone luau CLI.
--   MockDrawingImmediate  records DrawingImmediate calls into DrawCalls
--   MockDrawing           a Drawing library whose objects can be snapshotted into the same call format

local Vector2Meta = {}
Vector2 = {
	new = function(x, y)
		return setmetatable({ X = x, Y = y }, Vector2Meta)
	end,
}
Vector2Meta.__add = function(a, b)
	return Vector2.new(a.X + b.X, a.Y + b.Y)
end
Vector2Meta.__sub = function(a, b)
	return Vector2.new(a.X - b.X, a.Y - b.Y)
end
Vector2Meta.__mul = function(a, b)
	if type(a) == "number" then
		return Vector2.new(a * b.X, a * b.Y)
	elseif type(b) == "number" then
		return Vector2.new(a.X * b, a.Y * b)
	end
	return Vector2.new(a.X * b.X, a.Y * b.Y)
end
Vector2Meta.__unm = function(a)
	return Vector2.new(-a.X, -a.Y)
end

Color3 = {
	fromRGB = function(r, g, b)
		return { R = r / 255, G = g / 255, B = b / 255, r = r, g = g, b = b }
	end,
	new = function(r, g, b)
		return { R = r, G = g, B = b, r = math.floor(r * 255 + 0.5), g = math.floor(g * 255 + 0.5), b = math.floor(b * 255 + 0.5) }
	end,
}

DrawCalls = {}

MockDrawingImmediate = {
	GetPaint = function()
		return {
			Connect = function()
				return { Disconnect = function() end }
			end,
		}
	end,
	FilledRectangle = function(topLeft, size, color, opacity, rounding)
		DrawCalls[#DrawCalls + 1] = { "rect", topLeft.X, topLeft.Y, size.X, size.Y, color.r, color.g, color.b, opacity, rounding or 0 }
	end,
	FilledQuad = function(a, b, c, d, color, opacity)
		DrawCalls[#DrawCalls + 1] = { "quad", a.X, a.Y, b.X, b.Y, c.X, c.Y, d.X, d.Y, color.r, color.g, color.b, opacity }
	end,
	FilledTriangle = function(a, b, c, color, opacity)
		DrawCalls[#DrawCalls + 1] = { "tri", a.X, a.Y, b.X, b.Y, c.X, c.Y, color.r, color.g, color.b, opacity }
	end,
	FilledCircle = function(center, radius, color, numSides, opacity)
		DrawCalls[#DrawCalls + 1] = { "circle", center.X, center.Y, radius, color.r, color.g, color.b, opacity, numSides }
	end,
	Text = function(position, font, size, color, opacity, text, center)
		DrawCalls[#DrawCalls + 1] = { "text", position.X, position.Y, font, size, color.r, color.g, color.b, opacity, text }
	end,
}

-- Monospace metrics shared by every harness test and by the rasterizers
function HarnessAdvance(size)
	return math.floor(size * 0.55 + 0.5)
end

MockDrawing = { Fonts = { UI = 0, System = 1, Plex = 2, Monospace = 3 }, Objects = {}, Created = 0, Writes = 0 }

function MockDrawing.new(className)
	local zero = Vector2.new(0, 0)
	local props = {
		ClassName = className, Visible = false, ZIndex = 1, Transparency = 1, Color = Color3.fromRGB(0, 0, 0),
		Position = zero, Size = if className == "Text" then 18 else zero, Thickness = 1, Filled = false,
		PointA = zero, PointB = zero, PointC = zero, PointD = zero, Radius = 0, NumSides = 250,
		Text = "", Font = 0, Center = false, Outline = false,
	}
	local object = setmetatable({}, {
		__index = function(_, key)
			if key == "Remove" or key == "Destroy" then
				return function()
					props.Removed = true
				end
			elseif key == "TextBounds" then
				return Vector2.new((utf8.len(props.Text) or #props.Text) * HarnessAdvance(props.Size), props.Size)
			end
			return props[key]
		end,
		__newindex = function(_, key, value)
			if props.Removed then
				error("write to a removed Drawing object")
			end
			MockDrawing.Writes += 1
			props[key] = value
		end,
	})
	MockDrawing.Created += 1
	table.insert(MockDrawing.Objects, props)
	return object
end

-- Visible objects in ZIndex order, as DrawingImmediate-style calls
function MockDrawing.Snapshot()
	local visible = {}
	for _, p in MockDrawing.Objects do
		if p.Visible and not p.Removed then
			table.insert(visible, p)
		end
	end
	table.sort(visible, function(a, b)
		return a.ZIndex < b.ZIndex
	end)
	local calls = {}
	for _, p in visible do
		local c = p.Color
		local kind = p.ClassName
		if kind == "Square" then
			calls[#calls + 1] = { "rect", p.Position.X, p.Position.Y, p.Size.X, p.Size.Y, c.r, c.g, c.b, p.Transparency, 0 }
		elseif kind == "Quad" then
			calls[#calls + 1] = { "quad", p.PointA.X, p.PointA.Y, p.PointB.X, p.PointB.Y, p.PointC.X, p.PointC.Y, p.PointD.X, p.PointD.Y, c.r, c.g, c.b, p.Transparency }
		elseif kind == "Triangle" then
			calls[#calls + 1] = { "tri", p.PointA.X, p.PointA.Y, p.PointB.X, p.PointB.Y, p.PointC.X, p.PointC.Y, c.r, c.g, c.b, p.Transparency }
		elseif kind == "Circle" then
			calls[#calls + 1] = { "circle", p.Position.X, p.Position.Y, p.Radius, c.r, c.g, c.b, p.Transparency, p.NumSides }
		elseif kind == "Text" then
			calls[#calls + 1] = { "text", p.Position.X, p.Position.Y, p.Font, p.Size, c.r, c.g, c.b, p.Transparency, p.Text }
		end
	end
	return calls
end

function EncodeJson(value)
	local kind = type(value)
	if kind == "number" then
		if value ~= value or value == math.huge or value == -math.huge then
			return "0"
		end
		return string.format("%.4g", value)
	elseif kind == "string" then
		return '"' .. string.gsub(value, '[%c"\\]', function(c)
			return string.format("\\u%04x", string.byte(c))
		end) .. '"'
	elseif kind == "table" then
		local parts = {}
		for i = 1, #value do
			parts[i] = EncodeJson(value[i])
		end
		return "[" .. table.concat(parts, ",") .. "]"
	end
	return "null"
end

-- Dear ImGui for Roblox: render modes
-- Turns the draw table produced by rbx_render() (src/imgui_rbx.cpp) into primitives for one of two render modes:
--   DrawingImmediate  Potassium's immediate-mode drawing, called from a DrawingImmediate.GetPaint event
--   Drawing           the UNC Drawing library: retained objects, pooled and updated in place every frame
-- The bundle runs this chunk once; runtime.luau receives the returned table.

local band, bor, rshift, lshift = bit32.band, bit32.bor, bit32.rshift, bit32.lshift
local readu16, readu32, readf32 = buffer.readu16, buffer.readu32, buffer.readf32
local floor, min, max, abs, sqrt, huge = math.floor, math.min, math.max, math.abs, math.sqrt, math.huge
local tconcat, tclear = table.concat, table.clear
local srep, sformat, slower = string.rep, string.format, string.lower
local utf8char = utf8.char

local Renderer = {}

--------------------------------------------------------------------------------
-- Modes and fonts
--------------------------------------------------------------------------------

local ModeNames = { auto = "Auto", drawingimmediate = "DrawingImmediate", drawing = "Drawing" }

function Renderer.NormalizeMode(value)
	if value == nil then
		return "Auto"
	end
	local mode = type(value) == "string" and ModeNames[slower(value)]
	if not mode then
		error(sformat('[ImGui] unknown RenderMode %s (expected "DrawingImmediate", "Drawing" or "Auto")', tostring(value)), 3)
	end
	return mode
end

-- Drawing.Fonts indices
Renderer.FontIndices = { UI = 0, System = 1, Plex = 2, Monospace = 3 }

-- Roblox fonts closest to the Drawing fonts, to measure text when the drawing library cannot
local MeasureFontNames = { [0] = "BuilderSans", [1] = "Arial", [2] = "SourceSans", [3] = "RobotoMono" }

-- Returns the value a render mode draws text with: a Drawing font index (custom renderers accept any value).
function Renderer.ResolveFont(mode, value)
	if value == nil then
		value = "Monospace"
	end
	if type(value) == "string" then
		local index = Renderer.FontIndices[value]
		if index == nil then
			error(sformat('[ImGui] unknown font "%s" (expected "UI", "System", "Plex" or "Monospace")', value), 3)
		end
		value = index
	end
	if mode ~= "Custom" and type(value) ~= "number" then
		error("[ImGui] " .. mode .. " mode fonts are Drawing font indices (Drawing.Fonts.*) or font names", 3)
	end
	return value
end

-- Measured against the drawn text to check the advances of each font and size
local PROBE_TEXT = "The quick brown fox jumps over the lazy dog 0123456789"
local PROBE_TOLERANCE = 0.015
local PROBE_ATTEMPTS = 3

-- Glyph advances are measured with the fonts that will draw the text, so Dear ImGui's layout matches the screen.
-- Returns measureGlyph(slot, size, codepoint) and a metrics object:
--   metrics.Step()              once per frame after drawing; true when advances changed and glyphs must be measured again
--   metrics.CanMerge(slot, size) true when the advances of that font and size are known to match the drawn text
--   metrics.Info(), metrics.Destroy()
-- Drawing text objects measure synchronously in most executors, but some only update TextBounds once the text has been
-- drawn: synchronous measuring then fails and an estimate is used. So every font and size is also checked a few frames
-- later, by comparing the TextBounds of a drawn sample with the width the advances give it, and scaled to match.
function Renderer.CreateGlyphMeasurer(mode, options, fontSlots)
	local fallbackText, fallbackName
	if game ~= nil then
		local TextService = game:GetService("TextService")
		local bounds = Vector2.new(1e6, 1e6)
		fallbackName = "TextService"
		fallbackText = function(font, size, text)
			local robloxFont = if type(font) == "number" then Enum.Font[MeasureFontNames[font] or "RobotoMono"] else font
			return TextService:GetTextSize(text, size, robloxFont, bounds).X
		end
	else
		fallbackName = "Estimate"
		fallbackText = function(_, size, text)
			return (utf8.len(text) or #text) * size * 0.5
		end
	end

	local trusted = options.MeasureText ~= nil
	local measureText, source = options.MeasureText, "MeasureText"
	local drawing = options.Drawing or Drawing
	local hasDrawing = drawing ~= nil and drawing.new ~= nil
	local objects = {}
	if measureText == nil and hasDrawing then
		source = "Drawing"
		measureText = function(font, size, text)
			local object = objects[font]
			if object == nil then
				object = drawing.new("Text")
				object.Visible = false
				object.Font = font
				objects[font] = object
			end
			object.Size = size
			object.Text = text
			local width = object.TextBounds.X
			if width <= 0 and not object.Visible then
				-- Some Drawing implementations only measure visible text: keep it transparent and off-screen instead
				object.Position = Vector2.new(-100000, -100000)
				object.Transparency = 0
				object.Visible = true
				width = object.TextBounds.X
			end
			return width
		end
	elseif measureText == nil then
		measureText, source = fallbackText, fallbackName
	end

	local function AdvanceOf(measure, font, size, codepoint)
		local ok, result = pcall(function()
			local bars = measure(font, size, "||")
			return (measure(font, size, "|" .. srep(utf8char(codepoint), 32) .. "|") - bars) / 32
		end)
		if ok and type(result) == "number" and result == result and result > 0 then
			return result
		end
		return nil
	end

	local cache = {} -- key -> codepoint -> advance
	local entries = {} -- key -> { Slot, Size, Scale, Verified, Attempts, Ratio }
	local queue = {} -- entries waiting for a probe
	local measured = {} -- source name -> glyphs measured with it

	local function KeyOf(slot, size)
		return slot * 1048576 + floor(size * 64 + 0.5)
	end

	local function measureGlyph(slot, size, codepoint)
		local key = KeyOf(slot, size)
		local sizeCache = cache[key]
		if sizeCache == nil then
			sizeCache = {}
			cache[key] = sizeCache
			if entries[key] == nil then
				local entry = { Slot = slot, Size = size, Scale = 1, Verified = trusted, Attempts = 0 }
				entries[key] = entry
				if not trusted and hasDrawing then
					queue[#queue + 1] = entry
				end
			end
		end
		local advance = sizeCache[codepoint]
		if advance == nil then
			if codepoint < 32 then
				advance = -1 -- control characters: let Dear ImGui use its fallbacks
			else
				local font = fontSlots[slot]
				local name = source
				advance = AdvanceOf(measureText, font, size, codepoint)
				if advance == nil and measureText ~= fallbackText then
					name = fallbackName
					advance = AdvanceOf(fallbackText, font, size, codepoint)
				end
				if advance == nil then
					name = "Estimate"
					advance = size * 0.5
				end
				measured[name] = (measured[name] or 0) + 1
				advance *= entries[key].Scale
			end
			sizeCache[codepoint] = advance
		end
		return advance
	end

	local metrics = {}
	local frame = 0
	local probe, bars, probing = nil, nil, nil -- Drawing texts "|<sample>|" and "||", entry being checked
	local readAt, expected = 0, 0

	local function ShowProbe(entry)
		if probe == nil then
			probe, bars = drawing.new("Text"), drawing.new("Text")
		end
		for _, object in { probe, bars } do
			object.Font = fontSlots[entry.Slot]
			object.Size = entry.Size
			object.Position = Vector2.new(-100000, -100000)
			object.Transparency = 0.01
			object.Visible = true
		end
		probe.Text = "|" .. PROBE_TEXT .. "|"
		bars.Text = "||"
	end

	function metrics.Step()
		frame += 1
		if trusted or not hasDrawing then
			return false
		end
		if probing == nil then
			local entry = table.remove(queue, 1)
			if entry == nil then
				if probe ~= nil and probe.Visible then
					pcall(function()
						probe.Visible = false
						bars.Visible = false
					end)
				end
				return false
			end
			local width = 0
			for _, codepoint in utf8.codes(PROBE_TEXT) do
				width += measureGlyph(entry.Slot, entry.Size, codepoint)
			end
			if not pcall(ShowProbe, entry) then
				hasDrawing = false -- this Drawing library cannot draw the sample: keep the advances as they are
				return false
			end
			probing, expected, readAt = entry, width, frame + 2 -- read once the text has certainly been drawn
			return false
		end
		if frame < readAt then
			return false
		end

		local entry = probing
		probing = nil
		entry.Attempts += 1
		local ok, width = pcall(function()
			return probe.TextBounds.X - bars.TextBounds.X
		end)
		if not ok or type(width) ~= "number" or width ~= width or width <= 0 or expected <= 0 then
			if entry.Attempts < PROBE_ATTEMPTS then
				queue[#queue + 1] = entry -- nothing measured yet: try again
			end
			return false
		end
		local ratio = width / expected
		entry.Ratio = ratio
		if abs(ratio - 1) <= PROBE_TOLERANCE then
			entry.Verified = true
			return false
		end
		entry.Scale *= ratio
		cache[KeyOf(entry.Slot, entry.Size)] = nil
		if entry.Attempts < PROBE_ATTEMPTS then
			queue[#queue + 1] = entry -- check the corrected advances too
		end
		return true
	end

	function metrics.CanMerge(slot, size)
		if trusted then
			return true
		end
		local entry = entries[KeyOf(slot, size)]
		return entry ~= nil and entry.Verified
	end

	function metrics.Info()
		local fonts = {}
		for _, entry in entries do
			fonts[#fonts + 1] = {
				Slot = entry.Slot, Font = fontSlots[entry.Slot], Size = entry.Size, Scale = entry.Scale,
				Verified = entry.Verified, Attempts = entry.Attempts, Ratio = entry.Ratio,
			}
		end
		table.sort(fonts, function(a, b)
			return if a.Slot ~= b.Slot then a.Slot < b.Slot else a.Size < b.Size
		end)
		return { Source = source, Measured = table.clone(measured), Fonts = fonts }
	end

	function metrics.Destroy()
		for _, object in { probe, bars } do
			pcall(function()
				object:Remove()
			end)
		end
		for _, object in objects do
			pcall(function()
				object:Remove()
			end)
		end
		probe, bars, probing = nil, nil, nil
		tclear(objects)
	end

	return measureGlyph, metrics
end

--------------------------------------------------------------------------------
-- Colors (Dear ImGui packs colors as 0xAABBGGRR)
--------------------------------------------------------------------------------

local function CreateColorCache()
	local RGB = Color3.fromRGB
	local cache, size = {}, 0
	return function(rgb)
		local color = cache[rgb]
		if color == nil then
			if size >= 4096 then
				tclear(cache)
				size = 0
			end
			color = RGB(band(rgb, 0xFF), band(rshift(rgb, 8), 0xFF), band(rshift(rgb, 16), 0xFF))
			cache[rgb] = color
			size += 1
		end
		return color
	end
end

local function LerpColor(c1, c2, t)
	if c1 == c2 then
		return c1
	end
	local r1, g1, b1, a1 = band(c1, 255), band(rshift(c1, 8), 255), band(rshift(c1, 16), 255), rshift(c1, 24)
	local r2, g2, b2, a2 = band(c2, 255), band(rshift(c2, 8), 255), band(rshift(c2, 16), 255), rshift(c2, 24)
	return bor(
		floor(r1 + (r2 - r1) * t + 0.5),
		lshift(floor(g1 + (g2 - g1) * t + 0.5), 8),
		lshift(floor(b1 + (b2 - b1) * t + 0.5), 16),
		lshift(floor(a1 + (a2 - a1) * t + 0.5), 24)
	)
end

local function BilinearColor(cTL, cTR, cBR, cBL, u, v)
	return LerpColor(LerpColor(cTL, cTR, u), LerpColor(cBL, cBR, u), v)
end

--------------------------------------------------------------------------------
-- Draw data walker (shared by every mode)
--------------------------------------------------------------------------------
-- Groups Dear ImGui's triangles back into the shapes that produced them, clips them against each draw command's
-- clip rectangle and hands them to a backend:
--   backend.Rect(x0, y0, x1, y1, rgb, alpha)                                   axis-aligned, already clipped
--   backend.Polygon(xs, ys, n, rgb, alpha)                                     convex, already clipped
--   backend.Text(x, y, fontSlot, size, rgb, alpha, text, width, clipX0, clipY0, clipX1, clipY1)
--   backend.GradientRect?(x0, y0, x1, y1, colTL, colTR, colBR, colBL, alphaScale) -> true if drawn
--   backend.Circle?(cx, cy, radius, rgb, alpha, clip...) -> true if drawn
--   backend.RoundedRect?(x0, y0, x1, y1, rTL, rTR, rBR, rBL, rgb, alpha, clip...) -> true if drawn
--   backend.BeginFrame?(), backend.EndFrame?()
--   backend.ClipsText / backend.ClipsShapes: the backend clips text / circles and rounded rectangles itself
--   backend.AnchorWords: every word is drawn where Dear ImGui placed it, unless options.MeasureText is given
-- Solid geometry uses the atlas white pixel UV. Textured quads are glyphs: their atlas texel encodes the codepoint and
-- font slot (see RbxFont_FontBakedLoadGlyph); neighbouring glyphs are merged into runs of text.

local EDGE_EPSILON = 0.05

local function CornerRadius(a, b)
	if abs(a - b) > 0.5 then
		return nil
	end
	local r = (a + b) * 0.5
	return if r < 0.5 then 0 else r
end

local function OnArc(x, y, cx, cy, r)
	local dx, dy = x - cx, y - cy
	return abs(sqrt(dx * dx + dy * dy) - r) <= 0.35
end

function Renderer.CreateWalker(backend, measureGlyph, options, metrics)
	local alphaScale = min(max(options.Alpha or 1, 0), 1) / 255
	local clipsText = backend.ClipsText == true
	local clipsShapes = backend.ClipsShapes == true
	local anchorWords = backend.AnchorWords == true and options.MeasureText == nil
	local canMerge = if metrics ~= nil then metrics.CanMerge else function()
		return true
	end
	local drawRect, drawPolygon, drawText = backend.Rect, backend.Polygon, backend.Text
	local drawGradient, drawCircle, drawRounded = backend.GradientRect, backend.Circle, backend.RoundedRect
	local beginFrame, endFrame = backend.BeginFrame, backend.EndFrame
	if type(drawRect) ~= "function" or type(drawPolygon) ~= "function" or type(drawText) ~= "function" then
		error("[ImGui] a renderer needs Rect, Polygon and Text functions", 3)
	end

	local charCache = {}
	local runChars = table.create(256)
	local runActive, runInk = false, false
	local runX, runY, runSize, runSlot, runCol, runNextX, runLen = 0, 0, 0, 0, 0, 0, 0
	local clipX0, clipY0, clipX1, clipY1 = 0, 0, 0, 0

	local px, py, pc = table.create(64, 0), table.create(64, 0), table.create(64, 0)
	local qx, qy = table.create(64, 0), table.create(64, 0)

	local function FlushText()
		if not runActive then
			return
		end
		runActive = false
		if runInk then
			local alpha = rshift(runCol, 24) * alphaScale
			if alpha > 0 then
				drawText(runX, runY, runSlot, runSize, band(runCol, 0xFFFFFF), alpha, tconcat(runChars, "", 1, runLen), runNextX - runX, clipX0, clipY0, clipX1, clipY1)
			end
		end
	end

	local function AddGlyph(x, y, w, h, codepoint, slot, col)
		if runActive then
			local dx, dy, ds = x - runNextX, y - runY, h - runSize
			if col ~= runCol or slot ~= runSlot or dx < -0.75 or dy > 0.5 or dy < -0.5 or ds > 0.01 or ds < -0.01 then
				FlushText()
			elseif dx > 0.75 and (anchorWords or not canMerge(slot, h)) then
				-- A gap between words. Unless the advances are known to match the drawn font, every word starts where Dear
				-- ImGui placed it, so text wider than measured cannot run past the wrap width or into the next item.
				FlushText()
			elseif dx > 0.75 then
				-- Dear ImGui emits no quad for blank glyphs: bridge gaps that are a whole number of spaces
				local space = measureGlyph(slot, h, 32)
				local count = if space > 0 then floor(dx / space + 0.5) else 0
				local drift = dx - count * space
				if count >= 1 and count <= 8 and drift <= 0.75 and drift >= -0.75 then
					for _ = 1, count do
						runLen += 1
						runChars[runLen] = " "
					end
				else
					FlushText()
				end
			end
		end
		if not runActive then
			if codepoint == 32 then
				return
			end
			runActive, runInk = true, false
			runX, runY, runSize, runSlot, runCol, runLen = x, y, h, slot, col, 0
		end
		local ch = charCache[codepoint]
		if ch == nil then
			ch = utf8char(codepoint)
			charCache[codepoint] = ch
		end
		runLen += 1
		runChars[runLen] = ch
		if codepoint ~= 32 then
			runInk = true
		end
		runNextX = x + w
	end

	local function EmitRect(x0, y0, x1, y1, col)
		local alpha = rshift(col, 24) * alphaScale
		if alpha <= 0 then
			return
		end
		if x0 < clipX0 then x0 = clipX0 end
		if y0 < clipY0 then y0 = clipY0 end
		if x1 > clipX1 then x1 = clipX1 end
		if y1 > clipY1 then y1 = clipY1 end
		if x1 <= x0 or y1 <= y0 then
			return
		end
		FlushText()
		drawRect(x0, y0, x1, y1, band(col, 0xFFFFFF), alpha)
	end

	-- Per-vertex colors (color pickers, alpha bars): exact gradients where the backend supports them, else solid cells
	local function EmitGradient(x0, y0, x1, y1, cTL, cTR, cBR, cBL)
		local w, h = x1 - x0, y1 - y0
		if w <= 0 or h <= 0 then
			return
		end
		local nx0, ny0, nx1, ny1 = max(x0, clipX0), max(y0, clipY0), min(x1, clipX1), min(y1, clipY1)
		if nx1 <= nx0 or ny1 <= ny0 then
			return
		end
		if nx0 ~= x0 or ny0 ~= y0 or nx1 ~= x1 or ny1 ~= y1 then
			local u0, v0, u1, v1 = (nx0 - x0) / w, (ny0 - y0) / h, (nx1 - x0) / w, (ny1 - y0) / h
			cTL, cTR, cBR, cBL = BilinearColor(cTL, cTR, cBR, cBL, u0, v0), BilinearColor(cTL, cTR, cBR, cBL, u1, v0),
				BilinearColor(cTL, cTR, cBR, cBL, u1, v1), BilinearColor(cTL, cTR, cBR, cBL, u0, v1)
			x0, y0, x1, y1 = nx0, ny0, nx1, ny1
		end
		FlushText()
		if drawGradient ~= nil and drawGradient(x0, y0, x1, y1, cTL, cTR, cBR, cBL, alphaScale) then
			return
		end
		local nx, ny = 1, 1
		if cTL ~= cTR or cBL ~= cBR then
			nx = max(1, min(32, floor((x1 - x0) / 4)))
		end
		if cTL ~= cBL or cTR ~= cBR then
			ny = max(1, min(32, floor((y1 - y0) / 4)))
		end
		local cw, ch = (x1 - x0) / nx, (y1 - y0) / ny
		for j = 0, ny - 1 do
			local v = (j + 0.5) / ny
			local left, right = LerpColor(cTL, cBL, v), LerpColor(cTR, cBR, v)
			local ry0 = y0 + ch * j
			for i = 0, nx - 1 do
				local col = LerpColor(left, right, (i + 0.5) / nx)
				local alpha = rshift(col, 24) * alphaScale
				if alpha > 0 then
					drawRect(x0 + cw * i, ry0, x0 + cw * (i + 1), ry0 + ch, band(col, 0xFFFFFF), alpha)
				end
			end
		end
	end

	-- Sutherland-Hodgman against the clip rectangle (the shapes are convex, so the result is too)
	local function ClipPolygon(n)
		local inX, inY, outX, outY = px, py, qx, qy
		for edge = 1, 4 do
			local m = 0
			local prevX, prevY = inX[n], inY[n]
			local prevD = if edge == 1 then prevX - clipX0 elseif edge == 2 then clipX1 - prevX elseif edge == 3 then prevY - clipY0 else clipY1 - prevY
			for i = 1, n do
				local x, y = inX[i], inY[i]
				local d = if edge == 1 then x - clipX0 elseif edge == 2 then clipX1 - x elseif edge == 3 then y - clipY0 else clipY1 - y
				if (d >= 0) ~= (prevD >= 0) then
					local t = prevD / (prevD - d)
					m += 1
					outX[m] = prevX + (x - prevX) * t
					outY[m] = prevY + (y - prevY) * t
				end
				if d >= 0 then
					m += 1
					outX[m] = x
					outY[m] = y
				end
				prevX, prevY, prevD = x, y, d
			end
			n = m
			if n < 3 then
				return 0, inX, inY
			end
			inX, outX = outX, inX
			inY, outY = outY, inY
		end
		return n, inX, inY
	end

	-- AddCircleFilled / AddNgonFilled: every vertex at the same distance from the centroid, and a square bounding box
	-- whose half side is that distance. The box test matters: a long thin rounded rectangle (a scrollbar grab) also has
	-- every vertex at one distance from its center, bunched at its two ends.
	local function DetectCircle(n, minX, minY, maxX, maxY)
		local w, h = maxX - minX, maxY - minY
		local half = (w + h) * 0.25
		if half < 1 or abs(w - h) > max(1, half * 0.2) then
			return false, 0, 0, 0
		end
		local sx, sy = 0, 0
		for i = 1, n do
			sx += px[i]
			sy += py[i]
		end
		local cx, cy = sx / n, sy / n
		local sum, dmin, dmax = 0, huge, 0
		for i = 1, n do
			local dx, dy = px[i] - cx, py[i] - cy
			local d = sqrt(dx * dx + dy * dy)
			sum += d
			if d < dmin then dmin = d end
			if d > dmax then dmax = d end
		end
		local r = sum / n
		local tolerance = max(0.3, r * 0.02)
		if r >= 1 and dmax - r <= tolerance and r - dmin <= tolerance and abs(half - r) <= max(1, r * 0.1) then
			return true, cx, cy, r
		end
		return false, 0, 0, 0
	end

	-- AddRectFilled with rounding (PathRect): straight edges plus quarter arcs of one radius at the rounded corners
	local function DetectRoundedRect(n, minX, minY, maxX, maxY)
		local w, h = maxX - minX, maxY - minY
		if w < 1 or h < 1 then
			return false, 0, 0, 0, 0
		end
		local tlX, tlY, trX, trY, brX, brY, blX, blY = w, h, w, h, w, h, w, h
		for i = 1, n do
			local x, y = px[i], py[i]
			local left, right, top, bottom = x - minX, maxX - x, y - minY, maxY - y
			if top <= EDGE_EPSILON then
				if left < tlX then tlX = left end
				if right < trX then trX = right end
			end
			if bottom <= EDGE_EPSILON then
				if left < blX then blX = left end
				if right < brX then brX = right end
			end
			if left <= EDGE_EPSILON then
				if top < tlY then tlY = top end
				if bottom < blY then blY = bottom end
			end
			if right <= EDGE_EPSILON then
				if top < trY then trY = top end
				if bottom < brY then brY = bottom end
			end
		end
		local rtl, rtr, rbr, rbl = CornerRadius(tlX, tlY), CornerRadius(trX, trY), CornerRadius(brX, brY), CornerRadius(blX, blY)
		if rtl == nil or rtr == nil or rbr == nil or rbl == nil or rtl + rtr + rbr + rbl == 0 then
			return false, 0, 0, 0, 0
		end
		for i = 1, n do
			local x, y = px[i], py[i]
			local ok
			if rtl > 0 and x < minX + rtl - EDGE_EPSILON and y < minY + rtl - EDGE_EPSILON then
				ok = OnArc(x, y, minX + rtl, minY + rtl, rtl)
			elseif rtr > 0 and x > maxX - rtr + EDGE_EPSILON and y < minY + rtr - EDGE_EPSILON then
				ok = OnArc(x, y, maxX - rtr, minY + rtr, rtr)
			elseif rbr > 0 and x > maxX - rbr + EDGE_EPSILON and y > maxY - rbr + EDGE_EPSILON then
				ok = OnArc(x, y, maxX - rbr, maxY - rbr, rbr)
			elseif rbl > 0 and x < minX + rbl - EDGE_EPSILON and y > maxY - rbl + EDGE_EPSILON then
				ok = OnArc(x, y, minX + rbl, maxY - rbl, rbl)
			else
				ok = x - minX <= EDGE_EPSILON or maxX - x <= EDGE_EPSILON or y - minY <= EDGE_EPSILON or maxY - y <= EDGE_EPSILON
			end
			if not ok then
				return false, 0, 0, 0, 0
			end
		end
		return true, rtl, rtr, rbr, rbl
	end

	-- px/py hold the n vertices of a convex fan; pc their colors when they are not all `col`
	local function EmitPolygon(n, col, uniform)
		local minX, minY, maxX, maxY = px[1], py[1], px[1], py[1]
		for i = 2, n do
			local x, y = px[i], py[i]
			if x < minX then minX = x elseif x > maxX then maxX = x end
			if y < minY then minY = y elseif y > maxY then maxY = y end
		end
		if maxX <= clipX0 or minX >= clipX1 or maxY <= clipY0 or minY >= clipY1 then
			return
		end

		if n == 4 then
			local ax, ay, bx, by, cx, cy, dx, dy = px[1], py[1], px[2], py[2], px[3], py[3], px[4], py[4]
			if (ay == by and bx == cx and cy == dy and dx == ax) or (ax == bx and by == cy and cx == dx and dy == ay) then
				if uniform then
					EmitRect(minX, minY, maxX, maxY, col)
				else
					local cTL, cTR, cBR, cBL
					for k = 1, 4 do
						local x, y, c = px[k], py[k], pc[k]
						if y == minY then
							if x == minX then cTL = c else cTR = c end
						elseif x == minX then
							cBL = c
						else
							cBR = c
						end
					end
					if cTL and cTR and cBR and cBL then
						EmitGradient(minX, minY, maxX, maxY, cTL, cTR, cBR, cBL)
					end
				end
				return
			end
		end

		if not uniform then
			local r, g, b, a = 0, 0, 0, 0
			for k = 1, n do
				local c = pc[k]
				r += band(c, 255)
				g += band(rshift(c, 8), 255)
				b += band(rshift(c, 16), 255)
				a += rshift(c, 24)
			end
			col = bor(floor(r / n + 0.5), lshift(floor(g / n + 0.5), 8), lshift(floor(b / n + 0.5), 16), lshift(floor(a / n + 0.5), 24))
		end
		local alpha = rshift(col, 24) * alphaScale
		if alpha <= 0 then
			return
		end
		local rgb = band(col, 0xFFFFFF)
		local inside = minX >= clipX0 and maxX <= clipX1 and minY >= clipY0 and maxY <= clipY1

		if n >= 6 and (inside or clipsShapes) then
			if drawCircle ~= nil and n >= 8 then
				local isCircle, cx, cy, r = DetectCircle(n, minX, minY, maxX, maxY)
				if isCircle then
					FlushText()
					if drawCircle(cx, cy, r, rgb, alpha, clipX0, clipY0, clipX1, clipY1) then
						return
					end
				end
			end
			if drawRounded ~= nil then
				local isRounded, rtl, rtr, rbr, rbl = DetectRoundedRect(n, minX, minY, maxX, maxY)
				if isRounded then
					FlushText()
					if drawRounded(minX, minY, maxX, maxY, rtl, rtr, rbr, rbl, rgb, alpha, clipX0, clipY0, clipX1, clipY1) then
						return
					end
				end
			end
		end

		FlushText()
		if inside then
			drawPolygon(px, py, n, rgb, alpha)
		else
			local m, ox, oy = ClipPolygon(n)
			if m >= 3 then
				drawPolygon(ox, oy, m, rgb, alpha)
			end
		end
	end

	return function(mem, tablePtr)
		local commandCount = readu32(mem, tablePtr)
		local whiteU = readf32(mem, tablePtr + 4)
		local whiteV = readf32(mem, tablePtr + 8)
		local record = tablePtr + 24
		runActive = false
		if beginFrame ~= nil then
			beginFrame()
		end

		for _ = 1, commandCount do
			local vtxBase = readu32(mem, record)
			local idxBase = readu32(mem, record + 4)
			local elemCount = readu32(mem, record + 8)
			local pixels = readu32(mem, record + 28)
			local texW = readu32(mem, record + 32)
			local texH = readu32(mem, record + 36)
			FlushText()
			clipX0 = readf32(mem, record + 12)
			clipY0 = readf32(mem, record + 16)
			clipX1 = readf32(mem, record + 20)
			clipY1 = readf32(mem, record + 24)
			record += 40
			if clipX1 <= clipX0 or clipY1 <= clipY0 then
				continue
			end

			local i = 0
			while i + 3 <= elemCount do
				local ip = idxBase + i * 2
				local ia = readu16(mem, ip)
				local pa = vtxBase + ia * 20
				local ua, va = readf32(mem, pa + 8), readf32(mem, pa + 12)

				if pixels ~= 0 and (ua ~= whiteU or va ~= whiteV) then
					local ic = readu16(mem, ip + 4)
					if i + 6 <= elemCount and readu16(mem, ip + 6) == ia and readu16(mem, ip + 8) == ic then
						local pcAddr = vtxBase + ic * 20
						local ax, ay = readf32(mem, pa), readf32(mem, pa + 4)
						local cx, cy = readf32(mem, pcAddr), readf32(mem, pcAddr + 4)
						local uc, vc = readf32(mem, pcAddr + 8), readf32(mem, pcAddr + 12)
						local colA = readu32(mem, pa + 16)
						local tx = floor((ua + uc) * 0.5 * texW)
						local ty = floor((va + vc) * 0.5 * texH)
						local texel = 0
						if tx >= 0 and ty >= 0 and tx < texW and ty < texH then
							texel = readu32(mem, pixels + (ty * texW + tx) * 4)
						end
						if rshift(texel, 24) == 0xFE then
							-- Glyph: rebuild the unclipped quad from its UVs (a glyph texel spans exactly one pixel)
							local fracU = (uc - ua) * texW
							local fracV = (vc - va) * texH
							if fracU >= 0.5 and fracV >= 0.5 then
								local w = (cx - ax) / fracU
								local h = (cy - ay) / fracV
								local gx = ax - (ua * texW - tx) * w
								local gy = ay - (va * texH - ty) * h
								local visibleW = min(gx + w, clipX1) - max(gx, clipX0)
								local visibleH = min(gy + h, clipY1) - max(gy, clipY0)
								local accept
								if clipsText then
									accept = visibleH > 0 and (visibleW > 0 or (w <= 0 and gx >= clipX0 and gx <= clipX1))
								else
									accept = visibleH >= h * 0.5 and (visibleW >= w * 0.5 or (w <= 0 and gx >= clipX0 and gx <= clipX1))
								end
								if accept then
									AddGlyph(gx, gy, w, h, band(texel, 0x1FFFFF), rshift(texel, 21) % 8, colA)
								else
									FlushText()
								end
							else
								FlushText()
							end
						else
							-- User texture (ImGui::Image): no mode can sample it, draw the tinted bounds
							EmitRect(min(ax, cx), min(ay, cy), max(ax, cx), max(ay, cy), colA)
						end
						i += 6
					else
						i += 3
					end
				else
					-- Solid fan (a, b, c) (a, c, d) (a, d, e) ...: rectangles, lines, circles, rounded rectangles, arrows
					local ib, ic = readu16(mem, ip + 2), readu16(mem, ip + 4)
					local pb, pcAddr = vtxBase + ib * 20, vtxBase + ic * 20
					local colA = readu32(mem, pa + 16)
					local colB, colC = readu32(mem, pb + 16), readu32(mem, pcAddr + 16)
					local ax, ay = readf32(mem, pa), readf32(mem, pa + 4)
					local bx, by = readf32(mem, pb), readf32(mem, pb + 4)
					local cx, cy = readf32(mem, pcAddr), readf32(mem, pcAddr + 4)
					local j = i + 3
					local jp = idxBase + j * 2
					if j + 3 <= elemCount and readu16(mem, jp) == ia and readu16(mem, jp + 2) == ic
						and (j + 6 > elemCount or readu16(mem, jp + 6) ~= ia) then
						-- Fast path for a quad no further triangle continues: rectangles, borders, line segments
						local pd = vtxBase + readu16(mem, jp + 4) * 20
						local dx, dy = readf32(mem, pd), readf32(mem, pd + 4)
						local colD = readu32(mem, pd + 16)
						i = j + 3
						local uniform = colB == colA and colC == colA and colD == colA
						if uniform and ((ay == by and bx == cx and cy == dy and dx == ax) or (ax == bx and by == cy and cx == dx and dy == ay)) then
							if ax < cx then
								if ay < cy then
									EmitRect(ax, ay, cx, cy, colA)
								else
									EmitRect(ax, cy, cx, ay, colA)
								end
							elseif ay < cy then
								EmitRect(cx, ay, ax, cy, colA)
							else
								EmitRect(cx, cy, ax, ay, colA)
							end
						else
							px[1], py[1], px[2], py[2], px[3], py[3], px[4], py[4] = ax, ay, bx, by, cx, cy, dx, dy
							if not uniform then
								pc[1], pc[2], pc[3], pc[4] = colA, colB, colC, colD
							end
							EmitPolygon(4, colA, uniform)
						end
						continue
					end
					px[1], py[1], px[2], py[2], px[3], py[3] = ax, ay, bx, by, cx, cy
					local uniform = colB == colA and colC == colA
					if not uniform then
						pc[1], pc[2], pc[3] = colA, colB, colC
					end
					local n, last = 3, ic
					while j + 3 <= elemCount do
						local jp = idxBase + j * 2
						if readu16(mem, jp) ~= ia or readu16(mem, jp + 2) ~= last then
							break
						end
						local id = readu16(mem, jp + 4)
						local pd = vtxBase + id * 20
						n += 1
						px[n], py[n] = readf32(mem, pd), readf32(mem, pd + 4)
						local colD = readu32(mem, pd + 16)
						if uniform and colD ~= colA then
							uniform = false
							for k = 1, n - 1 do
								pc[k] = colA
							end
						end
						if not uniform then
							pc[n] = colD
						end
						last = id
						j += 3
					end
					i = j
					EmitPolygon(n, colA, uniform)
				end
			end
		end
		FlushText()
		if endFrame ~= nil then
			endFrame()
		end
	end
end

--------------------------------------------------------------------------------
-- DrawingImmediate (Potassium)
--------------------------------------------------------------------------------

function Renderer.DrawingImmediate(lib, fontSlots)
	local FilledRectangle, FilledQuad, FilledTriangle, FilledCircle, DrawText =
		lib.FilledRectangle, lib.FilledQuad, lib.FilledTriangle, lib.FilledCircle, lib.Text
	if FilledRectangle == nil or FilledQuad == nil or FilledTriangle == nil or DrawText == nil then
		error("[ImGui] the DrawingImmediate library is missing FilledRectangle, FilledQuad, FilledTriangle or Text", 3)
	end
	local V2 = Vector2.new
	local Color = CreateColorCache()
	local backend = {}
	-- The advances are checked against Drawing text objects, which need not match DrawingImmediate's own text
	backend.AnchorWords = true

	function backend.Rect(x0, y0, x1, y1, rgb, alpha)
		FilledRectangle(V2(x0, y0), V2(x1 - x0, y1 - y0), Color(rgb), alpha, 0)
	end

	function backend.Polygon(xs, ys, n, rgb, alpha)
		local color = Color(rgb)
		local origin = V2(xs[1], ys[1])
		local i = 2
		while i + 2 <= n do
			FilledQuad(origin, V2(xs[i], ys[i]), V2(xs[i + 1], ys[i + 1]), V2(xs[i + 2], ys[i + 2]), color, alpha)
			i += 2
		end
		if i + 1 == n then
			FilledTriangle(origin, V2(xs[i], ys[i]), V2(xs[i + 1], ys[i + 1]), color, alpha)
		end
	end

	if FilledCircle ~= nil then
		function backend.Circle(cx, cy, r, rgb, alpha)
			FilledCircle(V2(cx, cy), r, Color(rgb), max(12, min(64, floor(r * 2))), alpha)
			return true
		end
	end

	function backend.RoundedRect(x0, y0, x1, y1, rtl, rtr, rbr, rbl, rgb, alpha)
		if rtl ~= rtr or rtr ~= rbr or rbr ~= rbl then
			return false -- DrawingImmediate rounds all four corners or none
		end
		FilledRectangle(V2(x0, y0), V2(x1 - x0, y1 - y0), Color(rgb), alpha, rtl)
		return true
	end

	function backend.Text(x, y, slot, size, rgb, alpha, text)
		DrawText(V2(x, y), fontSlots[slot], size, Color(rgb), alpha, text, false)
	end

	return backend
end

--------------------------------------------------------------------------------
-- Drawing (UNC Drawing library)
--------------------------------------------------------------------------------

function Renderer.Drawing(lib, fontSlots, options)
	local new = lib.new
	local V2 = Vector2.new
	local Color = CreateColorCache()
	local baseZ = options.ZIndex or 1
	local order = 0
	local pools = {}
	local created = {}

	local function NewPool(className, filled)
		local pool = { items = {}, used = 0, className = className, filled = filled }
		pools[#pools + 1] = pool
		return pool
	end

	-- Objects are reused frame to frame; every property remembers its last value so unchanged UI costs nothing
	local function Take(pool)
		local used = pool.used + 1
		pool.used = used
		local item = pool.items[used]
		if item == nil then
			local object = new(pool.className)
			if pool.filled then
				object.Filled = true
				object.Thickness = 1
			else
				object.Center = false
				object.Outline = false
			end
			created[#created + 1] = object
			item = { object = object }
			pool.items[used] = item
		end
		order += 1
		local object = item.object
		local z = baseZ + order
		if item.z ~= z then
			object.ZIndex = z
			item.z = z
		end
		if not item.visible then
			object.Visible = true
			item.visible = true
		end
		return item
	end

	local function Paint(item, rgb, alpha)
		if item.rgb ~= rgb then
			item.object.Color = Color(rgb)
			item.rgb = rgb
		end
		if item.alpha ~= alpha then
			item.object.Transparency = alpha
			item.alpha = alpha
		end
	end

	local squares = NewPool("Square", true)
	local triangles = NewPool("Triangle", true)
	local quads = NewPool("Quad", true)
	local circles = NewPool("Circle", true)
	local texts = NewPool("Text", false)

	local function Triangle(ax, ay, bx, by, cx, cy, rgb, alpha)
		local item = Take(triangles)
		local object = item.object
		if item.ax ~= ax or item.ay ~= ay then
			object.PointA = V2(ax, ay)
			item.ax, item.ay = ax, ay
		end
		if item.bx ~= bx or item.by ~= by then
			object.PointB = V2(bx, by)
			item.bx, item.by = bx, by
		end
		if item.cx ~= cx or item.cy ~= cy then
			object.PointC = V2(cx, cy)
			item.cx, item.cy = cx, cy
		end
		Paint(item, rgb, alpha)
	end

	local function Quad(ax, ay, bx, by, cx, cy, dx, dy, rgb, alpha)
		local item = Take(quads)
		local object = item.object
		if item.ax ~= ax or item.ay ~= ay then
			object.PointA = V2(ax, ay)
			item.ax, item.ay = ax, ay
		end
		if item.bx ~= bx or item.by ~= by then
			object.PointB = V2(bx, by)
			item.bx, item.by = bx, by
		end
		if item.cx ~= cx or item.cy ~= cy then
			object.PointC = V2(cx, cy)
			item.cx, item.cy = cx, cy
		end
		if item.dx ~= dx or item.dy ~= dy then
			object.PointD = V2(dx, dy)
			item.dx, item.dy = dx, dy
		end
		Paint(item, rgb, alpha)
	end

	local backend = {}

	function backend.BeginFrame()
		order = 0
		for _, pool in pools do
			pool.used = 0
		end
	end

	function backend.EndFrame()
		for _, pool in pools do
			local items = pool.items
			for i = pool.used + 1, #items do
				local item = items[i]
				if item.visible then
					item.object.Visible = false
					item.visible = false
				end
			end
		end
	end

	function backend.Rect(x0, y0, x1, y1, rgb, alpha)
		local item = Take(squares)
		local object = item.object
		if item.x ~= x0 or item.y ~= y0 then
			object.Position = V2(x0, y0)
			item.x, item.y = x0, y0
		end
		local w, h = x1 - x0, y1 - y0
		if item.w ~= w or item.h ~= h then
			object.Size = V2(w, h)
			item.w, item.h = w, h
		end
		Paint(item, rgb, alpha)
	end

	function backend.Polygon(xs, ys, n, rgb, alpha)
		local ox, oy = xs[1], ys[1]
		local i = 2
		while i + 2 <= n do
			Quad(ox, oy, xs[i], ys[i], xs[i + 1], ys[i + 1], xs[i + 2], ys[i + 2], rgb, alpha)
			i += 2
		end
		if i + 1 == n then
			Triangle(ox, oy, xs[i], ys[i], xs[i + 1], ys[i + 1], rgb, alpha)
		end
	end

	function backend.Circle(cx, cy, r, rgb, alpha)
		local item = Take(circles)
		local object = item.object
		if item.x ~= cx or item.y ~= cy then
			object.Position = V2(cx, cy)
			item.x, item.y = cx, cy
		end
		if item.r ~= r then
			object.Radius = r
			object.NumSides = max(12, min(64, floor(r * 2)))
			item.r = r
		end
		Paint(item, rgb, alpha)
		return true
	end

	function backend.Text(x, y, slot, size, rgb, alpha, text)
		local item = Take(texts)
		local object = item.object
		local font = fontSlots[slot]
		if item.font ~= font then
			object.Font = font
			item.font = font
		end
		if item.size ~= size then
			object.Size = size
			item.size = size
		end
		if item.x ~= x or item.y ~= y then
			object.Position = V2(x, y)
			item.x, item.y = x, y
		end
		if item.text ~= text then
			object.Text = text
			item.text = text
		end
		Paint(item, rgb, alpha)
	end

	function backend.Destroy()
		for _, object in created do
			pcall(function()
				object:Remove()
			end)
		end
		tclear(created)
		tclear(pools)
	end

	return backend
end

return Renderer

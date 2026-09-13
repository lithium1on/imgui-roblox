-- Text drawn with a font wider than the advances Dear ImGui measured must stay inside its window.
-- Simulates an executor whose Drawing text objects only update TextBounds once they have been drawn: measuring on the spot
-- fails, so the advances start as an estimate (0.5 * size) while the font is 20% wider (0.6 * size). Checks that
-- DrawingImmediate draws every word where Dear ImGui placed it, that the delayed probe corrects the advances, that
-- Drawing mode merges words back into lines once they are verified, and that Shutdown removes the probe objects.
local ImGui = ImGuiBundle
local W, H = 900, 700
local ADVANCE = 0.6
local failures = 0

local function check(name, ok)
	print((if ok then "PASS " else "FAIL ") .. name)
	if not ok then
		failures += 1
	end
end

local function LazyDrawing()
	local library = { Objects = {} }
	function library.new(className)
		local props = {
			ClassName = className, Visible = false, Text = "", Size = 18, Font = 0, Transparency = 1, ZIndex = 1,
			Position = Vector2.new(0, 0), Color = Color3.fromRGB(0, 0, 0), Bounds = Vector2.new(0, 0),
		}
		table.insert(library.Objects, props)
		return setmetatable({}, {
			__index = function(_, key)
				if key == "TextBounds" then
					return props.Bounds
				elseif key == "Remove" or key == "Destroy" then
					return function()
						props.Removed = true
					end
				end
				return props[key]
			end,
			__newindex = function(_, key, value)
				props[key] = value
			end,
		})
	end
	-- What the executor does when it draws a frame: text is laid out here, not when properties change
	function library.Render()
		for _, props in library.Objects do
			if props.ClassName == "Text" and props.Visible and not props.Removed then
				props.Bounds = Vector2.new((utf8.len(props.Text) or #props.Text) * ADVANCE * props.Size, props.Size)
			end
		end
	end
	return library
end

local PARAGRAPH = "Sections below are demonstrating many aspects of the library. The Tools menu above gives access to: "
	.. "About Box, Style Editor, and Metrics/Debugger (general purpose Dear ImGui debugging tool)."

local windowRight, windowBottom = 0, 0
local measuredWidth = 0
local function UI()
	ImGui.SetNextWindowPos(Vector2.new(20, 20), ImGui.Cond.Always)
	ImGui.SetNextWindowSize(Vector2.new(360, 420), ImGui.Cond.Always)
	if ImGui.Begin("Wrapped text") then
		ImGui.TextWrapped(PARAGRAPH)
		ImGui.BulletText("Web demo (w/ source code browser):")
		ImGui.SameLine()
		ImGui.Text("https://pthom.github.io")
		measuredWidth = ImGui.CalcTextSize("abcd").X
		local pos, size = ImGui.GetWindowPos(), ImGui.GetWindowSize()
		windowRight, windowBottom = pos.X + size.X, pos.Y + size.Y
	end
	ImGui.End()
end

-- Text as the executor font draws it: { x0, x1, y, text }, sorted by line then x
local function DrawnText(calls)
	local texts = {}
	for _, call in calls do
		if call[1] == "text" and call[2] >= 0 then
			table.insert(texts, { call[2], call[2] + (utf8.len(call[10]) or #call[10]) * ADVANCE * call[5], call[3], call[10] })
		end
	end
	table.sort(texts, function(a, b)
		return if a[3] ~= b[3] then a[3] < b[3] else a[1] < b[1]
	end)
	return texts
end

local function Overflows(texts)
	local outside, overlaps = 0, 0
	for i, text in texts do
		if text[2] > windowRight + 0.5 then
			outside += 1
		end
		local nextText = texts[i + 1]
		if nextText and nextText[3] == text[3] and text[2] > nextText[1] + 0.5 then
			overlaps += 1
		end
	end
	return outside, overlaps
end

local function run(mode)
	local drawing = LazyDrawing()
	local options = { RenderMode = mode, AutoRender = false, Input = false, Font = "Monospace", FontSize = 13, Drawing = drawing, DisplaySize = Vector2.new(W, H) }
	if mode == "DrawingImmediate" then
		options.DrawingImmediate = MockDrawingImmediate
	end
	ImGui.Init(options)
	ImGui.OnFrame(UI)

	local function frame()
		table.clear(DrawCalls)
		ImGui.Step(1 / 60, W, H)
		drawing.Render()
	end
	local function snapshot()
		if mode == "DrawingImmediate" then
			return DrawCalls
		end
		local calls = {}
		for _, props in drawing.Objects do
			if props.ClassName == "Text" and props.Visible and not props.Removed and props.Transparency > 0.5 then
				table.insert(calls, { "text", props.Position.X, props.Position.Y, props.Font, props.Size, 0, 0, 0, 1, props.Text })
			end
		end
		return calls
	end

	frame()
	frame()
	local before = DrawnText(snapshot())
	local merged = 0
	for _, text in before do
		if string.find(text[4], " ", 1, true) then
			merged += 1
		end
	end
	check(string.format("%s: unverified metrics draw one call per word (%d of %d calls contain spaces)", mode, merged, #before), merged == 0)
	local beforeOutside, beforeOverlaps = Overflows(before)
	print(string.format("%s: before correction, %d words past the window edge, %d overlaps", mode, beforeOutside, beforeOverlaps))

	for _ = 1, 12 do
		frame()
	end
	local info = ImGui.GetTextMetricsInfo()
	local font = info.Fonts[1]
	check(string.format("%s: text measured with %s, corrected by %.3f (verified %s after %d probes)", mode, info.Source, font and font.Scale or 0,
		tostring(font and font.Verified), font and font.Attempts or 0),
		info.Source == "Drawing" and font ~= nil and math.abs(font.Scale - ADVANCE / 0.5) < 1e-6 and font.Verified == true)
	check(string.format("%s: advances follow the drawn font (CalcTextSize(\"abcd\") = %.1f, want 32)", mode, measuredWidth), measuredWidth == 32)

	local after = DrawnText(snapshot())
	local outside, overlaps = Overflows(after)
	check(string.format("%s: no text past the window edge (%d) and no overlapping text (%d)", mode, outside, overlaps), outside == 0 and overlaps == 0)
	local words = 0
	for _, text in after do
		if string.find(text[4], " ", 1, true) then
			words += 1
		end
	end
	if mode == "Drawing" then
		check(string.format("Drawing: verified metrics merge words into lines again (%d runs with spaces)", words), words > 0)
	else
		check(string.format("DrawingImmediate: words stay anchored even once verified (%d runs with spaces)", words), words == 0)
	end

	ImGui.Shutdown()
	local left = 0
	for _, props in drawing.Objects do
		if not props.Removed then
			left += 1
		end
	end
	check(string.format("%s: Shutdown removes the measuring and probe objects (%d left)", mode, left), left == 0)
	return after
end

local immediate = run("DrawingImmediate")
run("Drawing")

print(string.format("RESULT %d failure(s)", failures))
print("JSON:" .. EncodeJson({ "wrapped text after correction, DrawingImmediate", immediate }))

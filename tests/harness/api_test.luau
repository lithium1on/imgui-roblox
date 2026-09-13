-- Exercises the generated Luau API and the input path headlessly: builds a window with common widgets,
-- simulates mouse/keyboard input and checks the resulting values.
local ImGui = ImGuiBundle
local W, H = 1280, 800

ImGui.Init({
	Renderer = MockDrawingImmediate,
	AutoRender = false,
	Input = false,
	Font = 3,
	FontSize = 13,
	DisplaySize = Vector2.new(W, H),
	MeasureText = function(_, size, text)
		return (utf8.len(text) or #text) * math.floor(size * 0.55 + 0.5)
	end,
})

local failures = 0
local function check(name, ok)
	print((if ok then "PASS " else "FAIL ") .. name)
	if not ok then
		failures += 1
	end
end

local state = {
	clicks = 0,
	checked = false,
	slider = 0.5,
	text = "hello",
	color = { 1, 0.5, 0.25, 1 },
	combo = 0,
	drag = { 1, 2, 3 },
	open = true,
}
local rects = {}
local frame = 0
local hsv = {}
local styleInfo = {}

ImGui.OnFrame(function()
	ImGui.SetNextWindowPos(Vector2.new(40, 40), ImGui.Cond.Always)
	ImGui.SetNextWindowSize(Vector2.new(460, 560), ImGui.Cond.Always)
	local visible
	visible, state.open = ImGui.Begin("Luau API test", state.open)
	if visible then
		ImGui.Text("Dear ImGui %s - frame %d, clicks %d", ImGui.GetVersion(), frame, state.clicks)
		if ImGui.Button("Click me") then
			state.clicks += 1
		end
		rects.button = { ImGui.GetItemRectMin(), ImGui.GetItemRectMax() }

		local _
		_, state.checked = ImGui.Checkbox("Checkbox", state.checked)
		rects.checkbox = { ImGui.GetItemRectMin(), ImGui.GetItemRectMax() }

		rects.sliderWidth = ImGui.CalcItemWidth()
		_, state.slider = ImGui.SliderFloat("Slider", state.slider, 0, 1)
		rects.slider = { ImGui.GetItemRectMin(), ImGui.GetItemRectMax() }

		_, state.text = ImGui.InputText("Input", state.text)
		rects.input = { ImGui.GetItemRectMin(), ImGui.GetItemRectMax() }

		_, state.color = ImGui.ColorEdit4("Color", state.color)
		_, state.combo = ImGui.Combo("Combo", state.combo, { "Apple", "Banana", "Cherry" })
		ImGui.PlotLines("Plot", { 0.1, 0.5, 0.3, 0.9, 0.2, 0.7 }, 0, nil, 0, 1, Vector2.new(0, 50))
		_, state.drag = ImGui.DragFloat3("Drag", state.drag)
		ImGui.TextColored(Color3.new(1, 0.4, 0.4), "Colored %s", "text")
		ImGui.SeparatorText("Draw list")

		local drawList = ImGui.GetWindowDrawList()
		local p = ImGui.GetCursorScreenPos()
		drawList:AddRectFilled(p, Vector2.new(p.X + 100, p.Y + 24), ImGui.COL32(255, 128, 0))
		drawList:AddCircleFilled(Vector2.new(p.X + 130, p.Y + 12), 12, ImGui.COL32(0, 200, 255))
		drawList:AddTriangleFilled(Vector2.new(p.X + 160, p.Y + 24), Vector2.new(p.X + 172, p.Y), Vector2.new(p.X + 184, p.Y + 24), ImGui.COL32(120, 255, 120))
		drawList:AddLine(Vector2.new(p.X + 200, p.Y), Vector2.new(p.X + 260, p.Y + 24), ImGui.COL32(255, 255, 255), 2)
		ImGui.Dummy(Vector2.new(0, 28))

		local style = ImGui.GetStyle()
		styleInfo.padding = style.WindowPadding
		styleInfo.textColor = style.Colors[ImGui.Col.Text]
		ImGui.Text("WindowPadding %.0f, %.0f  Framerate %.0f", style.WindowPadding.X, style.WindowPadding.Y, ImGui.GetIO().Framerate)
		hsv = { ImGui.ColorConvertRGBtoHSV(1, 0, 0) }
		if ImGui.CollapsingHeader("Table") then
			if ImGui.BeginTable("t", 3, ImGui.TableFlags.Borders) then
				for row = 1, 3 do
					ImGui.TableNextRow()
					for column = 1, 3 do
						ImGui.TableSetColumnIndex(column - 1)
						ImGui.Text("r%d c%d", row, column)
					end
				end
				ImGui.EndTable()
			end
		end
	end
	ImGui.End()
end)

local function step()
	frame += 1
	table.clear(DrawCalls)
	ImGui.Step(1 / 60, W, H)
end

local function center(rect)
	return (rect[1].X + rect[2].X) / 2, (rect[1].Y + rect[2].Y) / 2
end

local function click(x, y)
	ImGui.AddMousePosEvent(x, y)
	step()
	ImGui.AddMouseButtonEvent(0, true)
	step()
	ImGui.AddMouseButtonEvent(0, false)
	step()
end

local function key(name)
	ImGui.AddKeyEvent(name, true)
	step()
	ImGui.AddKeyEvent(name, false)
	step()
end

step()
step()

check("GetVersion", ImGui.GetVersion() == "1.92.9b")
check("CalcTextSize", (function()
	local size = ImGui.CalcTextSize("abc")
	return size.X == 21 and size.Y == 13
end)())
check("ColorConvertRGBtoHSV out params", hsv[1] == 0 and hsv[2] == 1 and hsv[3] == 1)
check("Style.WindowPadding field", styleInfo.padding.X == 8 and styleInfo.padding.Y == 8)
check("Style.Colors[Text] array field", styleInfo.textColor[1] == 1 and styleInfo.textColor[4] == 1)

click(center(rects.button))
check("button click (clicks=" .. state.clicks .. ")", state.clicks == 1)
check("WantCaptureMouse over window", ImGui.WantCaptureMouse())

click(center(rects.checkbox))
check("checkbox toggled", state.checked == true)

local sliderY = (rects.slider[1].Y + rects.slider[2].Y) / 2
click(rects.slider[1].X + rects.sliderWidth * 0.75, sliderY)
check(string.format("slider set by click (%.3f)", state.slider), math.abs(state.slider - 0.75) < 0.08)

click(rects.input[1].X + 20, (rects.input[1].Y + rects.input[2].Y) / 2)
check("WantTextInput after focusing InputText", ImGui.WantTextInput())
key("End")
ImGui.AddInputCharactersUTF8(" world")
step()
key("Backspace")
check("typed into InputText ('" .. state.text .. "')", state.text == "hello worl")
key("Enter")

ImGui.GetStyle().Alpha = 0.5
step()
check("Style.Alpha write", math.abs(ImGui.GetStyle().Alpha - 0.5) < 1e-6)
ImGui.GetStyle().Alpha = 1
step()

local counts = {}
for _, call in DrawCalls do
	counts[call[1]] = (counts[call[1]] or 0) + 1
end
print(string.format("frame %d: rect=%d quad=%d tri=%d text=%d", frame, counts.rect or 0, counts.quad or 0, counts.tri or 0, counts.text or 0))
print(string.format("RESULT %d failure(s)", failures))
print("JSON:" .. EncodeJson({ "Luau API test window", DrawCalls }))

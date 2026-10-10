-- Touch input against a fake Roblox, in every render mode: a finger is the mouse (hover, press, drag, release), two
-- fingers scroll, holding one still is a right click, touches off the windows are left to the game, positions include
-- the top bar inset, and a soft keyboard types, deletes and confirms through the hidden TextBox.
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

local function Signal()
	local handlers = {}
	local signal = {}
	function signal:Connect(fn)
		table.insert(handlers, fn)
		return {
			Disconnect = function()
				local index = table.find(handlers, fn)
				if index then
					table.remove(handlers, index)
				end
			end,
		}
	end
	function signal:Fire(...)
		for _, fn in table.clone(handlers) do
			fn(...)
		end
	end
	return signal
end

local focusedTextBox = nil

local function NewInstance(className)
	local props = { ClassName = className, Name = className, Visible = true, Children = {} }
	if className == "ScrollingFrame" or className == "ScreenGui" then
		props.AbsoluteSize = Vector2.new(W, H)
	end
	local signals = {}
	local instance
	local methods = {
		FocusLost = Signal(),
		GetPropertyChangedSignal = function(_, property)
			signals[property] = signals[property] or Signal()
			return signals[property]
		end,
		Destroy = function()
			props.Destroyed = true
			if focusedTextBox == instance then
				focusedTextBox = nil
			end
		end,
		FindFirstChild = function(_, name)
			for _, child in props.Children do
				if child.Name == name then
					return child
				end
			end
			return nil
		end,
		CaptureFocus = function()
			focusedTextBox = instance
		end,
		ReleaseFocus = function()
			if focusedTextBox == instance then
				focusedTextBox = nil
				instance.FocusLost:Fire(false)
			end
		end,
		IsFocused = function()
			return focusedTextBox == instance
		end,
	}
	methods.WaitForChild = methods.FindFirstChild
	instance = setmetatable({}, {
		__index = function(_, key)
			return methods[key] or props[key]
		end,
		__newindex = function(_, key, value)
			if key == "Parent" and value ~= nil then
				if value.ClassName == "CoreGui" then
					return -- like a LocalScript: Roblox ignores the assignment without an error
				end
				table.insert(value.Children, instance)
			end
			local old = props[key]
			props[key] = value
			if old ~= value and signals[key] then
				signals[key]:Fire()
			end
		end,
	})
	return instance
end

Instance = { new = NewInstance }
UDim2 = {
	fromScale = function(x, y)
		return { x, y }
	end,
	fromOffset = function(x, y)
		return { x, y }
	end,
}

local function EnumItems(names)
	local items = {}
	for _, name in names do
		items[name] = setmetatable({ Name = name }, { __tostring = function() return "Enum." .. name end })
	end
	return items
end

local keyNames = { "LeftControl", "RightControl", "LeftShift", "RightShift", "LeftAlt", "RightAlt", "LeftSuper", "RightSuper",
	"Return", "Backspace", "Tab", "Escape", "Space", "Left", "Right", "Up", "Down", "Home", "End", "Delete", "Semicolon", "Comma", "Period" }
for i = 0, 25 do
	table.insert(keyNames, string.char(65 + i))
end
Enum = {
	KeyCode = EnumItems(keyNames),
	UserInputType = EnumItems({ "MouseButton1", "MouseButton2", "MouseButton3", "Keyboard", "MouseWheel", "MouseMovement" }),
	ScrollingDirection = EnumItems({ "XY" }),
	ElasticBehavior = EnumItems({ "Never" }),
	ContextActionResult = EnumItems({ "Sink", "Pass" }),
	UserInputState = EnumItems({ "Begin", "Change", "End", "Cancel" }),
	ZIndexBehavior = EnumItems({ "Sibling" }), ScreenInsets = EnumItems({ "None" }),
	Font = EnumItems({ "BuilderSans", "Arial", "SourceSans", "RobotoMono" }),
	TextXAlignment = EnumItems({ "Left" }), TextYAlignment = EnumItems({ "Top" }),
}
Enum.UserInputType.Touch = Enum.UserInputType.Touch or setmetatable({ Name = "Touch" }, {})
UDim = { new = function(s, o) return { Scale = s, Offset = o } end }
UDim2.new = function(sx, ox, sy, oy) return { X = { Scale = sx, Offset = ox }, Y = { Scale = sy, Offset = oy } } end
NumberSequenceKeypoint = { new = function(t, v) return { Time = t, Value = v } end }
NumberSequence = { new = function(a, b) return if type(a) == "table" then { Keypoints = a } else { Keypoints = { { Time = 0, Value = a }, { Time = 1, Value = b } } } end }
ColorSequence = { new = function(a, b) return { A = a, B = b or a } end }
warn = function() end

local AZERTY = { Q = "A", A = "Q", W = "Z", Z = "W", Semicolon = "M", M = "," }
local pressed = {}
local mouse = Vector2.new(0, 0)
local UIS = {
	TouchEnabled = true, KeyboardEnabled = false,
	InputBegan = Signal(),
	InputEnded = Signal(),
	InputChanged = Signal(),
	WindowFocused = Signal(),
	WindowFocusReleased = Signal(),
}
function UIS:IsKeyDown(keyCode)
	return pressed[keyCode] == true
end
function UIS:GetMouseLocation()
	return mouse
end
function UIS:GetFocusedTextBox()
	return focusedTextBox
end
function UIS:GetStringForKeyCode(keyCode)
	return AZERTY[keyCode.Name] or keyCode.Name
end

local bound = {}
local CAS = {}
function CAS:BindActionAtPriority(name, callback)
	bound[name] = callback
end
function CAS:UnbindAction(name)
	bound[name] = nil
end

local playerGui = NewInstance("PlayerGui")
local player = NewInstance("Player")
playerGui.Name = "PlayerGui"
playerGui.Parent = player
local services = {
	UserInputService = UIS,
	ContextActionService = CAS,
	CoreGui = NewInstance("CoreGui"),
	GuiService = { GetGuiInset = function() return Vector2.new(0, 36) end },
	Players = { LocalPlayer = player },
	TextService = {
		GetTextSize = function(_, text, size)
			return Vector2.new(#text * HarnessAdvance(size), size)
		end,
	},
}
game = {
	GetService = function(_, name)
		return services[name]
	end,
}

--------------------------------------------------------------------------------
-- Test
--------------------------------------------------------------------------------

local SENTINEL = "\u{200B}"
local INSET = 36

local function run(mode, library)
	local state = { clicks = 0, name = "abc", scroll = 0, slider = 0, popup = false }
	local options = {
		RenderMode = mode, AutoRender = false, Input = true, DisplaySize = Vector2.new(W, H),
		TouchLongPress = 0.05, TouchKeyboard = true,
		HitTest = function(x, y)
			return x >= 50 and x <= 470 and y >= 50 and y <= 370
		end,
		MeasureText = function(_, size, text)
			return (utf8.len(text) or #text) * HarnessAdvance(size)
		end,
	}
	if library then
		options[mode] = library
	end
	ImGui.Init(options)
	ImGui.OnFrame(function()
		ImGui.SetNextWindowPos(Vector2.new(50, 50), ImGui.Cond.Always)
		ImGui.SetNextWindowSize(Vector2.new(420, 320), ImGui.Cond.Always)
		ImGui.Begin("Touch test")
		if ImGui.Button("Tap me") then
			state.clicks += 1
		end
		state.buttonRect = { ImGui.GetItemRectMin(), ImGui.GetItemRectMax() }
		local _
		_, state.slider = ImGui.SliderFloat("Slider", state.slider, 0, 100)
		state.sliderRect = { ImGui.GetItemRectMin(), ImGui.GetItemRectMax() }
		_, state.name = ImGui.InputText("Name", state.name)
		state.inputRect = { ImGui.GetItemRectMin(), ImGui.GetItemRectMax() }
		ImGui.Text("Right click me")
		state.textRect = { ImGui.GetItemRectMin(), ImGui.GetItemRectMax() }
		if ImGui.BeginPopupContextItem("menu") then
			state.popup = true
			ImGui.Text("menu")
			ImGui.EndPopup()
		end
		ImGui.BeginChild("lines", Vector2.new(0, 120), ImGui.ChildFlags.Borders)
		for i = 1, 40 do
			ImGui.Text("line %d", i)
		end
		state.scroll = ImGui.GetScrollY()
		ImGui.EndChild()
		state.childRect = { ImGui.GetItemRectMin(), ImGui.GetItemRectMax() }
		ImGui.End()
	end)

	local function step(count)
		for _ = 1, count or 1 do
			table.clear(DrawCalls)
			ImGui.Step(1 / 60, W, H)
		end
	end
	local function center(rect)
		return (rect[1].X + rect[2].X) / 2, (rect[1].Y + rect[2].Y) / 2
	end
	local function wait(seconds)
		local t = os.clock()
		while os.clock() - t < seconds do end
	end

	-- A finger: the touch sink of ContextActionService sees it first, then UserInputService
	local fingers = 0
	local function touch(x, y)
		fingers += 1
		local input = { UserInputType = Enum.UserInputType.Touch, Position = { X = x, Y = y - INSET, Z = 0 }, Id = fingers }
		local sink = bound.DearImGuiTouchSink
		local result = sink and sink(nil, Enum.UserInputState.Begin, input)
		UIS.InputBegan:Fire(input, result == Enum.ContextActionResult.Sink)
		return input, result
	end
	local function move(input, x, y)
		input.Position = { X = x, Y = y - INSET, Z = 0 }
		if bound.DearImGuiTouchSink then
			bound.DearImGuiTouchSink(nil, Enum.UserInputState.Change, input)
		end
		UIS.InputChanged:Fire(input, false)
	end
	local function lift(input)
		if bound.DearImGuiTouchSink then
			bound.DearImGuiTouchSink(nil, Enum.UserInputState.End, input)
		end
		UIS.InputEnded:Fire(input, false)
	end
	local function name(text)
		return mode .. ": " .. text
	end

	step(3)
	check(name("the touch sink is bound"), bound.DearImGuiTouchSink ~= nil)

	-- A tap clicks, at the position the finger touched (the inset is added back), whatever the mouse says
	mouse = Vector2.new(1100, 700)
	local x, y = center(state.buttonRect)
	local finger, result = touch(x, y)
	step(2)
	lift(finger)
	step(3)
	check(name("a tap on a window is kept from the game"), result == Enum.ContextActionResult.Sink)
	check(name("a tap clicks the button under the finger (clicks = " .. state.clicks .. ")"), state.clicks == 1)
	check(name("the hover is gone once the finger lifts"), not ImGui.WantCaptureMouse())

	-- A touch away from the windows is the game's
	finger, result = touch(900, 600)
	step(2)
	lift(finger)
	step(2)
	check(name("a touch off the windows is left to the game"), result == Enum.ContextActionResult.Pass and state.clicks == 1)
	finger = touch(900, 600)
	step(2)
	move(finger, 900, 560)
	step(2)
	lift(finger)
	step(2)
	check(name("dragging off the windows (the camera) reaches nothing"), state.clicks == 1)

	-- Dragging the slider follows the finger
	local sx0, sy = state.sliderRect[1].X + 20, (state.sliderRect[1].Y + state.sliderRect[2].Y) / 2
	finger = touch(sx0, sy)
	step(2)
	move(finger, sx0 + 60, sy)
	step(3)
	local mid = state.slider
	move(finger, sx0 + 120, sy)
	step(3)
	lift(finger)
	step(3)
	check(name(string.format("dragging a slider follows the finger (%.1f then %.1f)", mid, state.slider)), mid > 0 and state.slider > mid)

	-- Two fingers scroll the list under them, and click nothing
	local cx, cy = center(state.childRect)
	local before = state.scroll
	local a = touch(cx - 30, cy + 30)
	step(1)
	local b = touch(cx + 30, cy + 30)
	step(2)
	move(a, cx - 30, cy - 20)
	move(b, cx + 30, cy - 20)
	step(3)
	lift(a)
	lift(b)
	step(3)
	check(name(string.format("two fingers dragging up scroll the list down (%.1f to %.1f)", before, state.scroll)), state.scroll > before and state.clicks == 1)

	-- Holding one finger still is a right click
	x, y = center(state.textRect)
	finger = touch(x, y)
	step(2)
	wait(0.08)
	step(4)
	lift(finger)
	step(4)
	check(name("holding a finger still opens the context menu"), state.popup)

	-- The soft keyboard
	click = nil
	local sink
	for _, child in playerGui.Children do
		if child.Name == "DearImGuiInputSink" then
			sink = child -- the newest: sinks of earlier modes are destroyed but stay listed in the fake
		end
	end
	local textBox = sink and sink:FindFirstChild("TextInput")
	check(name("the hidden TextBox holds one invisible character"), textBox ~= nil and textBox.Text == SENTINEL)
	state.popup = false
	x, y = center(state.inputRect)
	finger = touch(900, 600)
	lift(finger)
	finger = touch(x, y)
	step(2)
	lift(finger)
	step(4)
	check(name("tapping a text field brings up the keyboard"), textBox ~= nil and textBox:IsFocused())
	textBox.Text = SENTINEL .. "d"
	step(2)
	check(name(string.format("typed text arrives (%q) and the TextBox starts over", state.name)), state.name == "abcd" and textBox.Text == SENTINEL)
	textBox.Text = ""
	step(3)
	check(name(string.format("deleting the invisible character is Backspace (%q)", state.name)), state.name == "abc" and textBox.Text == SENTINEL)
	textBox.Text = SENTINEL .. "\n"
	step(3)
	check(name("a line break is Enter: it confirms the field"), ImGui.WantTextInput() == false)

	ImGui.Shutdown()
	check(name("Shutdown unbinds the touch sink"), bound.DearImGuiTouchSink == nil)
end

run("DrawingImmediate", MockDrawingImmediate)
run("Drawing", MockDrawing)
run("Cesium", nil)

print(string.format("RESULT %d failure(s)", failures))

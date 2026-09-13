-- Runs the UserInputService input code against a fake Roblox (game, Enum, Instance, UserInputService) with an AZERTY
-- layout: wheel blocking over windows, typed text through the hidden TextBox, layout-aware shortcuts, Ctrl+V paste,
-- AltGr characters and cleanup.
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
}

local AZERTY = { Q = "A", A = "Q", W = "Z", Z = "W", Semicolon = "M", M = "," }
local pressed = {}
local mouse = Vector2.new(0, 0)
local UIS = {
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
function CAS:BindActionAtPriority(name)
	bound[name] = true
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

ImGui.Init({
	RenderMode = "DrawingImmediate", DrawingImmediate = MockDrawingImmediate, AutoRender = false, Input = true,
	DisplaySize = Vector2.new(W, H),
	MeasureText = function(_, size, text)
		return (utf8.len(text) or #text) * HarnessAdvance(size)
	end,
})

local state = { name = "abc", scroll = 0 }
ImGui.OnFrame(function()
	ImGui.SetNextWindowPos(Vector2.new(50, 50), ImGui.Cond.Always)
	ImGui.SetNextWindowSize(Vector2.new(420, 320), ImGui.Cond.Always)
	ImGui.Begin("Input test")
	local _
	_, state.name = ImGui.InputText("Name", state.name)
	state.inputRect = { ImGui.GetItemRectMin(), ImGui.GetItemRectMax() }
	ImGui.BeginChild("lines", Vector2.new(0, 160), ImGui.ChildFlags.Borders)
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

local function key(name, down)
	local keyCode = Enum.KeyCode[name]
	pressed[keyCode] = if down then true else nil
	local signal = if down then UIS.InputBegan else UIS.InputEnded
	signal:Fire({ UserInputType = Enum.UserInputType.Keyboard, KeyCode = keyCode }, focusedTextBox ~= nil)
end

local function click(x, y)
	mouse = Vector2.new(x, y)
	step()
	UIS.InputBegan:Fire({ UserInputType = Enum.UserInputType.MouseButton1 }, false)
	step()
	UIS.InputEnded:Fire({ UserInputType = Enum.UserInputType.MouseButton1 }, false)
	step(2)
end

local function center(rect)
	return (rect[1].X + rect[2].X) / 2, (rect[1].Y + rect[2].Y) / 2
end

step(3)
local sink = playerGui:FindFirstChild("DearImGuiInputSink")
local textBox = sink and sink:FindFirstChild("TextInput")
local wheelSink = sink and sink:FindFirstChild("WheelSink")
check("input sink lands in PlayerGui when CoreGui silently refuses it", sink ~= nil and sink.Parent == playerGui)
check("input sink has a hidden TextBox and a wheel ScrollingFrame", textBox ~= nil and wheelSink ~= nil)

-- Mouse wheel over a window: the ScrollingFrame shows (so the camera ignores the wheel) and Dear ImGui still scrolls
mouse = Vector2.new(center(state.childRect))
step(2)
check("wheel blocker shows while the mouse is over a window", wheelSink ~= nil and wheelSink.Visible == true)
check("wheel blocker is centered on its canvas", wheelSink ~= nil and wheelSink.CanvasPosition ~= nil and wheelSink.CanvasPosition.X == W)
UIS.InputChanged:Fire({ UserInputType = Enum.UserInputType.MouseWheel, Position = { Z = -3 } }, true)
step(3)
check(string.format("Dear ImGui still receives the wheel (child scrolled to %.0f)", state.scroll), state.scroll > 0)
mouse = Vector2.new(1100, 700)
step(2)
check("wheel blocker hides away from windows", wheelSink ~= nil and wheelSink.Visible == false)

-- Typing: clicking the field gives the hidden TextBox focus, and its text reaches the field
click(center(state.inputRect))
check("the hidden TextBox takes focus while a text field is active", textBox ~= nil and textBox:IsFocused())
key("LeftControl", true)
key("Q", true) -- AZERTY: the key labelled A is KeyCode.Q
step()
key("Q", false)
key("LeftControl", false)
step()
textBox.Text = "x"
step()
check(string.format("Ctrl + AZERTY A selects all, typing replaces it (%q)", state.name), state.name == "x")
textBox.Text = "é€"
step()
check(string.format("accented and euro text arrives exactly (%q)", state.name), state.name == "xé€")
textBox.Text = "\n\t"
step()
check("Enter and Tab characters from the TextBox are dropped (keys handle them)", state.name == "xé€")

key("LeftControl", true)
key("V", true)
textBox.Text = "PASTE" -- the TextBox receives the system clipboard
step()
key("V", false)
key("LeftControl", false)
step()
check(string.format("Ctrl+V pastes the system clipboard once (%q)", state.name), state.name == "xé€PASTE")

key("LeftControl", true)
key("RightAlt", true)
textBox.Text = "@" -- AltGr+0 on AZERTY
step()
key("RightAlt", false)
key("LeftControl", false)
step()
check(string.format("AltGr characters arrive (%q)", state.name), state.name == "xé€PASTE@")

key("LeftControl", true)
textBox.Text = "undo" -- Ctrl+Z inside the TextBox itself: must not reach the field
step()
key("LeftControl", false)
step(2)
check(string.format("text from Ctrl shortcuts that are not a paste is ignored (%q)", state.name), state.name == "xé€PASTE@")

local gameBox = NewInstance("TextBox") -- chat or the game's own TextBox
gameBox:CaptureFocus()
step(3)
check("another TextBox that takes focus keeps it", gameBox:IsFocused() and not textBox:IsFocused())
gameBox:ReleaseFocus()
step()
check("the hidden TextBox takes focus back once no other TextBox has it", textBox:IsFocused())

click(1100, 700)
check("the TextBox releases focus when the field deactivates", textBox ~= nil and not textBox:IsFocused())
check("keyboard sink is unbound when Dear ImGui stops wanting the keyboard", bound.DearImGuiKeyboardSink == nil)

ImGui.Shutdown()
check("Shutdown destroys the input sink", sink ~= nil and sink.Destroyed == true)

print(string.format("RESULT %d failure(s)", failures))

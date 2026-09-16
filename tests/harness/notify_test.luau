-- The notify addon (notify.luau) linked into the bundle: toasts of each kind draw their title and content, a toast
-- button runs its function when clicked, toasts can be removed and cleared, and they dismiss themselves after
-- DismissTime; nothing asserts.
local ImGui = ImGuiBundle
local W, H = 800, 600
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
	DisplaySize = Vector2.new(W, H), Addons = ImGuiAddons.notify,
	MeasureText = function(_, size, text)
		return (utf8.len(text) or #text) * HarnessAdvance(size)
	end,
})
check("InsertNotification, RenderNotifications and ToastType", type(ImGui.InsertNotification) == "function"
	and type(ImGui.RenderNotifications) == "function" and ImGui.ToastType.Error == 3)
check("an unknown toast type is an error", not pcall(ImGui.InsertNotification, { Type = "Bogus" }))

local pressed = 0
ImGui.InsertNotification({ Type = "Success", Title = "Saved", Content = "All settings saved" })
ImGui.InsertNotification("Warning", "Low memory")
ImGui.InsertNotification({ Type = "Info", Content = "Item deleted", ButtonLabel = "Undo", DismissTime = 10000, OnButtonPress = function()
	pressed += 1
end })
check("three toasts are queued", ImGui.GetNotificationCount() == 3)

ImGui.OnFrame(function()
	ImGui.RenderNotifications()
end)

local function frame()
	table.clear(DrawCalls)
	local ok, err = pcall(ImGui.Step, 1 / 60, W, H)
	if not ok then
		stepErrors += 1
		realPrint("  step error: " .. tostring(err))
	end
end

local function find(text, exact)
	for _, call in DrawCalls do
		if call[1] == "text" and (if exact then call[10] == text else string.find(call[10], text, 1, true) ~= nil) then
			return call
		end
	end
	return nil
end

-- Toasts widen over their first frames (ImGuiNotify puts the close button at 80% of the auto-resized width) and move
-- left as they do: let them settle before clicking
for _ = 1, 40 do
	frame()
end
check(string.format("frames run without errors (%d) or assertions (%d)", stepErrors, warnings), stepErrors == 0 and warnings == 0)
check("toast titles and contents are drawn", find("Saved") ~= nil and find("All settings saved") ~= nil and find("Low memory") ~= nil
	and find("Item deleted") ~= nil)

local button = find("Undo", true)
check("the toast button is drawn", button ~= nil)
if button ~= nil then
	ImGui.AddMousePosEvent(button[2] + 4, button[3] + 4)
	frame()
	ImGui.AddMouseButtonEvent(0, true)
	frame()
	ImGui.AddMouseButtonEvent(0, false)
	frame()
	frame()
end
check(string.format("clicking the button runs its function (%d)", pressed), pressed == 1)

ImGui.RemoveNotification(0)
check("RemoveNotification", ImGui.GetNotificationCount() == 2)
ImGui.ClearNotifications()
check("ClearNotifications", ImGui.GetNotificationCount() == 0)

ImGui.InsertNotification({ Type = "Error", Content = "Brief", DismissTime = 50 })
local start = os.clock()
while ImGui.GetNotificationCount() > 0 and os.clock() - start < 5 do
	frame()
end
check(string.format("a toast dismisses itself after DismissTime (%.2f s)", os.clock() - start), ImGui.GetNotificationCount() == 0)
check(string.format("no errors (%d) or assertions (%d)", stepErrors, warnings), stepErrors == 0 and warnings == 0)

ImGui.Shutdown()
realPrint(string.format("RESULT %d failure(s)", failures))

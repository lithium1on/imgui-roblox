-- Runs an example headlessly: ImGui.Init keeps the example's options but draws into the recording DrawingImmediate mock,
-- measures text with the harness metrics, and leaves frames and input to example_driver.luau. Warnings are collected.

ExampleWarnings = {}
local realPrint = print
print = function(first, ...)
	if first == "[warn]" then
		local parts = {}
		for index, value in { ... } do
			parts[index] = tostring(value)
		end
		table.insert(ExampleWarnings, table.concat(parts, " "))
	end
	realPrint(first, ...)
end

local realInit = ImGuiBundle.Init
ImGuiBundle.Init = function(options)
	options = if options ~= nil then table.clone(options) else {}
	options.RenderMode = nil
	options.DrawingImmediate = nil
	options.Drawing = nil
	options.Renderer = MockDrawingImmediate
	options.AutoRender = false
	options.Input = false
	options.DisplaySize = Vector2.new(1280, 800)
	options.MeasureText = function(_, size, text)
		return (utf8.len(text) or #text) * HarnessAdvance(size)
	end
	ExampleInitCalled = true
	return realInit(options)
end

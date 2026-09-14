-- ImGui.Shutdown() called from inside an OnFrame callback, as a window's close button handler would: the frame ends
-- without an error or assertion, later callbacks of that frame don't run, nothing is drawn, every Drawing object is
-- removed, and Init works again afterwards. Runs in DrawingImmediate and Drawing modes.
local ImGui = ImGuiBundle
local W, H = 800, 600
local failures = 0

local warnings = 0
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

local function run(mode, library)
	local options = {
		RenderMode = mode, AutoRender = false, Input = false, DisplaySize = Vector2.new(W, H),
		MeasureText = function(_, size, text)
			return (utf8.len(text) or #text) * HarnessAdvance(size)
		end,
	}
	options[mode] = library
	ImGui.Init(options)

	local frames, laterCallback = 0, 0
	local open = true
	ImGui.OnFrame(function()
		frames += 1
		local visible
		visible, open = ImGui.Begin("Closing window", open)
		if visible then
			ImGui.Text("frame %d", frames)
		end
		ImGui.End()
		if frames == 3 then
			open = false -- as if the close button was clicked
		end
		if not open then
			ImGui.Shutdown()
			ImGui.Text("still inside the frame") -- the context stays usable until the frame ends
		end
	end)
	ImGui.OnFrame(function()
		laterCallback += 1
	end)

	local before = warnings
	local stepErrors = 0
	for _ = 1, 3 do
		table.clear(DrawCalls)
		local ok, err = pcall(ImGui.Step, 1 / 60, W, H)
		if not ok then
			stepErrors += 1
			realPrint("  step error: " .. tostring(err))
		end
	end
	check(string.format("%s: the shutdown frame ends without an error (%d) or warning (%d)", mode, stepErrors, warnings - before),
		stepErrors == 0 and warnings == before)
	check(string.format("%s: ImGui is shut down after that frame", mode), not ImGui.IsInitialized() and ImGui.RenderMode == nil)
	check(string.format("%s: later callbacks skip the shutdown frame (%d runs, want 2)", mode, laterCallback), laterCallback == 2)
	if mode == "DrawingImmediate" then
		check(string.format("DrawingImmediate: nothing is drawn in the shutdown frame (%d calls)", #DrawCalls), #DrawCalls == 0)
	else
		local left = 0
		for _, object in library.Objects do
			if not object.Removed then
				left += 1
			end
		end
		check(string.format("Drawing: every object is removed (%d left)", left), left == 0)
	end
	local ok = pcall(ImGui.Step, 1 / 60, W, H)
	check(string.format("%s: Step after shutdown asks for Init again", mode), not ok)

	ImGui.Init(options)
	local drawn = false
	ImGui.OnFrame(function()
		ImGui.Begin("Again")
		drawn = true
		ImGui.End()
	end)
	table.clear(DrawCalls)
	ok = pcall(ImGui.Step, 1 / 60, W, H)
	check(string.format("%s: Init works again after a shutdown from a frame callback", mode), ok and drawn and ImGui.IsInitialized())
	ImGui.Shutdown()
end

run("DrawingImmediate", MockDrawingImmediate)
run("Drawing", MockDrawing)

realPrint(string.format("RESULT %d failure(s)", failures))

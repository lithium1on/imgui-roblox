-- Runs a few frames of the example loaded above and checks it initialized, drew something and raised no error or warning.

local ImGui = ImGuiBundle
local failures = 0
local function check(name, ok)
	print((if ok then "PASS " else "FAIL ") .. name)
	if not ok then
		failures += 1
	end
end

check("the example calls ImGui.Init", ExampleInitCalled == true and ImGui.IsInitialized())

local frames, mostCalls, lastFrame = 0, 0, {}
for _ = 1, 6 do
	if not ImGui.IsInitialized() then
		break
	end
	table.clear(DrawCalls)
	ImGui.Step(1 / 60, 1280, 800)
	frames += 1
	mostCalls = math.max(mostCalls, #DrawCalls)
	if #DrawCalls > 0 then
		lastFrame = table.clone(DrawCalls)
	end
	local deferred = ExampleDeferred
	ExampleDeferred = {}
	for _, entry in deferred do
		entry[1](table.unpack(entry, 2, entry.n))
	end
end

check(string.format("frames ran (%d) and drew something (up to %d calls)", frames, mostCalls), frames > 0 and mostCalls > 0)
check(string.format("no errors or warnings (%d): %s", #ExampleWarnings, table.concat(ExampleWarnings, " | ")), #ExampleWarnings == 0)
if ImGui.IsInitialized() then
	ImGui.Shutdown()
end
print(string.format("RESULT %d failure(s)", failures))
print("SIZE:1280x800")
print("JSON:" .. EncodeJson({ "last frame drawn by the example", lastFrame }))

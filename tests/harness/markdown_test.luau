-- The markdown addon (markdown.luau) linked into the bundle: headings, emphasis, lists, links and rules draw, headings
-- are larger than body text, clicking a link returns it, configs and format flags are accepted; nothing asserts.
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
	DisplaySize = Vector2.new(W, H), FontSize = 14, Addons = ImGuiAddons.markdown,
	MeasureText = function(_, size, text)
		return (utf8.len(text) or #text) * HarnessAdvance(size)
	end,
})
check("ImGui.Markdown and ImGui.MarkdownFormatFlags", type(ImGui.Markdown) == "function" and ImGui.MarkdownFormatFlags.GithubStyle == 7)

local document = table.concat({
	"# Title",
	"Some *emphasis* in the body.",
	"## Section",
	"  * first item",
	"  * second item",
	"[Documentation](https://example.com/docs)",
	"___",
	"The end",
}, "\n")

local clicked = nil
ImGui.OnFrame(function()
	ImGui.SetNextWindowPos(Vector2.new(10, 10), ImGui.Cond.Always)
	ImGui.SetNextWindowSize(Vector2.new(500, 400), ImGui.Cond.Always)
	ImGui.Begin("Help")
	local link = ImGui.Markdown(document)
	if link ~= nil then
		clicked = link
	end
	ImGui.End()
	ImGui.SetNextWindowPos(Vector2.new(520, 10), ImGui.Cond.Always)
	ImGui.SetNextWindowSize(Vector2.new(260, 300), ImGui.Cond.Always)
	ImGui.Begin("Styled")
	ImGui.Markdown("# Big\ntext", { H1 = { Size = 30, Separator = false }, Flags = ImGui.MarkdownFormatFlags.GithubStyle, LinkIcon = ">" })
	ImGui.End()
end)

local function frame()
	table.clear(DrawCalls)
	local ok, err = pcall(ImGui.Step, 1 / 60, W, H)
	if not ok then
		stepErrors += 1
		realPrint("  step error: " .. tostring(err))
	end
end

local function find(text)
	for _, call in DrawCalls do
		if call[1] == "text" and string.find(call[10], text, 1, true) then
			return call
		end
	end
	return nil
end

frame()
frame()
check(string.format("frames run without errors (%d) or assertions (%d)", stepErrors, warnings), stepErrors == 0 and warnings == 0)
check("headings, emphasis, list items, links and text are drawn", find("Title") ~= nil and find("emphasis") ~= nil and find("Section") ~= nil
	and find("first") ~= nil and find("Documentation") ~= nil and find("end") ~= nil)
local title, body, big = find("Title"), find("body"), find("Big")
check(string.format("headings are larger than body text (%s > %s)", tostring(title and title[5]), tostring(body and body[5])),
	title ~= nil and body ~= nil and title[5] > body[5])
check(string.format("heading configs apply (%s)", tostring(big and big[5])), big ~= nil and big[5] >= 29)

local link = find("Documentation")
ImGui.AddMousePosEvent(link[2] + 8, link[3] + 6)
frame()
ImGui.AddMouseButtonEvent(0, true)
frame()
ImGui.AddMouseButtonEvent(0, false)
frame()
frame()
check(string.format("clicking a link returns it (%s)", tostring(clicked)), clicked == "https://example.com/docs")
check(string.format("no errors (%d) or assertions (%d) after clicking", stepErrors, warnings), stepErrors == 0 and warnings == 0)

ImGui.Shutdown()
realPrint(string.format("RESULT %d failure(s)", failures))

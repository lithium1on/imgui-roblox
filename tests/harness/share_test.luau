-- Two scripts, each with its own copy of a bundle (ShareBuildA, then ShareBuildB), draw with one Dear ImGui context:
-- one frame loop, both scripts' windows in the same context, each script with its own theme and font. When bundle B
-- has more than bundle A, both scripts move to B; when each has something the other lacks, they stay separate.
-- Also: the first script leaving hands the context style to the next, shutting down from frame callbacks, Share = false,
-- and the IDE addon: its editors move with their script, and a script can link it into a context that lacks it.
local A, B = ImGuiBundleA, ImGuiBundleB
local IDE = ImGuiAddons.ide
local IDEB = table.clone(IDE) -- script B's own copy of ide.luau
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

local env = {}
getgenv = function()
	return env
end

local function features(name)
	return { Docking = string.sub(name, 1, 7) == "docking", Debug = string.sub(name, -6) == "_debug" }
end
local function covers(a, b)
	return (a.Docking or not b.Docking) and (a.Debug or not b.Debug)
end
local expected = if covers(features(ShareBuildA), features(ShareBuildB)) then "join"
	elseif covers(features(ShareBuildB), features(ShareBuildA)) then "move"
	else "separate"
realPrint(string.format("%s then %s: expect %s", ShareBuildA, ShareBuildB, expected))

-- DrawingImmediate whose paint event is fired by the test
local paintCallbacks = {}
local paint = setmetatable({
	GetPaint = function()
		return {
			Connect = function(_, callback)
				table.insert(paintCallbacks, callback)
				return {
					Disconnect = function()
						local index = table.find(paintCallbacks, callback)
						if index then
							table.remove(paintCallbacks, index)
						end
					end,
				}
			end,
		}
	end,
}, { __index = MockDrawingImmediate })

local function frame()
	table.clear(DrawCalls)
	for _, callback in table.clone(paintCallbacks) do
		callback()
	end
end

local function options(extra)
	local result = {
		RenderMode = "DrawingImmediate", DrawingImmediate = paint, Input = false, DisplaySize = Vector2.new(W, H),
		MeasureText = function(_, size, text)
			return (utf8.len(text) or #text) * HarnessAdvance(size)
		end,
	}
	for key, value in extra do
		result[key] = value
	end
	return result
end

local function drawnText(text)
	for _, call in DrawCalls do
		if call[1] == "text" and string.find(call[10], text, 1, true) then
			return true
		end
	end
	return false
end

local function near(a, b)
	return math.abs(a - b) < 1e-3
end

-- Script A: light theme, 13 px default font, a Plex font and a text editor made before B arrives, a window at (123, 45)
local seenA = { frames = 0 }
local pinned = true
A.Init(options({ Theme = "Light", FontSize = 13, Addons = IDE }))
local plexA = A.AddFont("Plex", 18)
A.GetStyle().WindowRounding = 7
local editorA = A.TextEditor.new()
editorA:SetText("print('from A')\nreturn 1")
editorA:SetLanguage("Luau")
editorA:SetTabSize(3)
editorA:SetCursor(1, 2)
local callbackA = function(ImGui)
	seenA.frames += 1
	if pinned then
		ImGui.SetNextWindowPos(Vector2.new(123, 45), ImGui.Cond.Always)
	else
		ImGui.SetNextWindowPos(Vector2.new(300, 300), ImGui.Cond.FirstUseEver)
	end
	ImGui.Begin("Script A")
	ImGui.Text("from script A")
	seenA.windowBg = ImGui.GetStyle().Colors[ImGui.Col.WindowBg][1]
	seenA.rounding = ImGui.GetStyle().WindowRounding
	seenA.fontSize = ImGui.GetFontSize()
	seenA.pos = ImGui.GetWindowPos()
	ImGui.PushFont(plexA, 18)
	seenA.plexSize = ImGui.GetFontSize()
	ImGui.PopFont()
	if editorA:IsValid() then
		editorA:Render("##editorA", Vector2.new(220, 80))
	end
	ImGui.End()
end
A.OnFrame(callbackA)
frame()
frame()
check("A alone: its frame loop draws", seenA.frames == 2 and drawnText("from script A"))
pinned = false

-- Script B: dark theme, 16 px Monospace, its own copy of the IDE addon and an editor
local seenB = { frames = 0 }
local warningsBefore = warnings
B.Init(options({ Theme = "Dark", FontSize = 16, Font = "Monospace", Addons = IDEB }))
local editorB = B.TextEditor.new()
editorB:SetText("from B")
local callbackB = function(ImGui)
	seenB.frames += 1
	ImGui.SetNextWindowPos(Vector2.new(400, 300), ImGui.Cond.FirstUseEver)
	ImGui.Begin("Script B")
	ImGui.Text("from script B")
	seenB.windowBg = ImGui.GetStyle().Colors[ImGui.Col.WindowBg][1]
	seenB.fontSize = ImGui.GetFontSize()
	if editorB:IsValid() then
		editorB:Render("##editorB", Vector2.new(220, 80))
	end
	ImGui.End()
end
B.OnFrame(callbackB)
seenA.frames = 0
frame()
frame()
frame()

local infoA, infoB = A.GetShareInfo(), B.GetShareInfo()
realPrint(string.format("A: %s %s %d scripts, B: %s %s %d scripts", infoA.Role, tostring(infoA.Build), infoA.Scripts,
	infoB.Role, tostring(infoB.Build), infoB.Scripts))
check("both scripts' callbacks run every frame", seenA.frames == 3 and seenB.frames == 3)
check("each script keeps its theme inside its callbacks", seenA.windowBg > 0.5 and seenB.windowBg < 0.5)
check("each script keeps its font size", near(seenA.fontSize, 13) and near(seenB.fontSize, 16))
check("style edits made before B arrived are kept", near(seenA.rounding, 7) and near(A.GetStyle().WindowRounding, 7))
check("A's added font still works", near(seenA.plexSize, 18))
check("both windows are drawn", drawnText("from script A") and drawnText("from script B"))
local editorLine, editorIndex = editorA:GetMainCursorPosition()
check("A's text editor keeps its text, settings and cursor", editorA:IsValid() and editorA:GetText() == "print('from A')\nreturn 1"
	and editorA:GetTabSize() == 3 and editorA:GetLanguageName() == "Luau" and editorLine == 1 and editorIndex == 2)
check("B's text editor works", editorB:IsValid() and editorB:GetText() == "from B")

if expected == "separate" then
	check("separate: two frame loops", #paintCallbacks == 2)
	check("separate: A hosts alone, B is private", infoA.Role == "host" and infoA.Scripts == 1 and infoB.Role == "private")
	check(string.format("separate: one warning (%d)", warnings - warningsBefore), warnings - warningsBefore == 1)
	A.Shutdown()
	B.Shutdown()
	check("separate: both shut down", not A.IsInitialized() and not B.IsInitialized() and #paintCallbacks == 0)
	check("separate: the editors are freed", not editorA:IsValid() and not editorB:IsValid())
	realPrint(string.format("RESULT %d failure(s)", failures))
	return
end

check(string.format("shared: no warnings (%d)", warnings - warningsBefore), warnings == warningsBefore)
check("shared: one frame loop", #paintCallbacks == 1)
check("shared: one context with both windows", string.find(A.SaveIniSettings(), "[Window][Script B]", 1, true) ~= nil
	and string.find(B.SaveIniSettings(), "[Window][Script A]", 1, true) ~= nil)
check("shared: A's window stays where it was", seenA.pos ~= nil and near(seenA.pos.X, 123) and near(seenA.pos.Y, 45))
if expected == "join" then
	check("join: A hosts, B is a client of A's bundle", infoA.Role == "host" and infoB.Role == "client"
		and infoA.Scripts == 2 and infoB.Build == ShareBuildA)
else
	check("move: both scripts run on B's bundle", infoA.Role == "client" and infoB.Role == "host"
		and infoA.Build == ShareBuildB and A.HasDocking == B.HasDocking and A.Build == ShareBuildB)
end

-- The first script leaves: B's style becomes the context style
A.Shutdown()
seenA.frames, seenB.frames = 0, 0
frame()
check("A left: only B's callbacks run", seenA.frames == 0 and seenB.frames == 1 and not A.IsInitialized())
check("A left: its text editor is freed, B's is not", not editorA:IsValid() and editorB:IsValid())
check("A left: B keeps its theme and font", seenB.windowBg < 0.5 and near(seenB.fontSize, 16))
check("A left: B shares with nobody", B.GetShareInfo().Scripts == 1 and #paintCallbacks == 1)

-- A comes back, then both shut down from their callbacks in the same frame
A.Init(options({ Theme = "Light", FontSize = 13 }))
plexA = A.AddFont("Plex", 18)
A.OnFrame(callbackA)
frame()
check("A back: both styles again", seenA.windowBg > 0.5 and seenB.windowBg < 0.5 and A.GetShareInfo().Scripts == 2)
check("A back without Addons: no ImGui.TextEditor", A.TextEditor == nil)
A.OnFrame(function(ImGui)
	ImGui.Shutdown()
end)
B.OnFrame(function(ImGui)
	ImGui.Shutdown()
	ImGui.Text("still inside the frame")
end)
warningsBefore = warnings
frame()
check(string.format("shutting both down from callbacks: no warnings (%d)", warnings - warningsBefore), warnings == warningsBefore)
check("shutting both down: everything stops", not A.IsInitialized() and not B.IsInitialized() and #paintCallbacks == 0)
check("shutting both down: editors are freed", not editorB:IsValid())

-- A context without the addon: B links it in
A.Init(options({}))
B.Init(options({ Addons = IDEB }))
local lateEditor = B.TextEditor.new()
lateEditor:SetText("linked later")
local rendered = false
B.OnFrame(function(ImGui)
	ImGui.Begin("Late editor")
	lateEditor:Render("##late", Vector2.new(200, 60))
	rendered = true
	ImGui.End()
end)
frame()
check("B links the addon into A's context", A.TextEditor == nil and rendered and lateEditor:GetText() == "linked later"
	and B.GetShareInfo().Scripts == 2)
A.Shutdown()
B.Shutdown()

-- Share = false: two contexts
A.Init(options({ Share = false }))
B.Init(options({ Share = false }))
check("Share = false: two private contexts", A.GetShareInfo().Role == "private" and B.GetShareInfo().Role == "private"
	and #paintCallbacks == 2)
A.Shutdown()
B.Shutdown()
check("Share = false: both shut down", #paintCallbacks == 0)

realPrint(string.format("RESULT %d failure(s)", failures))

-- A console window: a colored, filterable log that follows new lines, and a command line with a few commands
-- (type "help").

local ImGui = loadstring(game:HttpGet("https://github.com/lithium1on/imgui-roblox/releases/latest/download/imgui.luau"))()
ImGui.Init({ Font = "Monospace", FontSize = 14 })

local MAX_LINES = 500
local COLORS = {
	info = Color3.new(0.85, 0.85, 0.85),
	warn = Color3.new(1, 0.8, 0.3),
	error = Color3.new(1, 0.45, 0.45),
	command = Color3.new(0.5, 0.8, 1),
}
local lines = {}
local input, filter = "", ""
local autoScroll, scrollToBottom = true, false

local function log(kind, format, ...)
	table.insert(lines, { kind = kind, text = string.format(format, ...) })
	if #lines > MAX_LINES then
		table.remove(lines, 1)
	end
	scrollToBottom = autoScroll
end

local commands = {}
commands.help = { "list the commands", function()
	local names = {}
	for name in commands do
		table.insert(names, name)
	end
	table.sort(names)
	for _, name in names do
		log("info", "  %-6s %s", name, commands[name][1])
	end
end }
commands.clear = { "clear the log", function()
	table.clear(lines)
end }
commands.echo = { "print the rest of the line", function(rest)
	log("info", "%s", rest)
end }
commands.time = { "seconds since Dear ImGui started", function()
	log("info", "%.1f s", ImGui.GetTime())
end }
commands.copy = { "copy the log to the clipboard", function()
	local text = {}
	for index, line in lines do
		text[index] = line.text
	end
	ImGui.SetClipboardText(table.concat(text, "\n"))
	log("info", "copied %d lines", #text)
end }

local function run(line)
	log("command", "> %s", line)
	local name, rest = string.match(line, "^%s*(%S+)%s*(.-)%s*$")
	local command = name and commands[string.lower(name)]
	if command then
		command[2](rest)
	else
		log("error", "unknown command '%s', try help", tostring(name))
	end
end

log("info", "Console ready. Type 'help' and press Enter.")
log("warn", "Lines are colored by kind: info, warnings, errors and commands.")

ImGui.OnFrame(function()
	ImGui.SetNextWindowSize(Vector2.new(520, 380), ImGui.Cond.FirstUseEver)
	if ImGui.Begin("Console") then
		local _
		ImGui.SetNextItemWidth(220)
		_, filter = ImGui.InputTextWithHint("##filter", "Filter", filter)
		ImGui.SameLine()
		_, autoScroll = ImGui.Checkbox("Auto-scroll", autoScroll)
		ImGui.SameLine()
		if ImGui.SmallButton("Clear") then
			table.clear(lines)
		end
		ImGui.Separator()

		-- The log fills the window except for one row at the bottom, kept for the command line
		local reserved = ImGui.GetStyle().ItemSpacing.Y + ImGui.GetFrameHeightWithSpacing()
		if ImGui.BeginChild("log", Vector2.new(0, -reserved), ImGui.ChildFlags.None, ImGui.WindowFlags.HorizontalScrollbar) then
			local needle = string.lower(filter)
			for _, line in lines do
				if needle == "" or string.find(string.lower(line.text), needle, 1, true) then
					ImGui.TextColored(COLORS[line.kind], "%s", line.text)
				end
			end
			if scrollToBottom or (autoScroll and ImGui.GetScrollY() >= ImGui.GetScrollMaxY()) then
				ImGui.SetScrollHereY(1)
			end
			scrollToBottom = false
		end
		ImGui.EndChild()
		ImGui.Separator()

		local submitted
		submitted, input = ImGui.InputText("##command", input, ImGui.InputTextFlags.EnterReturnsTrue)
		ImGui.SetItemDefaultFocus()
		if submitted then
			if string.find(input, "%S") then
				run(input)
			end
			input = ""
			ImGui.SetKeyboardFocusHere(-1) -- keep typing in the command line
		end
		ImGui.SameLine()
		ImGui.TextDisabled("Enter runs it")
	end
	ImGui.End()
end)

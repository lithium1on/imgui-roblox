-- A settings window that remembers everything between runs:
-- - window positions and sizes, through Dear ImGui's .ini data (Init's IniSettings and ImGui.SaveIniSettings);
-- - the settings themselves, as JSON saved with writefile;
-- - RightShift hides and shows the UI, and closing the window saves and shuts everything down.

local HttpService = game:GetService("HttpService")
local UserInputService = game:GetService("UserInputService")
local CONFIG_FILE = "imgui_example_settings.json"
local LAYOUT_FILE = "imgui_example_layout.ini"

local ImGui = loadstring(game:HttpGet("https://github.com/lithium1on/imgui-roblox/releases/latest/download/imgui.luau"))()

local settings = { walkSpeed = 16, jumpPower = 50, notifications = true, theme = 0 }
if isfile(CONFIG_FILE) then
	local ok, saved = pcall(function()
		return HttpService:JSONDecode(readfile(CONFIG_FILE))
	end)
	if ok and type(saved) == "table" then
		for key, value in saved do
			if type(value) == type(settings[key]) then
				settings[key] = value
			end
		end
	end
end

local THEMES = { "Dark", "Light", "Classic" }
ImGui.Init({
	Font = "Monospace",
	FontSize = 14,
	Theme = THEMES[settings.theme + 1],
	IniSettings = if isfile(LAYOUT_FILE) then readfile(LAYOUT_FILE) else nil,
})

local function save()
	writefile(CONFIG_FILE, HttpService:JSONEncode(settings))
	writefile(LAYOUT_FILE, ImGui.SaveIniSettings())
end

local shown, open = true, true
local toggleConnection = UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if not gameProcessed and input.KeyCode == Enum.KeyCode.RightShift then
		shown = not shown
	end
end)

ImGui.OnFrame(function()
	local io = ImGui.GetIO()
	if io.WantSaveIniSettings then -- set a few seconds after a window moves or is resized
		writefile(LAYOUT_FILE, ImGui.SaveIniSettings())
		io.WantSaveIniSettings = false
	end
	if not shown then
		return
	end

	ImGui.SetNextWindowSize(Vector2.new(360, 220), ImGui.Cond.FirstUseEver)
	local visible
	visible, open = ImGui.Begin("Settings", open) -- passing open adds the close button
	if visible then
		local _
		_, settings.walkSpeed = ImGui.SliderInt("WalkSpeed", settings.walkSpeed, 0, 100)
		_, settings.jumpPower = ImGui.SliderInt("JumpPower", settings.jumpPower, 0, 200)
		_, settings.notifications = ImGui.Checkbox("Notifications", settings.notifications)
		local changed
		changed, settings.theme = ImGui.Combo("Theme", settings.theme, THEMES)
		if changed then
			ImGui["StyleColors" .. THEMES[settings.theme + 1]]()
		end
		ImGui.Separator()
		if ImGui.Button("Save now") then
			save()
		end
		ImGui.SameLine()
		ImGui.TextDisabled("RightShift hides")
		ImGui.TextDisabled("Closing the window saves and shuts down")
	end
	ImGui.End()

	if not open then
		save()
		toggleConnection:Disconnect()
		ImGui.Shutdown() -- safe inside OnFrame: ImGui shuts down once this frame ends
	end
end)

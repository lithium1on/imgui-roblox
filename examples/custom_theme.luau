-- A fully custom theme: every color and the shape of widgets (rounding, padding, borders), plus a larger title font.
-- Pick a theme in the combo. The "Accent" button shows a one-off override with PushStyleColor and PushStyleVar.

local ImGui = loadstring(game:HttpGet("https://github.com/lithium1on/imgui-roblox/releases/latest/download/imgui.luau"))()
ImGui.Init({ Font = "Monospace", FontSize = 14 })
local titleFont = ImGui.AddFont("UI", 20)

-- 0xRRGGBB and an alpha from 0 to 1 -> the { r, g, b, a } table style colors use
local function hex(rgb, alpha)
	return { bit32.rshift(rgb, 16) % 256 / 255, bit32.rshift(rgb, 8) % 256 / 255, rgb % 256 / 255, alpha or 1 }
end

local THEMES = {
	{ name = "Midnight", accent = 0x7C5CFF, background = 0x121218, surface = 0x1C1C26, text = 0xE8E8F0 },
	{ name = "Forest", accent = 0x3DBE7A, background = 0x0F1714, surface = 0x18241E, text = 0xE3F2EA },
	{ name = "Sunset", accent = 0xFF7A45, background = 0x1A1210, surface = 0x281B17, text = 0xF7E9E3 },
}
local THEME_NAMES = {}
for index, theme in THEMES do
	THEME_NAMES[index] = theme.name
end

local function applyTheme(theme)
	local style = ImGui.GetStyle()
	style.WindowRounding = 8
	style.ChildRounding = 6
	style.FrameRounding = 5
	style.PopupRounding = 6
	style.GrabRounding = 5
	style.TabRounding = 5
	style.ScrollbarRounding = 8
	style.WindowBorderSize = 1
	style.FrameBorderSize = 0
	style.WindowPadding = Vector2.new(12, 12)
	style.FramePadding = Vector2.new(8, 5)
	style.ItemSpacing = Vector2.new(8, 7)
	style.WindowTitleAlign = Vector2.new(0.5, 0.5)

	local colors, Col = style.Colors, ImGui.Col
	colors[Col.Text] = hex(theme.text)
	colors[Col.TextDisabled] = hex(theme.text, 0.45)
	colors[Col.WindowBg] = hex(theme.background, 0.97)
	colors[Col.ChildBg] = hex(theme.surface, 0.6)
	colors[Col.PopupBg] = hex(theme.background, 0.98)
	colors[Col.Border] = hex(theme.accent, 0.35)
	colors[Col.FrameBg] = hex(theme.surface)
	colors[Col.FrameBgHovered] = hex(theme.accent, 0.25)
	colors[Col.FrameBgActive] = hex(theme.accent, 0.4)
	colors[Col.TitleBg] = hex(theme.surface)
	colors[Col.TitleBgActive] = hex(theme.accent, 0.85)
	colors[Col.TitleBgCollapsed] = hex(theme.surface, 0.7)
	colors[Col.MenuBarBg] = hex(theme.surface)
	colors[Col.ScrollbarBg] = hex(theme.background, 0)
	colors[Col.ScrollbarGrab] = hex(theme.accent, 0.4)
	colors[Col.ScrollbarGrabHovered] = hex(theme.accent, 0.6)
	colors[Col.ScrollbarGrabActive] = hex(theme.accent, 0.8)
	colors[Col.CheckMark] = hex(theme.accent)
	colors[Col.SliderGrab] = hex(theme.accent, 0.8)
	colors[Col.SliderGrabActive] = hex(theme.accent)
	colors[Col.Button] = hex(theme.accent, 0.55)
	colors[Col.ButtonHovered] = hex(theme.accent, 0.75)
	colors[Col.ButtonActive] = hex(theme.accent)
	colors[Col.Header] = hex(theme.accent, 0.35)
	colors[Col.HeaderHovered] = hex(theme.accent, 0.55)
	colors[Col.HeaderActive] = hex(theme.accent, 0.75)
	colors[Col.Separator] = hex(theme.accent, 0.3)
	colors[Col.Tab] = hex(theme.surface)
	colors[Col.TabHovered] = hex(theme.accent, 0.6)
	colors[Col.TabSelected] = hex(theme.accent, 0.8)
	colors[Col.PlotHistogram] = hex(theme.accent)
	colors[Col.TextSelectedBg] = hex(theme.accent, 0.35)
end

local current = 0
local enabled, volume = true, 0.6
applyTheme(THEMES[1])

ImGui.OnFrame(function()
	ImGui.SetNextWindowSize(Vector2.new(360, 300), ImGui.Cond.FirstUseEver)
	if ImGui.Begin("Custom theme") then
		ImGui.PushFont(titleFont, 20)
		ImGui.Text("%s", THEMES[current + 1].name)
		ImGui.PopFont()
		ImGui.Separator()

		local changed
		changed, current = ImGui.Combo("Theme", current, THEME_NAMES)
		if changed then
			applyTheme(THEMES[current + 1])
		end
		local _
		_, enabled = ImGui.Checkbox("Enabled", enabled)
		_, volume = ImGui.SliderFloat("Volume", volume, 0, 1)
		ImGui.ProgressBar(volume, Vector2.new(-1, 0))

		ImGui.Button("Normal button")
		ImGui.SameLine()
		ImGui.PushStyleColor(ImGui.Col.Button, ImGui.COL32(220, 60, 70))
		ImGui.PushStyleColor(ImGui.Col.ButtonHovered, ImGui.COL32(240, 90, 100))
		ImGui.PushStyleVar(ImGui.StyleVar.FrameRounding, 12)
		ImGui.Button("Accent")
		ImGui.PopStyleVar(1)
		ImGui.PopStyleColor(2)
	end
	ImGui.End()
end)

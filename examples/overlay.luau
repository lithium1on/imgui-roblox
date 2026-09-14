-- A stats overlay pinned to a corner of the screen: no title bar, clicks go through it, half transparent. It shows the
-- frame rate, a frame time graph and how long Dear ImGui itself takes, and draws a crosshair with the foreground draw
-- list. F9 moves the overlay to the next corner.

local ImGui = loadstring(game:HttpGet("https://github.com/lithium1on/imgui-roblox/releases/latest/download/imgui.luau"))()
ImGui.Init({ Font = "Monospace", FontSize = 13 })

local HISTORY = 90
local frameTimes = table.create(HISTORY, 0)
local newest = 0 -- index of the latest sample in frameTimes
local corner = 1 -- 0 top left, 1 top right, 2 bottom left, 3 bottom right
local MARGIN = 10
local OVERLAY_FLAGS = bit32.bor(
	ImGui.WindowFlags.NoDecoration,
	ImGui.WindowFlags.AlwaysAutoResize,
	ImGui.WindowFlags.NoSavedSettings,
	ImGui.WindowFlags.NoFocusOnAppearing,
	ImGui.WindowFlags.NoNav,
	ImGui.WindowFlags.NoInputs
)

ImGui.OnFrame(function()
	local io = ImGui.GetIO()
	newest = newest % HISTORY + 1
	frameTimes[newest] = io.DeltaTime * 1000
	if ImGui.IsKeyPressed(ImGui.Key.F9) then
		corner = (corner + 1) % 4
	end

	local viewport = ImGui.GetMainViewport()
	local workPos, workSize = viewport.WorkPos, viewport.WorkSize
	local right, bottom = corner % 2 == 1, corner >= 2
	local position = Vector2.new(
		if right then workPos.X + workSize.X - MARGIN else workPos.X + MARGIN,
		if bottom then workPos.Y + workSize.Y - MARGIN else workPos.Y + MARGIN
	)
	ImGui.SetNextWindowPos(position, ImGui.Cond.Always, Vector2.new(if right then 1 else 0, if bottom then 1 else 0))
	ImGui.SetNextWindowBgAlpha(0.35)
	if ImGui.Begin("Stats overlay", nil, OVERLAY_FLAGS) then
		local stats = ImGui.GetFrameStats()
		ImGui.Text("%.0f FPS (%.1f ms)", io.Framerate, 1000 / math.max(io.Framerate, 1))
		-- values_offset is the 0-based index of the oldest sample, so the graph scrolls
		ImGui.PlotLines("##frametime", frameTimes, newest % HISTORY, "frame time", 0, 50, Vector2.new(220, 40))
		ImGui.Text("Dear ImGui: %.2f ms, drawing %.2f ms", stats.Total * 1000, stats.Draw * 1000)
		ImGui.TextDisabled("%s mode, F9 moves this", ImGui.RenderMode)
	end
	ImGui.End()

	local center = io.DisplaySize * 0.5
	local drawList = ImGui.GetForegroundDrawList() -- drawn over every window
	local white, shadow = ImGui.COL32(255, 255, 255, 230), ImGui.COL32(0, 0, 0, 160)
	for _, pass in { { shadow, 3 }, { white, 1 } } do
		drawList:AddLine(center - Vector2.new(10, 0), center + Vector2.new(10, 0), pass[1], pass[2])
		drawList:AddLine(center - Vector2.new(0, 10), center + Vector2.new(0, 10), pass[1], pass[2])
	end
	drawList:AddCircle(center, 3, white, 12, 1)
end)

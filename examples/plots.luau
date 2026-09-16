-- Live plots with the ImPlot addon (implot.luau):
-- - a scrolling frame time graph with a shaded area and a limit line you can drag;
-- - a bar chart and a pie chart side by side in subplots;
-- - item styles (colors, line weights) passed as the last argument of each Plot function.

local ImPlotAddon = loadstring(game:HttpGet("https://github.com/lithium1on/imgui-roblox/releases/latest/download/implot.luau"))()
local ImGui = loadstring(game:HttpGet("https://github.com/lithium1on/imgui-roblox/releases/latest/download/imgui.luau"))()
ImGui.Init({ Font = "Monospace", FontSize = 13, Addons = ImPlotAddon })
local ImPlot = ImGui.ImPlot

local HISTORY = 240
local times, frameMs = {}, {}
local elapsed = 0
local limit = 20
local LIMIT_COLOR = Color3.new(1, 0.45, 0.35)

ImGui.OnFrame(function()
	local deltaTime = ImGui.GetIO().DeltaTime
	elapsed += deltaTime
	table.insert(times, elapsed)
	table.insert(frameMs, deltaTime * 1000)
	if #times > HISTORY then
		table.remove(times, 1)
		table.remove(frameMs, 1)
	end

	ImGui.SetNextWindowSize(Vector2.new(540, 560), ImGui.Cond.FirstUseEver)
	if ImGui.Begin("Performance") then
		if ImPlot.BeginPlot("Frame time", Vector2.new(-1, 230)) then
			ImPlot.SetupAxes("seconds", "ms", ImPlot.AxisFlags.NoTickLabels, ImPlot.AxisFlags.AutoFit)
			ImPlot.SetupAxisLimits(ImPlot.Axis.X1, math.max(elapsed - 4, 0), math.max(elapsed, 4), ImPlot.Cond.Always)
			ImPlot.PlotShaded("frame", times, frameMs, 0, { FillAlpha = 0.25 })
			ImPlot.PlotLine("frame", times, frameMs, { LineWeight = 2 })
			local _
			_, limit = ImPlot.DragLineY(1, limit, LIMIT_COLOR, 2)
			ImPlot.TagY(limit, LIMIT_COLOR, "limit")
			ImPlot.EndPlot()
		end

		if ImPlot.BeginSubplots("##charts", 1, 2, Vector2.new(-1, 260)) then
			if ImPlot.BeginPlot("Scores") then
				ImPlot.SetupAxes(nil, nil, ImPlot.AxisFlags.AutoFit, ImPlot.AxisFlags.AutoFit)
				ImPlot.PlotBars("round 1", { 12, 30, 22, 8 }, 0.6, { FillColor = Color3.new(0.3, 0.6, 1) })
				ImPlot.EndPlot()
			end
			if ImPlot.BeginPlot("Teams", Vector2.new(-1, -1), bit32.bor(ImPlot.Flags.Equal, ImPlot.Flags.NoMouseText)) then
				ImPlot.SetupAxes(nil, nil, ImPlot.AxisFlags.NoDecorations, ImPlot.AxisFlags.NoDecorations)
				ImPlot.SetupAxesLimits(0, 1, 0, 1)
				ImPlot.PlotPieChart({ "Red", "Blue", "Green" }, { 5, 3, 2 }, 0.5, 0.5, 0.4, "%.0f")
				ImPlot.EndPlot()
			end
			ImPlot.EndSubplots()
		end
	end
	ImGui.End()
end)

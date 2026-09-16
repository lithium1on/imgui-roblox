-- The ImPlot addon (implot.luau) linked into the bundle: every plot type draws inside a window with data and item specs,
-- setup, drag tools and queries return values, colormaps and enums are there, bad specs raise errors, nothing asserts.
local ImGui = ImGuiBundle
local W, H = 900, 700
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

local function near(a, b, tolerance)
	return type(a) == "number" and math.abs(a - b) <= (tolerance or 1e-3)
end

ImGui.Init({
	RenderMode = "DrawingImmediate", DrawingImmediate = MockDrawingImmediate, AutoRender = false, Input = false,
	DisplaySize = Vector2.new(W, H), Addons = ImGuiAddons.implot,
	MeasureText = function(_, size, text)
		return (utf8.len(text) or #text) * HarnessAdvance(size)
	end,
})
local ImPlot = ImGui.ImPlot

check("ImGui.ImPlot and its enums", ImPlot ~= nil and ImPlot.Axis.X1 == 0 and ImPlot.Axis.Y1 == 3 and ImPlot.Marker.Circle == 0
	and ImPlot.Location.NorthWest == ImPlot.Location.North + ImPlot.Location.West and ImPlot.Cond.Always ~= nil)
check(string.format("colormaps (%d)", ImPlot.GetColormapCount()), ImPlot.GetColormapCount() >= 16
	and ImPlot.GetColormapName(0) == "Deep" and ImPlot.GetColormapIndex("Viridis") == ImPlot.Colormap.Viridis)
local sample = ImPlot.SampleColormap(0.5, ImPlot.Colormap.Viridis)
check("SampleColormap returns a color", #sample == 4 and sample[4] == 1 and sample[1] >= 0 and sample[1] <= 1)
check("GetMarkerName", ImPlot.GetMarkerName(ImPlot.Marker.Square) == "Square")
check("an unknown spec field is an error", not pcall(ImPlot.PlotLine, "x", { 1, 2 }, { Bogus = 1 }))

local xs, ys = {}, {}
for i = 1, 50 do
	xs[i] = i
	ys[i] = math.sin(i / 5)
end

local seen = {}
ImGui.OnFrame(function()
	ImGui.SetNextWindowPos(Vector2.new(10, 10), ImGui.Cond.Always)
	ImGui.SetNextWindowSize(Vector2.new(860, 670), ImGui.Cond.Always)
	ImGui.Begin("Plots")
	if ImPlot.BeginPlot("Waves", Vector2.new(-1, 300)) then
		ImPlot.SetupAxes("time", "value")
		ImPlot.SetupAxesLimits(0, 60, -1.5, 1.5, ImPlot.Cond.Always)
		ImPlot.SetupLegend(ImPlot.Location.NorthEast)
		ImPlot.PlotLine("sine", xs, ys)
		ImPlot.PlotLine("scaled", ys, 1, 0, { LineColor = Color3.new(1, 0, 0), LineWeight = 2 })
		ImPlot.PlotScatter("points", xs, ys, { Marker = ImPlot.Marker.Square, MarkerSize = 3 })
		ImPlot.PlotStairs("stairs", ys)
		ImPlot.PlotShaded("band", xs, ys, 0, { FillAlpha = 0.25 })
		ImPlot.PlotBars("bars", { 0.5, 1, 0.25 }, 0.5)
		ImPlot.PlotStems("stems", xs, ys)
		ImPlot.PlotInfLines("marks", { 10, 20 })
		ImPlot.PlotDigital("digital", xs, ys)
		ImPlot.PlotText("center", 30, 1)
		seen.drag = { ImPlot.DragPoint(1, 25, 0.5, Color3.new(0, 1, 0)) }
		seen.line = { ImPlot.DragLineX(2, 45, Color3.new(1, 1, 0)) }
		ImPlot.TagX(40, Color3.new(1, 1, 0), "tagged")
		ImPlot.Annotation(5, 1, Color3.new(1, 1, 1), Vector2.new(10, -10), true, "note")
		seen.limits = { ImPlot.GetPlotLimits() }
		seen.size = ImPlot.GetPlotSize()
		seen.pixels = ImPlot.PlotToPixels(30, 0)
		seen.back = { ImPlot.PixelsToPlot(seen.pixels) }
		seen.hovered = ImPlot.IsPlotHovered()
		seen.drawList = ImPlot.GetPlotDrawList()
		seen.lastColor = ImPlot.GetLastItemColor()
		ImPlot.EndPlot()
	end
	if ImPlot.BeginSubplots("Grid", 1, 2, Vector2.new(-1, 300)) then
		if ImPlot.BeginPlot("Heat") then
			ImPlot.PushColormap(ImPlot.Colormap.Viridis)
			ImPlot.PlotHeatmap("heat", { { 1, 2, 3 }, { 4, 5, 6 } }, 0, 6)
			ImPlot.PopColormap()
			ImPlot.EndPlot()
		end
		if ImPlot.BeginPlot("Stats") then
			seen.histogram = ImPlot.PlotHistogram("hist", { 1, 1, 2, 3, 3, 3 }, 3)
			ImPlot.PlotPieChart({ "left", "right" }, { 1, 3 }, 0.5, 0.5, 0.4)
			ImPlot.PlotBarGroups({ "x", "y" }, { { 1, 2 }, { 3, 4 } })
			ImPlot.PlotErrorBars("errors", { 1, 2 }, { 1, 2 }, { 0.1, 0.2 })
			ImPlot.EndPlot()
		end
		ImPlot.EndSubplots()
	end
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

local function drawn(text)
	for _, call in DrawCalls do
		if call[1] == "text" and string.find(call[10], text, 1, true) then
			return true
		end
	end
	return false
end

frame()
frame()
frame()
check(string.format("frames run without errors (%d) or assertions (%d)", stepErrors, warnings), stepErrors == 0 and warnings == 0)
check("plot titles, legend entries, axis labels and texts are drawn", drawn("Waves") and drawn("sine") and drawn("scaled")
	and drawn("time") and drawn("center") and drawn("note") and drawn("Heat") and drawn("hist"))
check(string.format("SetupAxesLimits reaches the plot (%s)", table.concat(seen.limits or {}, ", ")),
	near(seen.limits[1], 0) and near(seen.limits[2], 60) and near(seen.limits[3], -1.5) and near(seen.limits[4], 1.5))
check("PlotToPixels and PixelsToPlot round-trip", near(seen.back[1], 30, 0.5) and near(seen.back[2], 0, 0.05)
	and seen.size.X > 100 and seen.size.Y > 100)
check("DragPoint and DragLineX return their values", seen.drag[1] == false and near(seen.drag[2], 25) and near(seen.drag[3], 0.5)
	and seen.line[1] == false and near(seen.line[2], 45))
check(string.format("PlotHistogram returns the largest bin (%s)", tostring(seen.histogram)), near(seen.histogram, 3))
check("GetPlotDrawList is a draw list handle", seen.drawList ~= nil and string.find(tostring(seen.drawList), "ImDrawList", 1, true) ~= nil)
check("GetLastItemColor returns a color", type(seen.lastColor) == "table" and #seen.lastColor == 4)

ImGui.Shutdown()
realPrint(string.format("RESULT %d failure(s)", failures))

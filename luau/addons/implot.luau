-- ImPlot addon (github.com/epezent/implot, MIT) as ImGui.ImPlot.
--
--     local ImPlotAddon = loadstring(game:HttpGet(".../implot.luau"))()
--     ImGui.Init({ Addons = ImPlotAddon })
--     local ImPlot = ImGui.ImPlot
--     if ImPlot.BeginPlot("Frame times") then
--         ImPlot.PlotLine("ms", history)
--         ImPlot.EndPlot()
--     end
--
-- Functions keep ImPlot's C++ names and argument order. Data is a table of numbers. Item styling is an optional last
-- table argument with ImPlotSpec fields: { LineColor = Color3.new(1, 0, 0), LineWeight = 2, Marker = ImPlot.Marker.Circle,
-- Flags = ImPlot.LineFlags.Shaded }. Colors are Color3 values, { r, g, b, a } tables (0-1) or ImU32 numbers.

local Modules, Enums, Common = ...

local sformat, min, max = string.format, math.min, math.max

local ImPlotAddon = { Name = "ImPlot", Protocol = 1, ImGuiVersion = "1.92.9b", Modules = Modules }

local SPEC_COLORS = { LineColor = true, FillColor = true, MarkerLineColor = true, MarkerFillColor = true }
local SPEC_FIELDS = { "LineColor", "LineWeight", "FillColor", "FillAlpha", "Marker", "MarkerSize", "MarkerLineColor", "MarkerFillColor", "Size", "Offset", "Flags" }

local function IsSpec(value)
	return type(value) == "table" and value[1] == nil and next(value) ~= nil and value.X == nil
end

local function IsArray(value)
	return type(value) == "table" and not IsSpec(value)
end

-- The arguments before a trailing spec table, their count, and the spec
local function Split(...)
	local count = select("#", ...)
	local args = { ... }
	while count > 0 and args[count] == nil do
		count -= 1
	end
	local spec = nil
	if count > 0 and IsSpec(args[count]) then
		spec = args[count]
		args[count] = nil
		count -= 1
	end
	return args, spec
end

function ImPlotAddon.Install(host)
	local C = Common(host)
	local Call, Release, String, Doubles, ColorU32, XY = C.Call, C.Release, C.String, C.Doubles, C.ColorU32, C.XY
	local E = C.Exports("rbx_implot_", {
		"init", "out", "begin_plot", "begin_subplots", "setup_axis", "setup_axis_format", "setup_axis_scale", "setup_axis_ticks",
		"setup_axis_ticks_range", "axis_range", "setup_axes", "axes_limits", "setup_location", "command", "text_op", "name",
		"query", "get", "plot_xy", "plot_values", "plot_error_bars", "plot_bar_groups", "plot_pie_chart", "plot_heatmap",
		"plot_histogram", "plot_histogram2d", "plot_text", "plot_dummy", "drag_point", "drag_line", "drag_rect", "annotation",
		"tag", "set_axes", "hide_next_item", "push_style_color", "push_style_var", "add_colormap", "colormap_scale",
		"colormap_slider", "colormap_button", "item_icon", "get_plot_draw_list", "push_plot_clip_rect",
	})
	Call(E.init)
	local out = (Call(E.out))
	local Prop, Cond = Enums.Prop, Enums.Cond

	local ImPlot = {}
	for name, values in Enums do
		ImPlot[name] = table.clone(values)
	end
	ImPlot.AUTO = -1

	local function Spec(spec)
		if spec == nil then
			return 0, 0
		end
		local values, count = {}, 0
		for key, value in spec do
			local prop = Prop[key]
			if prop == nil then
				error(sformat('[ImGui] unknown ImPlotSpec field "%s" (fields: %s)', tostring(key), table.concat(SPEC_FIELDS, ", ")), 3)
			end
			count += 1
			values[2 * count - 1] = prop
			values[2 * count] = if SPEC_COLORS[key] then ColorU32(value) else value
		end
		return (Doubles(values, 2 * count)), count
	end

	local function Out(count)
		return C.ReadDoubles(out, count)
	end

	local function Command(op, arg)
		Call(E.command, op, arg or 0)
	end

	local function TextOp(op, text, arg)
		local result = Call(E.text_op, op, (String(text)), arg or 0)
		Release()
		return result
	end

	---------------------------------------------------------------------------- plots and subplots

	function ImPlot.BeginPlot(title, size, flags)
		local width, height = -1, 0
		if size ~= nil then
			width, height = XY(size)
		end
		local result = Call(E.begin_plot, (String(title)), width, height, flags or 0) ~= 0
		Release()
		return result
	end

	function ImPlot.EndPlot()
		Command(0)
	end

	function ImPlot.BeginSubplots(title, rows, cols, size, flags)
		local width, height = XY(size)
		local result = Call(E.begin_subplots, (String(title)), rows, cols, width, height, flags or 0) ~= 0
		Release()
		return result
	end

	function ImPlot.EndSubplots()
		Command(1)
	end

	function ImPlot.BeginAlignedPlots(groupId, vertical)
		return TextOp(8, groupId, if vertical == false then 0 else 1) ~= 0
	end

	function ImPlot.EndAlignedPlots()
		Command(2)
	end

	---------------------------------------------------------------------------- setup

	function ImPlot.SetupAxis(axis, label, flags)
		Call(E.setup_axis, axis, (String(label)), flags or 0)
		Release()
	end

	function ImPlot.SetupAxisLimits(axis, vMin, vMax, cond)
		Call(E.axis_range, 0, axis, vMin, vMax, cond or Cond.Once)
	end

	function ImPlot.SetupAxisFormat(axis, format)
		Call(E.setup_axis_format, axis, (String(format)))
		Release()
	end

	-- (axis, values, labels?, keepDefault?) or (axis, vMin, vMax, count, labels?, keepDefault?)
	function ImPlot.SetupAxisTicks(axis, a, b, c, d, e)
		if type(a) == "table" then
			local ptr, count = Doubles(a)
			Call(E.setup_axis_ticks, axis, ptr, count, if b then C.Strings(b) else 0, if c then 1 else 0)
		else
			Call(E.setup_axis_ticks_range, axis, a, b, c, if d then C.Strings(d) else 0, if e then 1 else 0)
		end
		Release()
	end

	function ImPlot.SetupAxisScale(axis, scale)
		Call(E.setup_axis_scale, axis, scale)
	end

	function ImPlot.SetupAxisLimitsConstraints(axis, vMin, vMax)
		Call(E.axis_range, 1, axis, vMin, vMax, 0)
	end

	function ImPlot.SetupAxisZoomConstraints(axis, zMin, zMax)
		Call(E.axis_range, 2, axis, zMin, zMax, 0)
	end

	function ImPlot.SetupAxes(xLabel, yLabel, xFlags, yFlags)
		Call(E.setup_axes, (String(xLabel)), (String(yLabel)), xFlags or 0, yFlags or 0)
		Release()
	end

	function ImPlot.SetupAxesLimits(xMin, xMax, yMin, yMax, cond)
		Call(E.axes_limits, 0, xMin, xMax, yMin, yMax, cond or Cond.Once)
	end

	function ImPlot.SetupLegend(location, flags)
		Call(E.setup_location, 0, location, flags or 0)
	end

	function ImPlot.SetupMouseText(location, flags)
		Call(E.setup_location, 1, location, flags or 0)
	end

	function ImPlot.SetupFinish()
		Command(3)
	end

	function ImPlot.SetNextAxisLimits(axis, vMin, vMax, cond)
		Call(E.axis_range, 3, axis, vMin, vMax, cond or Cond.Once)
	end

	function ImPlot.SetNextAxisToFit(axis)
		Command(5, axis)
	end

	function ImPlot.SetNextAxesLimits(xMin, xMax, yMin, yMax, cond)
		Call(E.axes_limits, 1, xMin, xMax, yMin, yMax, cond or Cond.Once)
	end

	function ImPlot.SetNextAxesToFit()
		Command(4)
	end

	---------------------------------------------------------------------------- items

	-- Line, scatter and stairs: (label, values, xscale?, xstart?, spec?) or (label, xs, ys, spec?)
	local function LinePlot(kind)
		return function(label, ...)
			local args, spec = Split(...)
			local labelPtr = (String(label))
			local specPtr, specCount = Spec(spec)
			if IsArray(args[2]) then
				local count = min(#args[1], #args[2])
				Call(E.plot_xy, kind, labelPtr, (Doubles(args[1], count)), (Doubles(args[2], count)), 0, count, 0, specPtr, specCount)
			else
				local values = args[1]
				Call(E.plot_values, kind, labelPtr, (Doubles(values)), 0, #values, args[2] or 1, args[3] or 0, 0, specPtr, specCount)
			end
			Release()
		end
	end

	ImPlot.PlotLine = LinePlot(0)
	ImPlot.PlotScatter = LinePlot(1)
	ImPlot.PlotStairs = LinePlot(2)

	-- (label, values, yref?, xscale?, xstart?, spec?), (label, xs, ys, yref?, spec?) or (label, xs, ys1, ys2, spec?)
	function ImPlot.PlotShaded(label, ...)
		local args, spec = Split(...)
		local labelPtr = (String(label))
		local specPtr, specCount = Spec(spec)
		if IsArray(args[2]) then
			local xs, ys = args[1], args[2]
			if IsArray(args[3]) then
				local count = min(#xs, #ys, #args[3])
				Call(E.plot_xy, 8, labelPtr, (Doubles(xs, count)), (Doubles(ys, count)), (Doubles(args[3], count)), count, 0, specPtr, specCount)
			else
				local count = min(#xs, #ys)
				Call(E.plot_xy, 3, labelPtr, (Doubles(xs, count)), (Doubles(ys, count)), 0, count, args[3] or 0, specPtr, specCount)
			end
		else
			local values = args[1]
			Call(E.plot_values, 3, labelPtr, (Doubles(values)), 0, #values, args[2] or 0, args[3] or 1, args[4] or 0, specPtr, specCount)
		end
		Release()
	end

	-- (label, values, barSize?, shift?, spec?) or (label, xs, ys, barSize?, spec?)
	function ImPlot.PlotBars(label, ...)
		local args, spec = Split(...)
		local labelPtr = (String(label))
		local specPtr, specCount = Spec(spec)
		if IsArray(args[2]) then
			local count = min(#args[1], #args[2])
			Call(E.plot_xy, 4, labelPtr, (Doubles(args[1], count)), (Doubles(args[2], count)), 0, count, args[3] or 0.67, specPtr, specCount)
		else
			local values = args[1]
			Call(E.plot_values, 4, labelPtr, (Doubles(values)), 0, #values, args[2] or 0.67, args[3] or 0, 0, specPtr, specCount)
		end
		Release()
	end

	-- (label, values, ref?, scale?, start?, spec?) or (label, xs, ys, ref?, spec?)
	function ImPlot.PlotStems(label, ...)
		local args, spec = Split(...)
		local labelPtr = (String(label))
		local specPtr, specCount = Spec(spec)
		if IsArray(args[2]) then
			local count = min(#args[1], #args[2])
			Call(E.plot_xy, 5, labelPtr, (Doubles(args[1], count)), (Doubles(args[2], count)), 0, count, args[3] or 0, specPtr, specCount)
		else
			local values = args[1]
			Call(E.plot_values, 5, labelPtr, (Doubles(values)), 0, #values, args[2] or 0, args[3] or 1, args[4] or 0, specPtr, specCount)
		end
		Release()
	end

	-- (label, values, sizes, xscale?, xstart?, spec?) or (label, xs, ys, sizes, spec?)
	function ImPlot.PlotBubbles(label, ...)
		local args, spec = Split(...)
		local labelPtr = (String(label))
		local specPtr, specCount = Spec(spec)
		if IsArray(args[3]) then
			local count = min(#args[1], #args[2], #args[3])
			Call(E.plot_xy, 9, labelPtr, (Doubles(args[1], count)), (Doubles(args[2], count)), (Doubles(args[3], count)), count, 0, specPtr, specCount)
		else
			local count = min(#args[1], #args[2])
			Call(E.plot_values, 7, labelPtr, (Doubles(args[1], count)), (Doubles(args[2], count)), count, args[3] or 1, args[4] or 0, 0, specPtr, specCount)
		end
		Release()
	end

	local function XYPlot(kind)
		return function(label, xs, ys, spec)
			local count = min(#xs, #ys)
			local labelPtr = (String(label))
			local specPtr, specCount = Spec(spec)
			Call(E.plot_xy, kind, labelPtr, (Doubles(xs, count)), (Doubles(ys, count)), 0, count, 0, specPtr, specCount)
			Release()
		end
	end

	ImPlot.PlotDigital = XYPlot(6)
	ImPlot.PlotPolygon = XYPlot(7)

	function ImPlot.PlotInfLines(label, values, spec)
		local labelPtr = (String(label))
		local specPtr, specCount = Spec(spec)
		Call(E.plot_values, 6, labelPtr, (Doubles(values)), 0, #values, 0, 0, 0, specPtr, specCount)
		Release()
	end

	-- (label, xs, ys, err, spec?) or (label, xs, ys, neg, pos, spec?)
	function ImPlot.PlotErrorBars(label, xs, ys, ...)
		local args, spec = Split(...)
		local neg, pos = args[1], args[2] or args[1]
		local count = min(#xs, #ys, #neg, #pos)
		local labelPtr = (String(label))
		local specPtr, specCount = Spec(spec)
		local negPtr = (Doubles(neg, count))
		local posPtr = if pos == neg then negPtr else (Doubles(pos, count))
		Call(E.plot_error_bars, labelPtr, (Doubles(xs, count)), (Doubles(ys, count)), negPtr, posPtr, count, specPtr, specCount)
		Release()
	end

	-- values[item][group]
	function ImPlot.PlotBarGroups(labels, values, ...)
		local args, spec = Split(...)
		local items, groups = #values, if values[1] then #values[1] else 0
		local flat = table.create(items * groups)
		for item = 1, items do
			for group = 1, groups do
				flat[(item - 1) * groups + group] = values[item][group] or 0
			end
		end
		local specPtr, specCount = Spec(spec)
		Call(E.plot_bar_groups, C.Strings(labels), (Doubles(flat, items * groups)), items, groups, args[1] or 0.67, args[2] or 0, specPtr, specCount)
		Release()
	end

	-- format: printf format of the slice labels ("%.1f" by default), or false for none
	function ImPlot.PlotPieChart(labels, values, x, y, radius, ...)
		local args, spec = Split(...)
		local format = args[1]
		local formatPtr = if format == false then 0 else (String(format or "%.1f"))
		local count = min(#labels, #values)
		local specPtr, specCount = Spec(spec)
		Call(E.plot_pie_chart, C.Strings(labels), (Doubles(values, count)), count, x, y, radius, formatPtr, args[2] or 90, specPtr, specCount)
		Release()
	end

	-- values: rows of numbers ({ { ... }, { ... } }), or a flat table followed by rows and cols.
	-- Then (scaleMin?, scaleMax?, format?, boundsMin?, boundsMax?, spec?); format false hides the value labels
	function ImPlot.PlotHeatmap(label, values, ...)
		local args, spec = Split(...)
		local flat, rows, cols
		if type(values[1]) == "table" then
			rows, cols = #values, #values[1]
			flat = table.create(rows * cols)
			for row = 1, rows do
				for col = 1, cols do
					flat[(row - 1) * cols + col] = values[row][col] or 0
				end
			end
		else
			flat, rows, cols = values, table.remove(args, 1), table.remove(args, 1)
		end
		local format = args[3]
		local formatPtr = if format == false then 0 else (String(format or "%.1f"))
		local x0, y0 = XY(args[4] or { 0, 0 })
		local x1, y1 = XY(args[5] or { 1, 1 })
		local specPtr, specCount = Spec(spec)
		Call(E.plot_heatmap, (String(label)), (Doubles(flat, rows * cols)), rows, cols, args[1] or 0, args[2] or 0, formatPtr, x0, y0, x1, y1, specPtr, specCount)
		Release()
	end

	-- range: { min, max } (default: the values' range). Returns the largest bin count
	function ImPlot.PlotHistogram(label, values, ...)
		local args, spec = Split(...)
		local range = args[3] or { 0, 0 }
		local labelPtr = (String(label))
		local specPtr, specCount = Spec(spec)
		local result = Call(E.plot_histogram, labelPtr, (Doubles(values)), #values, args[1] or Enums.Bin.Sturges, args[2] or 1, range[1], range[2], specPtr, specCount)
		Release()
		return result
	end

	-- range: { xMin, xMax, yMin, yMax }. Returns the largest bin count
	function ImPlot.PlotHistogram2D(label, xs, ys, ...)
		local args, spec = Split(...)
		local range = args[3] or { 0, 0, 0, 0 }
		local count = min(#xs, #ys)
		local labelPtr = (String(label))
		local specPtr, specCount = Spec(spec)
		local result = Call(E.plot_histogram2d, labelPtr, (Doubles(xs, count)), (Doubles(ys, count)), count, args[1] or Enums.Bin.Sturges,
			args[2] or Enums.Bin.Sturges, range[1], range[2], range[3], range[4], specPtr, specCount)
		Release()
		return result
	end

	function ImPlot.PlotText(text, x, y, ...)
		local args, spec = Split(...)
		local px, py = XY(args[1])
		local textPtr = (String(text))
		local specPtr, specCount = Spec(spec)
		Call(E.plot_text, textPtr, x, y, px, py, specPtr, specCount)
		Release()
	end

	function ImPlot.PlotDummy(label, spec)
		local labelPtr = (String(label))
		local specPtr, specCount = Spec(spec)
		Call(E.plot_dummy, labelPtr, specPtr, specCount)
		Release()
	end

	---------------------------------------------------------------------------- tools

	-- Returns changed, x, y, clicked, hovered, held
	function ImPlot.DragPoint(id, x, y, color, size, flags)
		local changed = Call(E.drag_point, id, x, y, ColorU32(color), size or 4, flags or 0) ~= 0
		local nx, ny, clicked, hovered, held = Out(5)
		return changed, nx, ny, clicked ~= 0, hovered ~= 0, held ~= 0
	end

	local function DragLine(vertical)
		return function(id, value, color, thickness, flags)
			local changed = Call(E.drag_line, vertical, id, value, ColorU32(color), thickness or 1, flags or 0) ~= 0
			local nv, clicked, hovered, held = Out(4)
			return changed, nv, clicked ~= 0, hovered ~= 0, held ~= 0
		end
	end

	-- Return changed, value, clicked, hovered, held
	ImPlot.DragLineX = DragLine(0)
	ImPlot.DragLineY = DragLine(1)

	-- Returns changed, x1, y1, x2, y2, clicked, hovered, held
	function ImPlot.DragRect(id, x1, y1, x2, y2, color, flags)
		local changed = Call(E.drag_rect, id, x1, y1, x2, y2, ColorU32(color), flags or 0) ~= 0
		local a, b, c, d, clicked, hovered, held = Out(7)
		return changed, a, b, c, d, clicked ~= 0, hovered ~= 0, held ~= 0
	end

	-- text: nil shows the point's value
	function ImPlot.Annotation(x, y, color, pixelOffset, clamp, text)
		local px, py = XY(pixelOffset)
		Call(E.annotation, x, y, ColorU32(color), px, py, if clamp then 1 else 0, if text == nil then 0 else (String(text)))
		Release()
	end

	function ImPlot.TagX(x, color, text)
		Call(E.tag, 0, x, ColorU32(color), if text == nil then 0 else (String(text)))
		Release()
	end

	function ImPlot.TagY(y, color, text)
		Call(E.tag, 1, y, ColorU32(color), if text == nil then 0 else (String(text)))
		Release()
	end

	---------------------------------------------------------------------------- plot utilities

	function ImPlot.SetAxis(axis)
		Command(6, axis)
	end

	function ImPlot.SetAxes(xAxis, yAxis)
		Call(E.set_axes, xAxis, yAxis)
	end

	-- (pixels: Vector2, xAxis?, yAxis?) or (x, y, xAxis?, yAxis?). Returns x, y in plot units
	function ImPlot.PixelsToPlot(a, b, c, d)
		local x, y, xAxis, yAxis
		if type(a) == "number" then
			x, y, xAxis, yAxis = a, b, c, d
		else
			x, y = XY(a)
			xAxis, yAxis = b, c
		end
		Call(E.get, 0, x, y, xAxis or -1, yAxis or -1)
		return Out(2)
	end

	-- Returns a Vector2 in pixels
	function ImPlot.PlotToPixels(x, y, xAxis, yAxis)
		Call(E.get, 1, x, y, xAxis or -1, yAxis or -1)
		local px, py = Out(2)
		return Vector2.new(px, py)
	end

	function ImPlot.GetPlotPos()
		Call(E.get, 2, 0, 0, -1, -1)
		local x, y = Out(2)
		return Vector2.new(x, y)
	end

	function ImPlot.GetPlotSize()
		Call(E.get, 3, 0, 0, -1, -1)
		local x, y = Out(2)
		return Vector2.new(x, y)
	end

	-- Returns x, y
	function ImPlot.GetPlotMousePos(xAxis, yAxis)
		Call(E.get, 4, 0, 0, xAxis or -1, yAxis or -1)
		return Out(2)
	end

	-- Return xMin, xMax, yMin, yMax
	function ImPlot.GetPlotLimits(xAxis, yAxis)
		Call(E.get, 5, 0, 0, xAxis or -1, yAxis or -1)
		return Out(4)
	end

	function ImPlot.GetPlotSelection(xAxis, yAxis)
		Call(E.get, 6, 0, 0, xAxis or -1, yAxis or -1)
		return Out(4)
	end

	function ImPlot.IsPlotHovered()
		return Call(E.query, 0, 0) ~= 0
	end

	function ImPlot.IsAxisHovered(axis)
		return Call(E.query, 1, axis) ~= 0
	end

	function ImPlot.IsSubplotsHovered()
		return Call(E.query, 2, 0) ~= 0
	end

	function ImPlot.IsPlotSelected()
		return Call(E.query, 3, 0) ~= 0
	end

	function ImPlot.CancelPlotSelection()
		Command(7)
	end

	function ImPlot.HideNextItem(hidden, cond)
		Call(E.hide_next_item, if hidden == false then 0 else 1, cond or Cond.Once)
	end

	-- mouseButton: 0 left, 1 right (default)
	function ImPlot.BeginLegendPopup(labelId, mouseButton)
		return TextOp(0, labelId, mouseButton or 1) ~= 0
	end

	function ImPlot.EndLegendPopup()
		Command(8)
	end

	function ImPlot.IsLegendEntryHovered(labelId)
		return TextOp(1, labelId) ~= 0
	end

	function ImPlot.GetPlotDrawList()
		return host.Handle("ImDrawList", (Call(E.get_plot_draw_list)))
	end

	function ImPlot.PushPlotClipRect(expand)
		Call(E.push_plot_clip_rect, expand or 0)
	end

	function ImPlot.PopPlotClipRect()
		Command(20)
	end

	---------------------------------------------------------------------------- style and colormaps

	for op, name in { [13] = "StyleColorsAuto", [14] = "StyleColorsClassic", [15] = "StyleColorsDark", [16] = "StyleColorsLight" } do
		ImPlot[name] = function()
			Command(op)
		end
	end

	function ImPlot.PushStyleColor(index, color)
		Call(E.push_style_color, index, ColorU32(color))
	end

	function ImPlot.PopStyleColor(count)
		Command(9, count or 1)
	end

	-- value: a number, or a Vector2 for the ImVec2 variables
	function ImPlot.PushStyleVar(index, value)
		if type(value) == "number" then
			Call(E.push_style_var, index, value, 0, 0)
		else
			local x, y = XY(value)
			Call(E.push_style_var, index, x, y, 1)
		end
	end

	function ImPlot.PopStyleVar(count)
		Command(10, count or 1)
	end

	-- Returns { r, g, b, a }
	function ImPlot.GetLastItemColor()
		Call(E.get, 7, 0, 0, -1, -1)
		return { Out(4) }
	end

	function ImPlot.GetStyleColorName(index)
		return C.ReadString((Call(E.name, 0, index)))
	end

	function ImPlot.GetMarkerName(index)
		return C.ReadString((Call(E.name, 1, index)))
	end

	function ImPlot.NextMarker()
		return Call(E.query, 6, 0)
	end

	-- colors: Color3 values, { r, g, b, a } tables or ImU32 numbers. Returns the new colormap's index
	function ImPlot.AddColormap(name, colors, qualitative)
		local ptr = C.Alloc(max(#colors, 1) * 4)
		local mem = host.Mem()
		for index, color in colors do
			buffer.writeu32(mem, ptr + (index - 1) * 4, ColorU32(color))
		end
		local result = Call(E.add_colormap, (String(name)), ptr, #colors, if qualitative == false then 0 else 1)
		Release()
		return result
	end

	function ImPlot.GetColormapCount()
		return Call(E.query, 4, 0)
	end

	function ImPlot.GetColormapName(colormap)
		return C.ReadString((Call(E.name, 2, colormap)))
	end

	function ImPlot.GetColormapIndex(name)
		return TextOp(5, name)
	end

	-- colormap: an index (ImPlot.Colormap.Viridis) or a name
	function ImPlot.PushColormap(colormap)
		if type(colormap) == "string" then
			TextOp(6, colormap)
		else
			Command(12, colormap)
		end
	end

	function ImPlot.PopColormap(count)
		Command(11, count or 1)
	end

	-- The next three return { r, g, b, a }
	function ImPlot.NextColormapColor()
		Call(E.get, 8, 0, 0, -1, -1)
		return { Out(4) }
	end

	function ImPlot.GetColormapSize(colormap)
		return Call(E.query, 5, colormap or -1)
	end

	function ImPlot.GetColormapColor(index, colormap)
		Call(E.get, 9, index, 0, colormap or -1, -1)
		return { Out(4) }
	end

	function ImPlot.SampleColormap(t, colormap)
		Call(E.get, 10, t, 0, colormap or -1, -1)
		return { Out(4) }
	end

	function ImPlot.ColormapScale(label, scaleMin, scaleMax, size, format, flags, colormap)
		local width, height = XY(size)
		Call(E.colormap_scale, (String(label)), scaleMin, scaleMax, width, height, (String(format or "%g")), flags or 0, colormap or -1)
		Release()
	end

	-- Returns changed, t, { r, g, b, a }
	function ImPlot.ColormapSlider(label, t, format, colormap)
		local changed = Call(E.colormap_slider, (String(label)), t, (String(format or "")), colormap or -1) ~= 0
		Release()
		local value, r, g, b, a = Out(5)
		return changed, value, { r, g, b, a }
	end

	function ImPlot.ColormapButton(label, size, colormap)
		local width, height = XY(size)
		local result = Call(E.colormap_button, (String(label)), width, height, colormap or -1) ~= 0
		Release()
		return result
	end

	function ImPlot.BustColorCache(plotTitleId)
		TextOp(7, plotTitleId)
	end

	function ImPlot.ItemIcon(color)
		Call(E.item_icon, ColorU32(color))
	end

	function ImPlot.ColormapIcon(colormap)
		Command(19, colormap)
	end

	function ImPlot.MapInputDefault()
		Command(17)
	end

	function ImPlot.MapInputReverse()
		Command(18)
	end

	function ImPlot.ShowStyleSelector(label)
		return TextOp(2, label) ~= 0
	end

	function ImPlot.ShowColormapSelector(label)
		return TextOp(3, label) ~= 0
	end

	function ImPlot.ShowInputMapSelector(label)
		return TextOp(4, label) ~= 0
	end

	function ImPlot.ShowUserGuide()
		Command(21)
	end

	function ImPlot.ShowStyleEditor()
		Command(22)
	end

	function ImPlot.ShowMetricsWindow()
		Command(23)
	end

	return {
		Bind = function()
			return { ImPlot = ImPlot }
		end,
	}
end

return ImPlotAddon

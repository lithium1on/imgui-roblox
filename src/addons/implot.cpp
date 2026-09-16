// ImPlot addon (https://github.com/epezent/implot, MIT): plots; flat exports that luau/addons/implot.luau wraps as
// ImGui.ImPlot. Data arrives as double arrays, item styling as (ImPlotProp, value) pairs of doubles (colors as ImU32),
// and points, rectangles and colors come back through a small double buffer.
#include "addon_common.h"

#include "imgui.h"
#include "implot.h"

#include <cstdint>

namespace {

double g_out[8] = {};
ImPlotSpec g_spec;

ImVec4 Color(uint32_t color) { return ImGui::ColorConvertU32ToFloat4(color); }

const ImPlotSpec& Spec(const double* pairs, int count)
{
    g_spec = ImPlotSpec();
    for (int i = 0; i < count; i++)
    {
        const double value = pairs[2 * i + 1];
        switch ((ImPlotProp)(int)pairs[2 * i])
        {
        case ImPlotProp_LineColor: g_spec.LineColor = Color((uint32_t)value); break;
        case ImPlotProp_LineWeight: g_spec.LineWeight = (float)value; break;
        case ImPlotProp_FillColor: g_spec.FillColor = Color((uint32_t)value); break;
        case ImPlotProp_FillAlpha: g_spec.FillAlpha = (float)value; break;
        case ImPlotProp_Marker: g_spec.Marker = (ImPlotMarker)(int)value; break;
        case ImPlotProp_MarkerSize: g_spec.MarkerSize = (float)value; break;
        case ImPlotProp_MarkerLineColor: g_spec.MarkerLineColor = Color((uint32_t)value); break;
        case ImPlotProp_MarkerFillColor: g_spec.MarkerFillColor = Color((uint32_t)value); break;
        case ImPlotProp_Size: g_spec.Size = (float)value; break;
        case ImPlotProp_Offset: g_spec.Offset = (int)value; break;
        case ImPlotProp_Flags: g_spec.Flags = (ImPlotItemFlags)(int)value; break;
        default: break;
        }
    }
    return g_spec;
}

double* Out(double a, double b, double c = 0, double d = 0)
{
    g_out[0] = a;
    g_out[1] = b;
    g_out[2] = c;
    g_out[3] = d;
    return g_out;
}

double* Out(const ImVec4& color) { return Out(color.x, color.y, color.z, color.w); }
double* Out(const ImPlotRect& rect) { return Out(rect.X.Min, rect.X.Max, rect.Y.Min, rect.Y.Max); }

} // namespace

RBX_EXPORT void rbx_implot_init(void)
{
    if (ImPlot::GetCurrentContext() == nullptr)
        ImPlot::CreateContext();
}

RBX_EXPORT double* rbx_implot_out(void) { return g_out; }

RBX_EXPORT int rbx_implot_begin_plot(const char* title, double width, double height, int flags)
{
    return ImPlot::BeginPlot(title, ImVec2((float)width, (float)height), flags) ? 1 : 0;
}

RBX_EXPORT int rbx_implot_begin_subplots(const char* title, int rows, int cols, double width, double height, int flags)
{
    return ImPlot::BeginSubplots(title, rows, cols, ImVec2((float)width, (float)height), flags) ? 1 : 0;
}

RBX_EXPORT void rbx_implot_setup_axis(int axis, const char* label, int flags) { ImPlot::SetupAxis(axis, label, flags); }
RBX_EXPORT void rbx_implot_setup_axis_format(int axis, const char* format) { ImPlot::SetupAxisFormat(axis, format); }
RBX_EXPORT void rbx_implot_setup_axis_scale(int axis, int scale) { ImPlot::SetupAxisScale(axis, scale); }

RBX_EXPORT void rbx_implot_setup_axis_ticks(int axis, const double* values, int count, const char* const* labels, int keep_default)
{
    ImPlot::SetupAxisTicks(axis, values, count, labels, keep_default != 0);
}

RBX_EXPORT void rbx_implot_setup_axis_ticks_range(int axis, double min, double max, int count, const char* const* labels, int keep_default)
{
    ImPlot::SetupAxisTicks(axis, min, max, count, labels, keep_default != 0);
}

// op 0: SetupAxisLimits, 1: SetupAxisLimitsConstraints, 2: SetupAxisZoomConstraints, 3: SetNextAxisLimits
RBX_EXPORT void rbx_implot_axis_range(int op, int axis, double a, double b, int cond)
{
    switch (op)
    {
    case 0: ImPlot::SetupAxisLimits(axis, a, b, cond); break;
    case 1: ImPlot::SetupAxisLimitsConstraints(axis, a, b); break;
    case 2: ImPlot::SetupAxisZoomConstraints(axis, a, b); break;
    case 3: ImPlot::SetNextAxisLimits(axis, a, b, cond); break;
    }
}

RBX_EXPORT void rbx_implot_setup_axes(const char* x_label, const char* y_label, int x_flags, int y_flags)
{
    ImPlot::SetupAxes(x_label, y_label, x_flags, y_flags);
}

// op 0: SetupAxesLimits, 1: SetNextAxesLimits
RBX_EXPORT void rbx_implot_axes_limits(int op, double x_min, double x_max, double y_min, double y_max, int cond)
{
    if (op == 0)
        ImPlot::SetupAxesLimits(x_min, x_max, y_min, y_max, cond);
    else
        ImPlot::SetNextAxesLimits(x_min, x_max, y_min, y_max, cond);
}

// op 0: SetupLegend, 1: SetupMouseText
RBX_EXPORT void rbx_implot_setup_location(int op, int location, int flags)
{
    if (op == 0)
        ImPlot::SetupLegend(location, flags);
    else
        ImPlot::SetupMouseText(location, flags);
}

// op 0: EndPlot, 1: EndSubplots, 2: EndAlignedPlots, 3: SetupFinish, 4: SetNextAxesToFit, 5: SetNextAxisToFit(arg),
// 6: SetAxis(arg), 7: CancelPlotSelection, 8: EndLegendPopup, 9: PopStyleColor(arg), 10: PopStyleVar(arg),
// 11: PopColormap(arg), 12: PushColormap(arg), 13-16: StyleColorsAuto, Classic, Dark, Light, 17: MapInputDefault,
// 18: MapInputReverse, 19: ColormapIcon(arg), 20: PopPlotClipRect, 21: ShowUserGuide, 22: ShowStyleEditor,
// 23: ShowMetricsWindow
RBX_EXPORT void rbx_implot_command(int op, int arg)
{
    switch (op)
    {
    case 0: ImPlot::EndPlot(); break;
    case 1: ImPlot::EndSubplots(); break;
    case 2: ImPlot::EndAlignedPlots(); break;
    case 3: ImPlot::SetupFinish(); break;
    case 4: ImPlot::SetNextAxesToFit(); break;
    case 5: ImPlot::SetNextAxisToFit(arg); break;
    case 6: ImPlot::SetAxis(arg); break;
    case 7: ImPlot::CancelPlotSelection(); break;
    case 8: ImPlot::EndLegendPopup(); break;
    case 9: ImPlot::PopStyleColor(arg); break;
    case 10: ImPlot::PopStyleVar(arg); break;
    case 11: ImPlot::PopColormap(arg); break;
    case 12: ImPlot::PushColormap(arg); break;
    case 13: ImPlot::StyleColorsAuto(); break;
    case 14: ImPlot::StyleColorsClassic(); break;
    case 15: ImPlot::StyleColorsDark(); break;
    case 16: ImPlot::StyleColorsLight(); break;
    case 17: ImPlot::MapInputDefault(); break;
    case 18: ImPlot::MapInputReverse(); break;
    case 19: ImPlot::ColormapIcon(arg); break;
    case 20: ImPlot::PopPlotClipRect(); break;
    case 21: ImPlot::ShowUserGuide(); break;
    case 22: ImPlot::ShowStyleEditor(); break;
    case 23: ImPlot::ShowMetricsWindow(); break;
    }
}

// op 0: BeginLegendPopup(arg = mouse button), 1: IsLegendEntryHovered, 2: ShowStyleSelector, 3: ShowColormapSelector,
// 4: ShowInputMapSelector, 5: GetColormapIndex, 6: PushColormap(name), 7: BustColorCache (NULL for every plot),
// 8: BeginAlignedPlots(arg = vertical)
RBX_EXPORT int rbx_implot_text_op(int op, const char* text, int arg)
{
    switch (op)
    {
    case 0: return ImPlot::BeginLegendPopup(text, arg) ? 1 : 0;
    case 1: return ImPlot::IsLegendEntryHovered(text) ? 1 : 0;
    case 2: return ImPlot::ShowStyleSelector(text) ? 1 : 0;
    case 3: return ImPlot::ShowColormapSelector(text) ? 1 : 0;
    case 4: return ImPlot::ShowInputMapSelector(text) ? 1 : 0;
    case 5: return ImPlot::GetColormapIndex(text);
    case 6: ImPlot::PushColormap(text); return 0;
    case 7: ImPlot::BustColorCache(text); return 0;
    case 8: return ImPlot::BeginAlignedPlots(text, arg != 0) ? 1 : 0;
    }
    return 0;
}

// op 0: GetStyleColorName, 1: GetMarkerName, 2: GetColormapName
RBX_EXPORT const char* rbx_implot_name(int op, int index)
{
    switch (op)
    {
    case 0: return ImPlot::GetStyleColorName(index);
    case 1: return ImPlot::GetMarkerName(index);
    default: return ImPlot::GetColormapName(index);
    }
}

// op 0: IsPlotHovered, 1: IsAxisHovered(arg), 2: IsSubplotsHovered, 3: IsPlotSelected, 4: GetColormapCount,
// 5: GetColormapSize(arg), 6: NextMarker
RBX_EXPORT int rbx_implot_query(int op, int arg)
{
    switch (op)
    {
    case 0: return ImPlot::IsPlotHovered() ? 1 : 0;
    case 1: return ImPlot::IsAxisHovered(arg) ? 1 : 0;
    case 2: return ImPlot::IsSubplotsHovered() ? 1 : 0;
    case 3: return ImPlot::IsPlotSelected() ? 1 : 0;
    case 4: return ImPlot::GetColormapCount();
    case 5: return ImPlot::GetColormapSize(arg);
    case 6: return ImPlot::NextMarker();
    }
    return 0;
}

// Results in the out buffer. op 0: PixelsToPlot(a, b), 1: PlotToPixels(a, b), 2: GetPlotPos, 3: GetPlotSize,
// 4: GetPlotMousePos, 5: GetPlotLimits, 6: GetPlotSelection, 7: GetLastItemColor, 8: NextColormapColor,
// 9: GetColormapColor(index a, colormap x_axis), 10: SampleColormap(t a, colormap x_axis)
RBX_EXPORT double* rbx_implot_get(int op, double a, double b, int x_axis, int y_axis)
{
    switch (op)
    {
    case 0: { ImPlotPoint p = ImPlot::PixelsToPlot((float)a, (float)b, x_axis, y_axis); return Out(p.x, p.y); }
    case 1: { ImVec2 p = ImPlot::PlotToPixels(a, b, x_axis, y_axis); return Out(p.x, p.y); }
    case 2: { ImVec2 p = ImPlot::GetPlotPos(); return Out(p.x, p.y); }
    case 3: { ImVec2 p = ImPlot::GetPlotSize(); return Out(p.x, p.y); }
    case 4: { ImPlotPoint p = ImPlot::GetPlotMousePos(x_axis, y_axis); return Out(p.x, p.y); }
    case 5: return Out(ImPlot::GetPlotLimits(x_axis, y_axis));
    case 6: return Out(ImPlot::GetPlotSelection(x_axis, y_axis));
    case 7: return Out(ImPlot::GetLastItemColor());
    case 8: return Out(ImPlot::NextColormapColor());
    case 9: return Out(ImPlot::GetColormapColor((int)a, x_axis));
    case 10: return Out(ImPlot::SampleColormap((float)a, x_axis));
    }
    return g_out;
}

// kind 0: PlotLine, 1: PlotScatter, 2: PlotStairs, 3: PlotShaded (a: yref), 4: PlotBars (a: bar size),
// 5: PlotStems (a: ref), 6: PlotDigital, 7: PlotPolygon, 8: PlotShaded between ys and extra, 9: PlotBubbles (extra: sizes)
RBX_EXPORT void rbx_implot_plot_xy(int kind, const char* label, const double* xs, const double* ys, const double* extra, int count,
                                   double a, const double* spec, int spec_count)
{
    const ImPlotSpec& s = Spec(spec, spec_count);
    switch (kind)
    {
    case 0: ImPlot::PlotLine(label, xs, ys, count, s); break;
    case 1: ImPlot::PlotScatter(label, xs, ys, count, s); break;
    case 2: ImPlot::PlotStairs(label, xs, ys, count, s); break;
    case 3: ImPlot::PlotShaded(label, xs, ys, count, a, s); break;
    case 4: ImPlot::PlotBars(label, xs, ys, count, a, s); break;
    case 5: ImPlot::PlotStems(label, xs, ys, count, a, s); break;
    case 6: ImPlot::PlotDigital(label, xs, ys, count, s); break;
    case 7: ImPlot::PlotPolygon(label, xs, ys, count, s); break;
    case 8: ImPlot::PlotShaded(label, xs, ys, extra, count, s); break;
    case 9: ImPlot::PlotBubbles(label, xs, ys, extra, count, s); break;
    }
}

// kind 0: PlotLine, 1: PlotScatter, 2: PlotStairs (a: xscale, b: xstart), 3: PlotShaded (a: yref, b: xscale, c: xstart),
// 4: PlotBars (a: bar size, b: shift), 5: PlotStems (a: ref, b: scale, c: start), 6: PlotInfLines,
// 7: PlotBubbles (extra: sizes, a: xscale, b: xstart)
RBX_EXPORT void rbx_implot_plot_values(int kind, const char* label, const double* values, const double* extra, int count,
                                       double a, double b, double c, const double* spec, int spec_count)
{
    const ImPlotSpec& s = Spec(spec, spec_count);
    switch (kind)
    {
    case 0: ImPlot::PlotLine(label, values, count, a, b, s); break;
    case 1: ImPlot::PlotScatter(label, values, count, a, b, s); break;
    case 2: ImPlot::PlotStairs(label, values, count, a, b, s); break;
    case 3: ImPlot::PlotShaded(label, values, count, a, b, c, s); break;
    case 4: ImPlot::PlotBars(label, values, count, a, b, s); break;
    case 5: ImPlot::PlotStems(label, values, count, a, b, c, s); break;
    case 6: ImPlot::PlotInfLines(label, values, count, s); break;
    case 7: ImPlot::PlotBubbles(label, values, extra, count, a, b, s); break;
    }
}

RBX_EXPORT void rbx_implot_plot_error_bars(const char* label, const double* xs, const double* ys, const double* neg, const double* pos,
                                           int count, const double* spec, int spec_count)
{
    ImPlot::PlotErrorBars(label, xs, ys, neg, pos, count, Spec(spec, spec_count));
}

RBX_EXPORT void rbx_implot_plot_bar_groups(const char* const* labels, const double* values, int items, int groups, double group_size,
                                           double shift, const double* spec, int spec_count)
{
    ImPlot::PlotBarGroups(labels, values, items, groups, group_size, shift, Spec(spec, spec_count));
}

RBX_EXPORT void rbx_implot_plot_pie_chart(const char* const* labels, const double* values, int count, double x, double y, double radius,
                                          const char* format, double angle0, const double* spec, int spec_count)
{
    ImPlot::PlotPieChart(labels, values, count, x, y, radius, format, angle0, Spec(spec, spec_count));
}

RBX_EXPORT void rbx_implot_plot_heatmap(const char* label, const double* values, int rows, int cols, double scale_min, double scale_max,
                                        const char* format, double x0, double y0, double x1, double y1, const double* spec, int spec_count)
{
    ImPlot::PlotHeatmap(label, values, rows, cols, scale_min, scale_max, format, ImPlotPoint(x0, y0), ImPlotPoint(x1, y1), Spec(spec, spec_count));
}

RBX_EXPORT double rbx_implot_plot_histogram(const char* label, const double* values, int count, int bins, double bar_scale,
                                            double range_min, double range_max, const double* spec, int spec_count)
{
    return ImPlot::PlotHistogram(label, values, count, bins, bar_scale, ImPlotRange(range_min, range_max), Spec(spec, spec_count));
}

RBX_EXPORT double rbx_implot_plot_histogram2d(const char* label, const double* xs, const double* ys, int count, int x_bins, int y_bins,
                                              double x_min, double x_max, double y_min, double y_max, const double* spec, int spec_count)
{
    return ImPlot::PlotHistogram2D(label, xs, ys, count, x_bins, y_bins, ImPlotRect(x_min, x_max, y_min, y_max), Spec(spec, spec_count));
}

RBX_EXPORT void rbx_implot_plot_text(const char* text, double x, double y, double pixel_x, double pixel_y, const double* spec, int spec_count)
{
    ImPlot::PlotText(text, x, y, ImVec2((float)pixel_x, (float)pixel_y), Spec(spec, spec_count));
}

RBX_EXPORT void rbx_implot_plot_dummy(const char* label, const double* spec, int spec_count) { ImPlot::PlotDummy(label, Spec(spec, spec_count)); }

// Out: x, y, clicked, hovered, held
RBX_EXPORT int rbx_implot_drag_point(int id, double x, double y, uint32_t color, double size, int flags)
{
    bool clicked = false, hovered = false, held = false;
    const bool changed = ImPlot::DragPoint(id, &x, &y, Color(color), (float)size, flags, &clicked, &hovered, &held);
    Out(x, y, clicked, hovered);
    g_out[4] = held;
    return changed ? 1 : 0;
}

// vertical 0: DragLineX, 1: DragLineY. Out: value, clicked, hovered, held
RBX_EXPORT int rbx_implot_drag_line(int vertical, int id, double value, uint32_t color, double thickness, int flags)
{
    bool clicked = false, hovered = false, held = false;
    const bool changed = vertical ? ImPlot::DragLineY(id, &value, Color(color), (float)thickness, flags, &clicked, &hovered, &held)
                                  : ImPlot::DragLineX(id, &value, Color(color), (float)thickness, flags, &clicked, &hovered, &held);
    Out(value, clicked, hovered, held);
    return changed ? 1 : 0;
}

// Out: x1, y1, x2, y2, clicked, hovered, held
RBX_EXPORT int rbx_implot_drag_rect(int id, double x1, double y1, double x2, double y2, uint32_t color, int flags)
{
    bool clicked = false, hovered = false, held = false;
    const bool changed = ImPlot::DragRect(id, &x1, &y1, &x2, &y2, Color(color), flags, &clicked, &hovered, &held);
    Out(x1, y1, x2, y2);
    g_out[4] = clicked;
    g_out[5] = hovered;
    g_out[6] = held;
    return changed ? 1 : 0;
}

// text NULL: the value at (x, y), else the text
RBX_EXPORT void rbx_implot_annotation(double x, double y, uint32_t color, double pixel_x, double pixel_y, int clamp, const char* text)
{
    const ImVec2 offset((float)pixel_x, (float)pixel_y);
    if (text != nullptr)
        ImPlot::Annotation(x, y, Color(color), offset, clamp != 0, "%s", text);
    else
        ImPlot::Annotation(x, y, Color(color), offset, clamp != 0, false);
}

// y_axis 0: TagX, 1: TagY; text NULL shows the value
RBX_EXPORT void rbx_implot_tag(int y_axis, double value, uint32_t color, const char* text)
{
    if (y_axis)
    {
        if (text != nullptr)
            ImPlot::TagY(value, Color(color), "%s", text);
        else
            ImPlot::TagY(value, Color(color), false);
    }
    else
    {
        if (text != nullptr)
            ImPlot::TagX(value, Color(color), "%s", text);
        else
            ImPlot::TagX(value, Color(color), false);
    }
}

RBX_EXPORT void rbx_implot_set_axes(int x_axis, int y_axis) { ImPlot::SetAxes(x_axis, y_axis); }
RBX_EXPORT void rbx_implot_hide_next_item(int hidden, int cond) { ImPlot::HideNextItem(hidden != 0, cond); }
RBX_EXPORT void rbx_implot_push_style_color(int index, uint32_t color) { ImPlot::PushStyleColor(index, color); }

RBX_EXPORT void rbx_implot_push_style_var(int index, double x, double y, int is_vec2)
{
    if (is_vec2)
        ImPlot::PushStyleVar(index, ImVec2((float)x, (float)y));
    else
        ImPlot::PushStyleVar(index, (float)x);
}

RBX_EXPORT int rbx_implot_add_colormap(const char* name, const uint32_t* colors, int count, int qualitative)
{
    return ImPlot::AddColormap(name, colors, count, qualitative != 0);
}

RBX_EXPORT void rbx_implot_colormap_scale(const char* label, double min, double max, double width, double height, const char* format,
                                          int flags, int colormap)
{
    ImPlot::ColormapScale(label, min, max, ImVec2((float)width, (float)height), format, flags, colormap);
}

// Out: t, r, g, b, a
RBX_EXPORT int rbx_implot_colormap_slider(const char* label, double t, const char* format, int colormap)
{
    float value = (float)t;
    ImVec4 color;
    const bool changed = ImPlot::ColormapSlider(label, &value, &color, format, colormap);
    Out(value, color.x, color.y, color.z);
    g_out[4] = color.w;
    return changed ? 1 : 0;
}

RBX_EXPORT int rbx_implot_colormap_button(const char* label, double width, double height, int colormap)
{
    return ImPlot::ColormapButton(label, ImVec2((float)width, (float)height), colormap) ? 1 : 0;
}

RBX_EXPORT void rbx_implot_item_icon(uint32_t color) { ImPlot::ItemIcon(color); }
RBX_EXPORT ImDrawList* rbx_implot_get_plot_draw_list(void) { return ImPlot::GetPlotDrawList(); }
RBX_EXPORT void rbx_implot_push_plot_clip_rect(double expand) { ImPlot::PushPlotClipRect((float)expand); }

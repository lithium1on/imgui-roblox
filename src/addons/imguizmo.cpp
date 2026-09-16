// ImGuizmo addon (https://github.com/CedricGuillemet/ImGuizmo, MIT): flat exports that luau/addons/imguizmo.luau wraps
// as ImGui.ImGuizmo. Matrices are column-major float[16] in one buffer block the Luau side reads and writes directly.
#include "addon_common.h"

#include "imgui.h"
#include "ImGuizmo.h"

#include <cstdint>

namespace {

// Float slots: view 0, projection 16, matrix 32, delta 48, snap 64, bounds 67, boundsSnap 73, translation 76,
// rotation 79, scale 82 (same order in imguizmo.luau)
struct Buffers {
    float view[16];
    float projection[16];
    float matrix[16];
    float delta[16];
    float snap[3];
    float bounds[6];
    float boundsSnap[3];
    float translation[3];
    float rotation[3];
    float scale[3];
};

Buffers g_buffers = {};

} // namespace

RBX_EXPORT float* rbx_imguizmo_buffers(void) { return g_buffers.view; }

RBX_EXPORT void rbx_imguizmo_begin_frame(void) { ImGuizmo::BeginFrame(); }
RBX_EXPORT void rbx_imguizmo_set_drawlist(ImDrawList* draw_list) { ImGuizmo::SetDrawlist(draw_list); }
RBX_EXPORT void rbx_imguizmo_set_rect(double x, double y, double width, double height) { ImGuizmo::SetRect((float)x, (float)y, (float)width, (float)height); }
RBX_EXPORT void rbx_imguizmo_set_orthographic(int orthographic) { ImGuizmo::SetOrthographic(orthographic != 0); }
RBX_EXPORT void rbx_imguizmo_enable(int enable) { ImGuizmo::Enable(enable != 0); }
RBX_EXPORT void rbx_imguizmo_set_id(int id) { ImGuizmo::SetID(id); }
RBX_EXPORT void rbx_imguizmo_push_id(const char* id) { ImGuizmo::PushID(id); }
RBX_EXPORT void rbx_imguizmo_push_id_int(int id) { ImGuizmo::PushID(id); }
RBX_EXPORT void rbx_imguizmo_pop_id(void) { ImGuizmo::PopID(); }
RBX_EXPORT void rbx_imguizmo_set_axis_mask(int x, int y, int z) { ImGuizmo::SetAxisMask(x != 0, y != 0, z != 0); }

RBX_EXPORT int rbx_imguizmo_manipulate(int operation, int mode, int use_snap, int use_bounds)
{
    Buffers& b = g_buffers;
    return ImGuizmo::Manipulate(b.view, b.projection, (ImGuizmo::OPERATION)operation, (ImGuizmo::MODE)mode, b.matrix, b.delta,
                                use_snap ? b.snap : nullptr, use_bounds ? b.bounds : nullptr, use_bounds ? b.boundsSnap : nullptr) ? 1 : 0;
}

RBX_EXPORT void rbx_imguizmo_view_manipulate(double length, double x, double y, double width, double height, uint32_t background)
{
    ImGuizmo::ViewManipulate(g_buffers.view, (float)length, ImVec2((float)x, (float)y), ImVec2((float)width, (float)height), background);
}

RBX_EXPORT void rbx_imguizmo_decompose(void)
{
    ImGuizmo::DecomposeMatrixToComponents(g_buffers.matrix, g_buffers.translation, g_buffers.rotation, g_buffers.scale);
}

RBX_EXPORT void rbx_imguizmo_recompose(void)
{
    ImGuizmo::RecomposeMatrixFromComponents(g_buffers.translation, g_buffers.rotation, g_buffers.scale, g_buffers.matrix);
}

// what 0: DrawGrid(size), 1: DrawCubes, 2: DrawAxes, all with the matrix slot
RBX_EXPORT void rbx_imguizmo_draw(int what, double grid_size)
{
    Buffers& b = g_buffers;
    switch (what)
    {
    case 0: ImGuizmo::DrawGrid(b.view, b.projection, b.matrix, (float)grid_size); break;
    case 1: ImGuizmo::DrawCubes(b.view, b.projection, b.matrix, 1); break;
    case 2: ImGuizmo::DrawAxes(b.view, b.projection, b.matrix, 1); break;
    }
}

// op 0: IsOver, 1: IsUsing, 2: IsUsingViewManipulate, 3: IsViewManipulateHovered, 4: IsUsingAny, 5: IsOver(operation)
RBX_EXPORT int rbx_imguizmo_query(int op, int operation)
{
    switch (op)
    {
    case 0: return ImGuizmo::IsOver() ? 1 : 0;
    case 1: return ImGuizmo::IsUsing() ? 1 : 0;
    case 2: return ImGuizmo::IsUsingViewManipulate() ? 1 : 0;
    case 3: return ImGuizmo::IsViewManipulateHovered() ? 1 : 0;
    case 4: return ImGuizmo::IsUsingAny() ? 1 : 0;
    case 5: return ImGuizmo::IsOver((ImGuizmo::OPERATION)operation) ? 1 : 0;
    }
    return 0;
}

// op 0: SetGizmoSizeClipSpace, 1: AllowAxisFlip, 2: SetAxisLimit, 3: SetPlaneLimit
RBX_EXPORT void rbx_imguizmo_setting(int op, double value)
{
    switch (op)
    {
    case 0: ImGuizmo::SetGizmoSizeClipSpace((float)value); break;
    case 1: ImGuizmo::AllowAxisFlip(value != 0.0); break;
    case 2: ImGuizmo::SetAxisLimit((float)value); break;
    case 3: ImGuizmo::SetPlaneLimit((float)value); break;
    }
}

// Style floats in declaration order: TranslationLineThickness ... CenterCircleSize
static float* StyleFloat(int field)
{
    ImGuizmo::Style& style = ImGuizmo::GetStyle();
    float* fields[] = {
        &style.TranslationLineThickness, &style.TranslationLineArrowSize, &style.RotationLineThickness,
        &style.RotationOuterLineThickness, &style.ScaleLineThickness, &style.ScaleLineCircleSize,
        &style.HatchedAxisLineThickness, &style.CenterCircleSize,
    };
    return field >= 0 && field < 8 ? fields[field] : nullptr;
}

RBX_EXPORT double rbx_imguizmo_style_get(int field)
{
    float* value = StyleFloat(field);
    return value != nullptr ? *value : 0.0;
}

RBX_EXPORT void rbx_imguizmo_style_set(int field, double value)
{
    if (float* target = StyleFloat(field))
        *target = (float)value;
}

RBX_EXPORT uint32_t rbx_imguizmo_style_color_get(int index)
{
    if (index < 0 || index >= ImGuizmo::COLOR::COUNT)
        return 0;
    return ImGui::ColorConvertFloat4ToU32(ImGuizmo::GetStyle().Colors[index]);
}

RBX_EXPORT void rbx_imguizmo_style_color_set(int index, uint32_t color)
{
    if (index >= 0 && index < ImGuizmo::COLOR::COUNT)
        ImGuizmo::GetStyle().Colors[index] = ImGui::ColorConvertU32ToFloat4(color);
}

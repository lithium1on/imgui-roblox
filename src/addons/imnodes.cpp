// imnodes addon (https://github.com/Nelarius/imnodes, MIT): node editor; flat exports that luau/addons/imnodes.luau
// wraps as ImGui.ImNodes. Out parameters go to small buffers the Luau side reads.
#define IMGUI_DEFINE_MATH_OPERATORS // imnodes_internal.h includes imgui_internal.h, which needs it before imgui.h
#include "addon_common.h"

#include "imgui.h"
#include "imnodes.h"
#include "imnodes_internal.h"

#include <cstdint>
#include <vector>

namespace {

int g_ints[5] = {};
double g_out[2] = {};
std::vector<int> g_selection(1);

// 0: none, 1: Ctrl, 2: Shift, 3: Alt, 4: Super
const bool* ModifierKey(int modifier)
{
    ImGuiIO& io = ImGui::GetIO();
    switch (modifier)
    {
    case 1: return &io.KeyCtrl;
    case 2: return &io.KeyShift;
    case 3: return &io.KeyAlt;
    case 4: return &io.KeySuper;
    default: return nullptr;
    }
}

double* Out(const ImVec2& value)
{
    g_out[0] = value.x;
    g_out[1] = value.y;
    return g_out;
}

} // namespace

RBX_EXPORT void rbx_imnodes_init(void)
{
    if (ImNodes::GetCurrentContext() == nullptr)
        ImNodes::CreateContext();
}

RBX_EXPORT int* rbx_imnodes_ints(void) { return g_ints; }

RBX_EXPORT ImNodesEditorContext* rbx_imnodes_editor_create(void) { return ImNodes::EditorContextCreate(); }
RBX_EXPORT void rbx_imnodes_editor_free(ImNodesEditorContext* editor) { ImNodes::EditorContextFree(editor); }

// NULL selects the default editor
RBX_EXPORT void rbx_imnodes_editor_set(ImNodesEditorContext* editor)
{
    ImNodes::EditorContextSet(editor != nullptr ? editor : ImNodes::GetCurrentContext()->DefaultEditorCtx);
}

RBX_EXPORT double* rbx_imnodes_get_panning(void) { return Out(ImNodes::EditorContextGetPanning()); }
RBX_EXPORT void rbx_imnodes_reset_panning(double x, double y) { ImNodes::EditorContextResetPanning(ImVec2((float)x, (float)y)); }
RBX_EXPORT void rbx_imnodes_move_to_node(int node_id) { ImNodes::EditorContextMoveToNode(node_id); }

// which 0: Dark, 1: Classic, 2: Light
RBX_EXPORT void rbx_imnodes_style_colors(int which)
{
    switch (which)
    {
    case 1: ImNodes::StyleColorsClassic(); break;
    case 2: ImNodes::StyleColorsLight(); break;
    default: ImNodes::StyleColorsDark(); break;
    }
}

RBX_EXPORT void rbx_imnodes_begin_editor(void) { ImNodes::BeginNodeEditor(); }
RBX_EXPORT void rbx_imnodes_end_editor(void) { ImNodes::EndNodeEditor(); }
RBX_EXPORT void rbx_imnodes_minimap(double fraction, int location) { ImNodes::MiniMap((float)fraction, location); }

RBX_EXPORT void rbx_imnodes_push_color(int item, uint32_t color) { ImNodes::PushColorStyle(item, color); }
RBX_EXPORT void rbx_imnodes_pop_color(void) { ImNodes::PopColorStyle(); }

RBX_EXPORT void rbx_imnodes_push_style_var(int item, double x, double y, int is_vec2)
{
    if (is_vec2)
        ImNodes::PushStyleVar(item, ImVec2((float)x, (float)y));
    else
        ImNodes::PushStyleVar(item, (float)x);
}

RBX_EXPORT void rbx_imnodes_pop_style_var(int count) { ImNodes::PopStyleVar(count); }

RBX_EXPORT void rbx_imnodes_begin_node(int id) { ImNodes::BeginNode(id); }
RBX_EXPORT void rbx_imnodes_end_node(void) { ImNodes::EndNode(); }
RBX_EXPORT void rbx_imnodes_begin_title_bar(void) { ImNodes::BeginNodeTitleBar(); }
RBX_EXPORT void rbx_imnodes_end_title_bar(void) { ImNodes::EndNodeTitleBar(); }
RBX_EXPORT double* rbx_imnodes_get_node_dimensions(int id) { return Out(ImNodes::GetNodeDimensions(id)); }

// kind 0: input, 1: output, 2: static
RBX_EXPORT void rbx_imnodes_begin_attribute(int kind, int id, int shape)
{
    switch (kind)
    {
    case 0: ImNodes::BeginInputAttribute(id, shape); break;
    case 1: ImNodes::BeginOutputAttribute(id, shape); break;
    default: ImNodes::BeginStaticAttribute(id); break;
    }
}

RBX_EXPORT void rbx_imnodes_end_attribute(int kind)
{
    switch (kind)
    {
    case 0: ImNodes::EndInputAttribute(); break;
    case 1: ImNodes::EndOutputAttribute(); break;
    default: ImNodes::EndStaticAttribute(); break;
    }
}

RBX_EXPORT void rbx_imnodes_push_attribute_flag(int flag) { ImNodes::PushAttributeFlag(flag); }
RBX_EXPORT void rbx_imnodes_pop_attribute_flag(void) { ImNodes::PopAttributeFlag(); }
RBX_EXPORT void rbx_imnodes_link(int id, int start_attribute, int end_attribute) { ImNodes::Link(id, start_attribute, end_attribute); }
RBX_EXPORT void rbx_imnodes_set_node_draggable(int id, int draggable) { ImNodes::SetNodeDraggable(id, draggable != 0); }
RBX_EXPORT void rbx_imnodes_snap_node_to_grid(int id) { ImNodes::SnapNodeToGrid(id); }

// space 0: screen, 1: editor, 2: grid
RBX_EXPORT void rbx_imnodes_set_node_pos(int space, int id, double x, double y)
{
    const ImVec2 pos((float)x, (float)y);
    switch (space)
    {
    case 0: ImNodes::SetNodeScreenSpacePos(id, pos); break;
    case 1: ImNodes::SetNodeEditorSpacePos(id, pos); break;
    default: ImNodes::SetNodeGridSpacePos(id, pos); break;
    }
}

RBX_EXPORT double* rbx_imnodes_get_node_pos(int space, int id)
{
    switch (space)
    {
    case 0: return Out(ImNodes::GetNodeScreenSpacePos(id));
    case 1: return Out(ImNodes::GetNodeEditorSpacePos(id));
    default: return Out(ImNodes::GetNodeGridSpacePos(id));
    }
}

// Results in the int buffer; see imnodes.luau for the op codes
RBX_EXPORT int rbx_imnodes_query(int op, int arg)
{
    int* out = g_ints;
    bool snap = false;
    switch (op)
    {
    case 0: return ImNodes::IsEditorHovered() ? 1 : 0;
    case 1: return ImNodes::IsNodeHovered(&out[0]) ? 1 : 0;
    case 2: return ImNodes::IsLinkHovered(&out[0]) ? 1 : 0;
    case 3: return ImNodes::IsPinHovered(&out[0]) ? 1 : 0;
    case 4: return ImNodes::NumSelectedNodes();
    case 5: return ImNodes::NumSelectedLinks();
    case 6: return ImNodes::IsNodeSelected(arg) ? 1 : 0;
    case 7: return ImNodes::IsLinkSelected(arg) ? 1 : 0;
    case 8: return ImNodes::IsAttributeActive() ? 1 : 0;
    case 9: return ImNodes::IsAnyAttributeActive(&out[0]) ? 1 : 0;
    case 10: return ImNodes::IsLinkStarted(&out[0]) ? 1 : 0;
    case 11: return ImNodes::IsLinkDropped(&out[0], arg != 0) ? 1 : 0;
    case 12: return ImNodes::IsLinkDestroyed(&out[0]) ? 1 : 0;
    case 13:
    {
        const bool created = ImNodes::IsLinkCreated(&out[0], &out[1], &snap);
        out[2] = snap ? 1 : 0;
        return created ? 1 : 0;
    }
    case 14:
    {
        const bool created = ImNodes::IsLinkCreated(&out[0], &out[1], &out[2], &out[3], &snap);
        out[4] = snap ? 1 : 0;
        return created ? 1 : 0;
    }
    }
    return 0;
}

// op 0: SelectNode, 1: ClearNodeSelection(id), 2: SelectLink, 3: ClearLinkSelection(id), 4: ClearNodeSelection(),
// 5: ClearLinkSelection()
RBX_EXPORT void rbx_imnodes_select(int op, int id)
{
    switch (op)
    {
    case 0: ImNodes::SelectNode(id); break;
    case 1: ImNodes::ClearNodeSelection(id); break;
    case 2: ImNodes::SelectLink(id); break;
    case 3: ImNodes::ClearLinkSelection(id); break;
    case 4: ImNodes::ClearNodeSelection(); break;
    case 5: ImNodes::ClearLinkSelection(); break;
    }
}

// The selected node (or link) ids; their count is NumSelectedNodes (or NumSelectedLinks)
RBX_EXPORT int* rbx_imnodes_selected(int links)
{
    const int count = links ? ImNodes::NumSelectedLinks() : ImNodes::NumSelectedNodes();
    g_selection.resize(count > 0 ? (size_t)count : 1);
    if (count > 0)
    {
        if (links)
            ImNodes::GetSelectedLinks(g_selection.data());
        else
            ImNodes::GetSelectedNodes(g_selection.data());
    }
    return g_selection.data();
}

// The current editor's state as .ini text; its size goes to the int buffer
RBX_EXPORT const char* rbx_imnodes_save_state(void)
{
    size_t size = 0;
    const char* data = ImNodes::SaveCurrentEditorStateToIniString(&size);
    g_ints[0] = (int)size;
    return data;
}

RBX_EXPORT void rbx_imnodes_load_state(const char* data, int size) { ImNodes::LoadCurrentEditorStateFromIniString(data, (size_t)size); }

// op 0: EmulateThreeButtonMouse modifier, 1: LinkDetachWithModifierClick modifier, 2: MultipleSelectModifier modifier,
// 3: AltMouseButton, 4: AutoPanningSpeed
RBX_EXPORT void rbx_imnodes_io(int op, double value)
{
    ImNodesIO& io = ImNodes::GetIO();
    switch (op)
    {
    case 0: io.EmulateThreeButtonMouse.Modifier = ModifierKey((int)value); break;
    case 1: io.LinkDetachWithModifierClick.Modifier = ModifierKey((int)value); break;
    case 2: io.MultipleSelectModifier.Modifier = ModifierKey((int)value); break;
    case 3: io.AltMouseButton = (int)value; break;
    case 4: io.AutoPanningSpeed = (float)value; break;
    }
}

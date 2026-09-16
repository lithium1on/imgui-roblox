// ImGuiNotify addon (https://github.com/TyomaVader/ImGuiNotify, MIT): toast notifications; luau/addons/notify.luau wraps
// it as ImGui.InsertNotification and ImGui.RenderNotifications. Toast buttons queue their id for the Luau side.
#include "addon_common.h"

#include "ImGuiNotify.hpp"

#include <deque>

namespace {

std::deque<int> g_pressed;

} // namespace

// type: ImGuiToastType (0 None, 1 Success, 2 Warning, 3 Error, 4 Info). Empty strings leave a part out.
RBX_EXPORT void rbx_notify_insert(int type, int dismiss_ms, const char* title, const char* content, const char* button_label, int button_id)
{
    ImGuiToast toast((ImGuiToastType)type, dismiss_ms);
    if (title != nullptr && title[0] != '\0')
        toast.setTitle("%s", title);
    if (content != nullptr && content[0] != '\0')
        toast.setContent("%s", content);
    if (button_label != nullptr && button_label[0] != '\0')
    {
        toast.setButtonLabel("%s", button_label);
        toast.setOnButtonPress([button_id] { g_pressed.push_back(button_id); });
    }
    ImGui::InsertNotification(toast);
}

RBX_EXPORT void rbx_notify_render(void) { ImGui::RenderNotifications(); }
RBX_EXPORT int rbx_notify_count(void) { return (int)ImGui::notifications.size(); }
RBX_EXPORT void rbx_notify_clear(void) { ImGui::notifications.clear(); }

RBX_EXPORT void rbx_notify_remove(int index)
{
    if (index >= 0 && (size_t)index < ImGui::notifications.size())
        ImGui::RemoveNotification(index);
}

// The id of a pressed toast button, oldest first, or -1
RBX_EXPORT int rbx_notify_take_pressed(void)
{
    if (g_pressed.empty())
        return -1;
    const int id = g_pressed.front();
    g_pressed.pop_front();
    return id;
}

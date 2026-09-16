// imgui_markdown addon (https://github.com/enkisoftware/imgui_markdown, zlib): Markdown text rendered with Dear ImGui;
// luau/addons/markdown.luau wraps it as ImGui.Markdown. A clicked link is reported to Luau instead of opened.
#include "addon_common.h"

#include "imgui.h"
#include "imgui_markdown.h"

#include <string>

namespace {

ImGui::MarkdownConfig g_config;
std::string g_link;
std::string g_icon;
bool g_clicked = false;

void LinkCallback(ImGui::MarkdownLinkCallbackData data)
{
    if (!data.isImage)
    {
        g_link.assign(data.link, (size_t)data.linkLength);
        g_clicked = true;
    }
}

} // namespace

// level 0-2: H1-H3 (deeper headings use H3). font NULL keeps the current font; size 0 keeps its size.
RBX_EXPORT void rbx_markdown_heading(int level, ImFont* font, double size, int separator)
{
    if (level < 0 || level >= ImGui::MarkdownConfig::NUMHEADINGS)
        return;
    ImGui::MarkdownHeadingFormat& format = g_config.headingFormats[level];
    format.font = font;
    format.separator = separator != 0;
#ifdef IMGUI_HAS_TEXTURES
    format.fontSize = (float)size;
#endif
}

RBX_EXPORT void rbx_markdown_link_icon(const char* icon)
{
    g_icon = icon != nullptr ? icon : "";
    g_config.linkIcon = g_icon.c_str();
}

RBX_EXPORT void rbx_markdown_flags(int flags) { g_config.formatFlags = flags; }

// Returns 1 when a link was clicked; rbx_markdown_link then holds it
RBX_EXPORT int rbx_markdown_render(const char* text, int size)
{
    g_config.linkCallback = LinkCallback;
    g_clicked = false;
    ImGui::Markdown(text, (size_t)size, g_config);
    return g_clicked ? 1 : 0;
}

RBX_EXPORT const char* rbx_markdown_link(void) { return g_link.c_str(); }
RBX_EXPORT int rbx_markdown_link_size(void) { return (int)g_link.size(); }

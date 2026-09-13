// Dear ImGui backend for Roblox executors.
// - Renderer: Potassium's DrawingImmediate. This file flattens ImDrawData into a small command table and the
//   Luau runtime turns the vertex/index buffers into DrawingImmediate shape and text calls.
// - Platform: UserInputService events are forwarded from Luau through the rbx_io_* exports.
// Compiled to WebAssembly with Emscripten together with the unmodified Dear ImGui sources, then translated to Luau.

#include "imgui.h"
#include "imgui_internal.h"
#include "rbx_host.h"

#include <emscripten/emscripten.h>
#include <stddef.h>
#include <string.h>

#define RBX_EXPORT extern "C" EMSCRIPTEN_KEEPALIVE

// The Luau renderer reads these structures straight from linear memory.
IM_STATIC_ASSERT(sizeof(ImDrawIdx) == 2);
IM_STATIC_ASSERT(sizeof(ImDrawVert) == 20);
IM_STATIC_ASSERT(offsetof(ImDrawVert, pos) == 0 && offsetof(ImDrawVert, uv) == 8 && offsetof(ImDrawVert, col) == 16);

// Alpha value of atlas texels that carry a glyph identity (see RbxFont_FontBakedLoadGlyph).
static const unsigned char RBX_GLYPH_TEXEL_MARKER = 0xFE;

extern "C" void imgui_rbx_assert_failed(const char* expr, const char* file, int line)
{
    rbx_host_assert_failed(expr, file, line);
}

//-----------------------------------------------------------------------------
// Font loader
//-----------------------------------------------------------------------------
// DrawingImmediate draws text with the executor's own fonts, so glyph metrics come from the host (measured with
// the Drawing library) and no glyph is rasterized. Every glyph still owns a 1x1 atlas texel encoding its codepoint
// and font slot: R,G = codepoint low 16 bits, B = codepoint bits 16-20 | slot << 5, A = RBX_GLYPH_TEXEL_MARKER.
// The renderer samples that texel under each textured quad to recover the character and emit a text run.

static bool RbxFont_FontSrcInit(ImFontAtlas*, ImFontConfig*) { return true; }
static void RbxFont_FontSrcDestroy(ImFontAtlas*, ImFontConfig*) {}
static bool RbxFont_FontSrcContainsGlyph(ImFontAtlas*, ImFontConfig*, ImWchar codepoint) { return codepoint != 0; }

static bool RbxFont_FontBakedInit(ImFontAtlas*, ImFontConfig* src, ImFontBaked* baked, void*)
{
    if (!src->MergeMode)
    {
        baked->Ascent = ImCeil(baked->Size * 0.8f);
        baked->Descent = ImFloor(baked->Size * -0.2f);
    }
    return true;
}

static bool RbxFont_FontBakedLoadGlyph(ImFontAtlas* atlas, ImFontConfig* src, ImFontBaked* baked, void*, ImWchar codepoint, ImFontGlyph* out_glyph, float* out_advance_x)
{
    const unsigned int slot = src->FontLoaderFlags & 7;
    const double advance_d = rbx_host_glyph_advance((int)slot, (double)baked->Size, (int)codepoint);
    if (advance_d < 0.0)
        return false;
    const float advance = (float)advance_d;

    if (out_advance_x != NULL)
    {
        *out_advance_x = advance;
        return true;
    }

    out_glyph->Codepoint = codepoint;
    out_glyph->AdvanceX = advance;

    ImFontAtlasRectId pack_id = ImFontAtlasPackAddRect(atlas, 1, 1);
    if (pack_id == ImFontAtlasRectId_Invalid)
        return false;
    ImTextureRect* r = ImFontAtlasPackGetRect(atlas, pack_id);

    const unsigned int c = (unsigned int)codepoint;
    const unsigned char texel[4] =
    {
        (unsigned char)(c & 0xFF),
        (unsigned char)((c >> 8) & 0xFF),
        (unsigned char)(((c >> 16) & 0x1F) | (slot << 5)),
        RBX_GLYPH_TEXEL_MARKER,
    };

    // The quad covers the whole advance and line height so the renderer can recover position and font size.
    out_glyph->X0 = 0.0f;
    out_glyph->Y0 = 0.0f;
    out_glyph->X1 = advance;
    out_glyph->Y1 = baked->Size;
    out_glyph->Visible = true;
    out_glyph->PackId = pack_id;
    ImFontAtlasBakedSetFontGlyphBitmap(atlas, baked, src, out_glyph, r, texel, ImTextureFormat_RGBA32, 4);
    return true;
}

static ImFontLoader g_RbxFontLoader;

static void RbxFont_SetupLoader()
{
    g_RbxFontLoader.Name = "roblox_drawing";
    g_RbxFontLoader.FontSrcInit = RbxFont_FontSrcInit;
    g_RbxFontLoader.FontSrcDestroy = RbxFont_FontSrcDestroy;
    g_RbxFontLoader.FontSrcContainsGlyph = RbxFont_FontSrcContainsGlyph;
    g_RbxFontLoader.FontBakedInit = RbxFont_FontBakedInit;
    g_RbxFontLoader.FontBakedLoadGlyph = RbxFont_FontBakedLoadGlyph;
}

// font_slot: DrawingImmediate font index (Drawing.Fonts: UI = 0, System = 1, Plex = 2, Monospace = 3)
RBX_EXPORT ImFont* rbx_add_font(int font_slot, double size_pixels, int merge_mode)
{
    ImFontConfig cfg;
    cfg.FontLoader = &g_RbxFontLoader;
    cfg.FontLoaderFlags = (unsigned int)(font_slot & 7);
    cfg.SizePixels = (float)size_pixels;
    cfg.MergeMode = merge_mode != 0;
    cfg.FontDataOwnedByAtlas = false;
    ImFormatString(cfg.Name, IM_ARRAYSIZE(cfg.Name), "Drawing font %d, %.0fpx", font_slot, size_pixels);
    return ImGui::GetIO().Fonts->AddFont(&cfg);
}

//-----------------------------------------------------------------------------
// Clipboard (Roblox can only write to the OS clipboard, so reads come from the last copied text)
//-----------------------------------------------------------------------------

static ImVector<char> g_ClipboardText;

static const char* Rbx_GetClipboardText(ImGuiContext*)
{
    return g_ClipboardText.Size > 0 ? g_ClipboardText.Data : "";
}

static void Rbx_StoreClipboardText(const char* text)
{
    const int len = (int)strlen(text);
    g_ClipboardText.resize(len + 1);
    memcpy(g_ClipboardText.Data, text, (size_t)len + 1);
}

static void Rbx_SetClipboardText(ImGuiContext*, const char* text)
{
    Rbx_StoreClipboardText(text);
    rbx_host_set_clipboard(text);
}

RBX_EXPORT void rbx_set_clipboard_buffer(const char* text)
{
    Rbx_StoreClipboardText(text);
}

// DrawingImmediate calls carry no render state, so there is nothing to reset.
static void Rbx_ResetRenderState(const ImDrawList*, const ImDrawCmd*) {}

//-----------------------------------------------------------------------------
// Lifecycle
//-----------------------------------------------------------------------------

RBX_EXPORT int rbx_init(int font_slot, double font_size)
{
    if (ImGui::GetCurrentContext() != NULL)
        return 0;

    IMGUI_CHECKVERSION();
    ImGui::CreateContext();

    ImGuiIO& io = ImGui::GetIO();
    io.IniFilename = NULL;
    io.LogFilename = NULL;
    io.BackendPlatformName = "imgui_impl_roblox";
    io.BackendRendererName = "imgui_impl_drawingimmediate";
    io.BackendFlags |= ImGuiBackendFlags_HasMouseCursors;
    io.BackendFlags |= ImGuiBackendFlags_RendererHasVtxOffset;
    io.BackendFlags |= ImGuiBackendFlags_RendererHasTextures;
    io.ConfigErrorRecoveryEnableAssert = false; // Unbalanced Begin/End from Luau shows a tooltip instead of asserting.

    ImGuiPlatformIO& platform_io = ImGui::GetPlatformIO();
    platform_io.Platform_GetClipboardTextFn = Rbx_GetClipboardText;
    platform_io.Platform_SetClipboardTextFn = Rbx_SetClipboardText;
    platform_io.DrawCallback_ResetRenderState = Rbx_ResetRenderState;

    ImFontAtlas* atlas = io.Fonts;
    atlas->TexDesiredFormat = ImTextureFormat_RGBA32;
    atlas->Flags |= ImFontAtlasFlags_NoBakedLines | ImFontAtlasFlags_NoMouseCursors;
    RbxFont_SetupLoader();
    rbx_add_font(font_slot, font_size, 0);

    ImGui::GetStyle().FontSizeBase = (float)font_size;
    return 1;
}

RBX_EXPORT void rbx_shutdown(void)
{
    if (ImGui::GetCurrentContext() != NULL)
        ImGui::DestroyContext();
}

// Forgets every baked glyph, so advances are measured again on next use (the Luau side corrected its text metrics).
RBX_EXPORT void rbx_discard_font_bakes(void)
{
    ImFontAtlasBuildDiscardBakes(ImGui::GetIO().Fonts, 0);
}

//-----------------------------------------------------------------------------
// Input
//-----------------------------------------------------------------------------

RBX_EXPORT void rbx_io_mouse_pos(double x, double y)            { ImGui::GetIO().AddMousePosEvent((float)x, (float)y); }
RBX_EXPORT void rbx_io_mouse_button(int button, int down)       { ImGui::GetIO().AddMouseButtonEvent(button, down != 0); }
RBX_EXPORT void rbx_io_mouse_wheel(double wheel_x, double wheel_y) { ImGui::GetIO().AddMouseWheelEvent((float)wheel_x, (float)wheel_y); }
RBX_EXPORT void rbx_io_key(int key, int down)                   { ImGui::GetIO().AddKeyEvent((ImGuiKey)key, down != 0); }
RBX_EXPORT void rbx_io_char(int codepoint)                      { ImGui::GetIO().AddInputCharacter((unsigned int)codepoint); }
RBX_EXPORT void rbx_io_focus(int focused)                       { ImGui::GetIO().AddFocusEvent(focused != 0); }

RBX_EXPORT int rbx_key_named_begin(void)                        { return ImGuiKey_NamedKey_BEGIN; }
RBX_EXPORT int rbx_key_named_end(void)                          { return ImGuiKey_NamedKey_END; }
RBX_EXPORT const char* rbx_key_name(int key)                    { return ImGui::GetKeyName((ImGuiKey)key); }

RBX_EXPORT int rbx_key_mod(int which)
{
    switch (which)
    {
    case 0: return ImGuiMod_Ctrl;
    case 1: return ImGuiMod_Shift;
    case 2: return ImGuiMod_Alt;
    case 3: return ImGuiMod_Super;
    default: return 0;
    }
}

// bit 0: WantCaptureMouse, bit 1: WantCaptureKeyboard, bit 2: WantTextInput, bits 8-15: ImGui::GetMouseCursor() + 1
RBX_EXPORT int rbx_io_state(void)
{
    ImGuiIO& io = ImGui::GetIO();
    int state = 0;
    if (io.WantCaptureMouse)    state |= 1;
    if (io.WantCaptureKeyboard) state |= 2;
    if (io.WantTextInput)       state |= 4;
    state |= ((ImGui::GetMouseCursor() + 1) & 0xFF) << 8;
    return state;
}

//-----------------------------------------------------------------------------
// Frame
//-----------------------------------------------------------------------------

RBX_EXPORT void rbx_new_frame(double display_w, double display_h, double delta_time)
{
    ImGuiIO& io = ImGui::GetIO();
    io.DisplaySize = ImVec2((float)display_w, (float)display_h);
    io.DeltaTime = (delta_time > 0.0) ? (float)delta_time : (1.0f / 60.0f);

    // DrawingImmediate has no textures or per-vertex colors: anti-aliased fringes would render as opaque smears.
    ImGuiStyle& style = ImGui::GetStyle();
    style.AntiAliasedLines = false;
    style.AntiAliasedLinesUseTex = false;
    style.AntiAliasedFill = false;

    ImGui::NewFrame();
}

static ImVector<ImU32> g_DrawTable;

static inline void DrawTablePushFloat(float f)
{
    ImU32 bits;
    memcpy(&bits, &f, sizeof(bits));
    g_DrawTable.push_back(bits);
}

static void Rbx_UpdateTexture(ImTextureData* tex)
{
    // Texture pixels stay in linear memory where the renderer reads glyph texels, so there is nothing to upload.
    if (tex->Status == ImTextureStatus_WantCreate)
    {
        tex->SetTexID((ImTextureID)(tex->UniqueID + 1));
        tex->SetStatus(ImTextureStatus_OK);
    }
    else if (tex->Status == ImTextureStatus_WantUpdates)
    {
        tex->SetStatus(ImTextureStatus_OK);
    }
    else if (tex->Status == ImTextureStatus_WantDestroy && tex->UnusedFrames > 0)
    {
        tex->SetTexID(ImTextureID_Invalid);
        tex->SetStatus(ImTextureStatus_Destroyed);
    }
}

// Draw table layout (little-endian 32-bit words):
//   [0] command count  [1] white pixel U (f32)  [2] white pixel V (f32)  [3] display pos X (f32)  [4] display pos Y (f32)  [5] reserved
//   then per command (10 words): vtx_ptr, idx_ptr, elem_count, clip_x0, clip_y0, clip_x1, clip_y1 (f32), tex_pixels_ptr, tex_width, tex_height
RBX_EXPORT const ImU32* rbx_render(void)
{
    ImGui::Render();
    ImDrawData* draw_data = ImGui::GetDrawData();

    if (draw_data->Textures != NULL)
        for (ImTextureData* tex : *draw_data->Textures)
            if (tex->Status != ImTextureStatus_OK)
                Rbx_UpdateTexture(tex);

    const ImVec2 white_uv = ImGui::GetIO().Fonts->TexUvWhitePixel;
    const ImVec2 display_pos = draw_data->DisplayPos;

    g_DrawTable.resize(0);
    g_DrawTable.push_back(0);
    DrawTablePushFloat(white_uv.x);
    DrawTablePushFloat(white_uv.y);
    DrawTablePushFloat(display_pos.x);
    DrawTablePushFloat(display_pos.y);
    g_DrawTable.push_back(0);

    ImU32 cmd_count = 0;
    for (ImDrawList* draw_list : draw_data->CmdLists)
    {
        for (const ImDrawCmd& cmd : draw_list->CmdBuffer)
        {
            if (cmd.UserCallback != NULL)
            {
                cmd.UserCallback(draw_list, &cmd);
                continue;
            }
            if (cmd.ElemCount == 0)
                continue;

            const ImTextureData* tex = cmd.TexRef._TexData;
            const bool readable_tex = tex != NULL && tex->Pixels != NULL && tex->Format == ImTextureFormat_RGBA32;

            g_DrawTable.push_back((ImU32)(uintptr_t)(draw_list->VtxBuffer.Data + cmd.VtxOffset));
            g_DrawTable.push_back((ImU32)(uintptr_t)(draw_list->IdxBuffer.Data + cmd.IdxOffset));
            g_DrawTable.push_back(cmd.ElemCount);
            DrawTablePushFloat(cmd.ClipRect.x - display_pos.x);
            DrawTablePushFloat(cmd.ClipRect.y - display_pos.y);
            DrawTablePushFloat(cmd.ClipRect.z - display_pos.x);
            DrawTablePushFloat(cmd.ClipRect.w - display_pos.y);
            g_DrawTable.push_back(readable_tex ? (ImU32)(uintptr_t)tex->Pixels : 0);
            g_DrawTable.push_back(readable_tex ? (ImU32)tex->Width : 0);
            g_DrawTable.push_back(readable_tex ? (ImU32)tex->Height : 0);
            cmd_count++;
        }
    }
    g_DrawTable[0] = cmd_count;
    return g_DrawTable.Data;
}

//-----------------------------------------------------------------------------
// Helpers for the Luau side
//-----------------------------------------------------------------------------

static char g_Scratch[1 << 16];
float g_RbxReturnSlots[16]; // ImVec2/ImVec4 results of the generated bindings (build/gen/imgui_bindings.cpp)

RBX_EXPORT char* rbx_scratch(void)          { return g_Scratch; }
RBX_EXPORT int   rbx_scratch_size(void)     { return (int)sizeof(g_Scratch); }
RBX_EXPORT float* rbx_return_slots(void)    { return g_RbxReturnSlots; }
RBX_EXPORT const char* rbx_version(void)    { return IMGUI_VERSION; }

RBX_EXPORT const char* rbx_save_ini(void)           { return ImGui::SaveIniSettingsToMemory(NULL); }
RBX_EXPORT void        rbx_load_ini(const char* ini) { ImGui::LoadIniSettingsFromMemory(ini); }


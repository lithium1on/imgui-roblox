// Dear ImGui user configuration for the Roblox (WASM -> Luau) build.
// Selected with -DIMGUI_USER_CONFIG="imconfig_roblox.h". Dear ImGui sources stay unmodified.
#pragma once

#define IMGUI_DISABLE_OBSOLETE_FUNCTIONS
#define IMGUI_DISABLE_WIN32_FUNCTIONS
#define IMGUI_DISABLE_DEFAULT_SHELL_FUNCTIONS
#define IMGUI_DISABLE_FILE_FUNCTIONS          // No filesystem in the sandbox; .ini data is exposed through memory instead.
#define IMGUI_DISABLE_TIME_FUNCTIONS          // Avoids WASI clock imports; the host provides DeltaTime every frame.
#define IMGUI_DISABLE_DEFAULT_FONT            // Glyphs come from DrawingImmediate text, not from an embedded bitmap font.
#define IMGUI_DISABLE_STB_TRUETYPE_IMPLEMENTATION // No glyph is rasterized: rbx_stbtt_stubs.cpp replaces stb_truetype.

// Route assertions to the host so they show up as Roblox warnings instead of aborting the VM.
#ifdef __cplusplus
extern "C"
#endif
void imgui_rbx_assert_failed(const char* expr, const char* file, int line);
#define IM_ASSERT(_EXPR) ((_EXPR) ? (void)0 : imgui_rbx_assert_failed(#_EXPR, __FILE__, __LINE__))

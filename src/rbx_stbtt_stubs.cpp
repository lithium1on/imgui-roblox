// Stand-ins for the stb_truetype functions referenced by Dear ImGui's default (TrueType) font loader.
// Every font in this build uses the loader in imgui_rbx.cpp, so the TrueType loader never runs. Without these
// definitions the linker would keep the whole stb_truetype parser and rasterizer; imconfig_roblox.h sets
// IMGUI_DISABLE_STB_TRUETYPE_IMPLEMENTATION so imgui_draw.cpp only sees the declarations.
#include <stddef.h>

#define STBTT_DEF extern
#include "imstb_truetype.h"

int stbtt_GetFontOffsetForIndex(const unsigned char*, int) { return -1; }
int stbtt_InitFont(stbtt_fontinfo*, const unsigned char*, int) { return 0; }
int stbtt_FindGlyphIndex(const stbtt_fontinfo*, int) { return 0; }
float stbtt_ScaleForPixelHeight(const stbtt_fontinfo*, float) { return 0.0f; }

void stbtt_GetFontVMetrics(const stbtt_fontinfo*, int* ascent, int* descent, int* line_gap)
{
    if (ascent) *ascent = 0;
    if (descent) *descent = 0;
    if (line_gap) *line_gap = 0;
}

void stbtt_GetGlyphHMetrics(const stbtt_fontinfo*, int, int* advance_width, int* left_side_bearing)
{
    if (advance_width) *advance_width = 0;
    if (left_side_bearing) *left_side_bearing = 0;
}

void stbtt_GetGlyphBitmapBoxSubpixel(const stbtt_fontinfo*, int, float, float, float, float, int* ix0, int* iy0, int* ix1, int* iy1)
{
    if (ix0) *ix0 = 0;
    if (iy0) *iy0 = 0;
    if (ix1) *ix1 = 0;
    if (iy1) *iy1 = 0;
}

void stbtt_GetGlyphBitmapBox(const stbtt_fontinfo* font, int glyph, float scale_x, float scale_y, int* ix0, int* iy0, int* ix1, int* iy1)
{
    stbtt_GetGlyphBitmapBoxSubpixel(font, glyph, scale_x, scale_y, 0.0f, 0.0f, ix0, iy0, ix1, iy1);
}

void stbtt_MakeGlyphBitmapSubpixelPrefilter(const stbtt_fontinfo*, unsigned char*, int, int, int, float, float, float, float, int, int, float* sub_x, float* sub_y, int)
{
    if (sub_x) *sub_x = 0.0f;
    if (sub_y) *sub_y = 0.0f;
}

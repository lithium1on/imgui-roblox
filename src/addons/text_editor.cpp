// ImGuiColorTextEdit addon (https://github.com/goossens/ImGuiColorTextEdit, MIT): flat exports over TextEditor that
// luau/runtime.luau wraps as ImGui.TextEditor. Lines and indexes are zero-based, as in TextEditor. Strings go in as
// pointer + length and come out as a pointer to a buffer the editor keeps until its next string result.
#include "TextEditor.h"
#include "rbx_host.h"

#include <emscripten/emscripten.h>

#include <cstdint>
#include <ctime>
#include <string>
#include <string_view>

#define RBX_EXPORT extern "C" EMSCRIPTEN_KEEPALIVE

extern "C" {
// TextEditor times change reports with std::chrono::system_clock: seconds from the host instead of a WASI clock import
int clock_gettime(clockid_t, struct timespec* ts)
{
    const double now = rbx_host_clock_now();
    ts->tv_sec = (time_t)now;
    ts->tv_nsec = (long)((now - (double)ts->tv_sec) * 1e9);
    return 0;
}
}

namespace {

using Language = TextEditor::Language;

struct Editor {
    TextEditor editor;
    std::string buffer; // the last string result
    int32_t out[4] = {}; // the last position or selection result
    bool changed = false;
};

const Language* Luau()
{
    static const Language language = [] {
        Language luau = *Language::Lua();
        luau.name = "Luau";
        for (const char* word : { "continue", "export" })
            luau.keywords.insert(word);
        for (const char* word : { "typeof", "game", "workspace", "script", "shared", "task", "buffer", "bit32", "utf8", "vector",
                                  "Enum", "Instance", "Vector2", "Vector3", "CFrame", "Color3", "UDim", "UDim2", "Rect", "Ray",
                                  "BrickColor", "NumberRange", "NumberSequence", "ColorSequence", "TweenInfo", "tick", "wait",
                                  "spawn", "delay", "warn", "getgenv", "Drawing", "DrawingImmediate" })
            luau.identifiers.insert(word);
        luau.otherStringStart = "`"; // interpolated strings
        luau.otherStringEnd = "`";
        return luau;
    }();
    return &language;
}

// Same order as EditorLanguages in runtime.luau
const Language* LanguageById(int id)
{
    switch (id)
    {
    case 1: return Language::C();
    case 2: return Language::Cpp();
    case 3: return Language::Cs();
    case 4: return Language::AngelScript();
    case 5: return Language::Lua();
    case 6: return Luau();
    case 7: return Language::Python();
    case 8: return Language::Glsl();
    case 9: return Language::Hlsl();
    case 10: return Language::Json();
    case 11: return Language::Markdown();
    case 12: return Language::Sql();
    default: return nullptr;
    }
}

const char* Result(Editor* e, std::string text)
{
    e->buffer = std::move(text);
    return e->buffer.c_str();
}

int32_t* Result(Editor* e, const TextEditor::DocPos& start, const TextEditor::DocPos& end)
{
    e->out[0] = (int32_t)start.line;
    e->out[1] = (int32_t)start.index;
    e->out[2] = (int32_t)end.line;
    e->out[3] = (int32_t)end.index;
    return e->out;
}

TextEditor::DocPos Pos(int line, int index)
{
    return TextEditor::DocPos((size_t)(line < 0 ? 0 : line), (size_t)(index < 0 ? 0 : index));
}

std::string_view View(const char* text, int size)
{
    return std::string_view(text, (size_t)size);
}

} // namespace

RBX_EXPORT Editor* rbx_te_new(void)
{
    Editor* e = new Editor();
    e->editor.SetChangeCallback([e] { e->changed = true; });
    return e;
}

RBX_EXPORT void rbx_te_free(Editor* e)
{
    delete e;
}

RBX_EXPORT int rbx_te_render(Editor* e, const char* title, double width, double height, int child_flags, int window_flags)
{
    if (window_flags < 0)
        window_flags = ImGuiWindowFlags_NoMove | ImGuiWindowFlags_HorizontalScrollbar;
    return e->editor.Render(title, ImVec2((float)width, (float)height), child_flags, window_flags) ? 1 : 0;
}

RBX_EXPORT int rbx_te_take_changed(Editor* e)
{
    const bool changed = e->changed;
    e->changed = false;
    return changed ? 1 : 0;
}

RBX_EXPORT int rbx_te_buffer_size(Editor* e) { return (int)e->buffer.size(); }
RBX_EXPORT void rbx_te_set_text(Editor* e, const char* text, int size) { e->editor.SetText(View(text, size)); }
RBX_EXPORT const char* rbx_te_get_text(Editor* e)
{
    // TextEditor ends a non-empty last line with a newline; leave it out so GetText returns what SetText was given
    std::string text = e->editor.GetText();
    const size_t lines = e->editor.GetLineCount();
    if (!text.empty() && text.back() == '\n' && lines > 0 && !e->editor.GetLineText(lines - 1).empty())
        text.pop_back();
    return Result(e, std::move(text));
}
RBX_EXPORT const char* rbx_te_get_line_text(Editor* e, int line) { return Result(e, e->editor.GetLineText((size_t)line)); }
RBX_EXPORT const char* rbx_te_get_cursor_text(Editor* e, int cursor) { return Result(e, e->editor.GetCursorText((size_t)cursor)); }
RBX_EXPORT const char* rbx_te_get_language_name(Editor* e) { return Result(e, e->editor.GetLanguageName()); }

RBX_EXPORT const char* rbx_te_get_section_text(Editor* e, int l1, int i1, int l2, int i2)
{
    return Result(e, e->editor.GetSectionText(Pos(l1, i1), Pos(l2, i2)));
}

RBX_EXPORT void rbx_te_replace_section_text(Editor* e, int l1, int i1, int l2, int i2, const char* text, int size)
{
    e->editor.ReplaceSectionText(Pos(l1, i1), Pos(l2, i2), View(text, size));
}

RBX_EXPORT void rbx_te_set_language(Editor* e, int id) { e->editor.SetLanguage(LanguageById(id)); }

RBX_EXPORT void rbx_te_set_palette(Editor* e, int light)
{
    e->editor.SetPalette(light ? TextEditor::GetLightPalette() : TextEditor::GetDarkPalette());
}

RBX_EXPORT void rbx_te_set_palette_color(Editor* e, int index, uint32_t color)
{
    if (index < 0 || index >= (int)TextEditor::Color::count)
        return;
    TextEditor::Palette palette = e->editor.GetPalette();
    palette[(size_t)index] = color;
    e->editor.SetPalette(palette);
}

RBX_EXPORT uint32_t rbx_te_get_palette_color(Editor* e, int index)
{
    if (index < 0 || index >= (int)TextEditor::Color::count)
        return 0;
    return e->editor.GetPalette()[(size_t)index];
}

// Same order as EditorOptions in runtime.luau
RBX_EXPORT void rbx_te_set_option(Editor* e, int option, double value)
{
    TextEditor& t = e->editor;
    const bool on = value != 0.0;
    const size_t count = value > 0.0 ? (size_t)value : 0;
    switch (option)
    {
    case 0: t.SetTabSize(count); break;
    case 1: t.SetInsertSpacesOnTabs(on); break;
    case 2: t.SetLineSpacing((float)value); break;
    case 3: t.SetWordWrapEnabled(on); break;
    case 4: t.SetReadOnlyEnabled(on); break;
    case 5: t.SetCaretsVisible(on); break;
    case 6: t.SetAutoIndentEnabled(on); break;
    case 7: t.SetShowWhitespacesEnabled(on); break;
    case 8: t.SetShowSpacesEnabled(on); break;
    case 9: t.SetShowTabsEnabled(on); break;
    case 10: t.SetShowLineNumbersEnabled(on); break;
    case 11: t.SetShowMiniMapEnabled(on); break;
    case 12: t.SetMiniMapColumns(count); break;
    case 13: t.SetShowScrollbarMiniMapEnabled(on); break;
    case 14: t.SetShowPanScrollIndicatorEnabled(on); break;
    case 15: t.SetShowMatchingBrackets(on); break;
    case 16: t.SetCompletePairedGlyphs(on); break;
    case 17: t.SetLineFoldingEnabled(on); break;
    case 18: t.SetOverwriteEnabled(on); break;
    case 19: if (on) t.SetMiddleMousePanMode(); else t.SetMiddleMouseScrollMode(); break;
    case 20: t.SetLineNumberLeftMargin(count); break;
    case 21: t.SetDecorationLeftMargin(count); break;
    case 22: t.SetTextLeftMargin(count); break;
    }
}

RBX_EXPORT double rbx_te_get_option(Editor* e, int option)
{
    const TextEditor& t = e->editor;
    switch (option)
    {
    case 0: return (double)t.GetTabSize();
    case 1: return t.IsInsertSpacesOnTabs();
    case 2: return t.GetLineSpacing();
    case 3: return t.IsWordWrapEnabled();
    case 4: return t.IsReadOnlyEnabled();
    case 5: return t.IsCaretsVisible();
    case 6: return t.IsAutoIndentEnabled();
    case 7: return t.IsShowWhitespacesEnabled();
    case 8: return t.IsShowSpacesEnabled();
    case 9: return t.IsShowTabsEnabled();
    case 10: return t.IsShowLineNumbersEnabled();
    case 11: return t.IsShowMiniMapEnabled();
    case 12: return (double)t.GetMiniMapColumns();
    case 13: return t.IsShowScrollbarMiniMapEnabled();
    case 14: return t.IsShowPanScrollIndicatorEnabled();
    case 15: return t.IsShowingMatchingBrackets();
    case 16: return t.IsCompletingPairedGlyphs();
    case 17: return t.IsLineFoldingEnabled();
    case 18: return t.IsOverwriteEnabled();
    case 19: return t.IsMiddleMousePanMode();
    case 20: return (double)t.GetLineNumberLeftMargin();
    case 21: return (double)t.GetDecorationLeftMargin();
    case 22: return (double)t.GetTextLeftMargin();
    }
    return 0.0;
}

// Same order as EditorCommands in runtime.luau
RBX_EXPORT void rbx_te_command(Editor* e, int command)
{
    TextEditor& t = e->editor;
    switch (command)
    {
    case 0: t.Cut(); break;
    case 1: t.Copy(); break;
    case 2: t.Paste(); break;
    case 3: t.Undo(); break;
    case 4: t.Redo(); break;
    case 5: t.SelectAll(); break;
    case 6: t.ClearCursors(); break;
    case 7: t.SetFocus(); break;
    case 8: t.ClearText(); break;
    case 9: t.OpenFindReplaceWindow(); break;
    case 10: t.CloseFindReplaceWindow(); break;
    case 11: t.FindNext(); break;
    case 12: t.FindAll(); break;
    case 13: t.ClearMarkers(); break;
    case 14: t.ClearSquiggles(); break;
    case 15: t.GrowSelections(); break;
    case 16: t.ShrinkSelections(); break;
    case 17: t.IndentLines(); break;
    case 18: t.DeindentLines(); break;
    case 19: t.MoveUpLines(); break;
    case 20: t.MoveDownLines(); break;
    case 21: t.ToggleComments(); break;
    case 22: t.SelectionToLowerCase(); break;
    case 23: t.SelectionToUpperCase(); break;
    case 24: t.StripTrailingWhitespaces(); break;
    case 25: t.TabsToSpaces(); break;
    case 26: t.SpacesToTabs(); break;
    case 27: t.UnfoldAll(); break;
    }
}

// Same order as EditorQueries in runtime.luau
RBX_EXPORT double rbx_te_query(Editor* e, int query)
{
    const TextEditor& t = e->editor;
    switch (query)
    {
    case 0: return t.CanUndo();
    case 1: return t.CanRedo();
    case 2: return (double)t.GetUndoIndex();
    case 3: return t.IsEmpty();
    case 4: return (double)t.GetLineCount();
    case 5: return (double)t.GetNumberOfCursors();
    case 6: return t.AnyCursorHasSelection();
    case 7: return t.AllCursorsHaveSelection();
    case 8: return t.MainCursorHasSelection();
    case 9: return t.CurrentCursorHasSelection();
    case 10: return t.HasMarkers();
    case 11: return t.HasSquiggles();
    case 12: return t.HasFindString();
    case 13: return (double)t.GetFirstVisibleRow();
    case 14: return (double)t.GetLastVisibleRow();
    case 15: return (double)t.GetFirstVisibleColumn();
    case 16: return (double)t.GetLastVisibleColumn();
    case 17: return t.GetLineHeight();
    case 18: return t.GetGlyphWidth();
    case 19: return t.HasLanguage();
    }
    return 0.0;
}

// Same order as EditorLineOps in runtime.luau; `value` is the second line, the scroll alignment or a flag
RBX_EXPORT int rbx_te_line(Editor* e, int op, int line, int value)
{
    TextEditor& t = e->editor;
    const size_t l = (size_t)(line < 0 ? 0 : line);
    switch (op)
    {
    case 0: t.SelectLine(l); break;
    case 1: t.SelectLines(l, (size_t)(value < 0 ? 0 : value)); break;
    case 2: t.ScrollToLine(l, value == 0 ? TextEditor::Scroll::alignTop : value == 2 ? TextEditor::Scroll::alignBottom : TextEditor::Scroll::alignMiddle); break;
    case 3: t.FoldAroundLine(l); break;
    case 4: t.UnfoldAroundLine(l); break;
    case 5: t.ToggleAtLine(l); break;
    case 6: return t.IsLineFoldable(l) ? 1 : 0;
    case 7: return t.IsLineFolded(l) ? 1 : 0;
    case 8: return t.IsLineVisible(l) ? 1 : 0;
    case 9: return t.IsLineHidden(l) ? 1 : 0;
    case 10: t.SelectToBrackets(value != 0); break;
    case 11: t.AddNextOccurrence(value != 0); break;
    case 12: t.SelectAllOccurrences(value != 0); break;
    }
    return 0;
}

// op 0: SetCursor, 1: SelectRegion, 2: ClearSquiggles in a region
RBX_EXPORT void rbx_te_region(Editor* e, int op, int l1, int i1, int l2, int i2)
{
    switch (op)
    {
    case 0: e->editor.SetCursor(Pos(l1, i1)); break;
    case 1: e->editor.SelectRegion(Pos(l1, i1), Pos(l2, i2)); break;
    case 2: e->editor.ClearSquiggles(Pos(l1, i1), Pos(l2, i2)); break;
    }
}

// which 0-2: position of a cursor, the main cursor, the current cursor; 3-5: their selections
RBX_EXPORT int32_t* rbx_te_cursor(Editor* e, int which, int cursor)
{
    const TextEditor& t = e->editor;
    if (which == 0 || which == 3)
    {
        if (cursor < 0 || (size_t)cursor >= t.GetNumberOfCursors())
            cursor = 0;
    }
    switch (which)
    {
    case 0: { auto p = t.GetCursorPosition((size_t)cursor); return Result(e, p, p); }
    case 1: { auto p = t.GetMainCursorPosition(); return Result(e, p, p); }
    case 2: { auto p = t.GetCurrentCursorPosition(); return Result(e, p, p); }
    case 3: { auto s = t.GetCursorSelection((size_t)cursor); return Result(e, s.start, s.end); }
    case 4: { auto s = t.GetMainCursorSelection(); return Result(e, s.start, s.end); }
    default: { auto s = t.GetCurrentCursorSelection(); return Result(e, s.start, s.end); }
    }
}

// op 0: IsMousePosOverGlyph, 1: IsMousePosOverTextArea, 2: GetDocPosAtMousePos (result in the position buffer)
RBX_EXPORT int rbx_te_mouse(Editor* e, int op, double x, double y)
{
    const ImVec2 pos((float)x, (float)y);
    switch (op)
    {
    case 0: return e->editor.IsMousePosOverGlyph(pos) ? 1 : 0;
    case 1: return e->editor.IsMousePosOverTextArea(pos) ? 1 : 0;
    default: { auto p = e->editor.GetDocPosAtMousePos(pos); return (int)(intptr_t)Result(e, p, p); }
    }
}

RBX_EXPORT const char* rbx_te_get_word_at_mouse_pos(Editor* e, double x, double y)
{
    return Result(e, e->editor.GetWordAtMousePos(ImVec2((float)x, (float)y)));
}

// op 0-2: SelectFirstOccurrenceOf, SelectNextOccurrenceOf, SelectAllOccurrencesOf
RBX_EXPORT void rbx_te_find(Editor* e, int op, const char* text, int size, int case_sensitive, int whole_word)
{
    switch (op)
    {
    case 0: e->editor.SelectFirstOccurrenceOf(View(text, size), case_sensitive != 0, whole_word != 0); break;
    case 1: e->editor.SelectNextOccurrenceOf(View(text, size), case_sensitive != 0, whole_word != 0); break;
    case 2: e->editor.SelectAllOccurrencesOf(View(text, size), case_sensitive != 0, whole_word != 0); break;
    }
}

// op 0-1: ReplaceTextInCurrentCursor, ReplaceTextInAllCursors; 2-5: find window labels (Find, Find All, Replace, Replace All)
RBX_EXPORT void rbx_te_string(Editor* e, int op, const char* text, int size)
{
    TextEditor& t = e->editor;
    switch (op)
    {
    case 0: t.ReplaceTextInCurrentCursor(View(text, size)); break;
    case 1: t.ReplaceTextInAllCursors(View(text, size)); break;
    case 2: t.SetFindButtonLabel(View(text, size)); break;
    case 3: t.SetFindAllButtonLabel(View(text, size)); break;
    case 4: t.SetReplaceButtonLabel(View(text, size)); break;
    case 5: t.SetReplaceAllButtonLabel(View(text, size)); break;
    }
}

RBX_EXPORT void rbx_te_add_marker(Editor* e, int line, uint32_t line_number_color, uint32_t text_color,
                                  const char* line_number_tooltip, int line_number_tooltip_size, const char* text_tooltip, int text_tooltip_size)
{
    e->editor.AddMarker((size_t)(line < 0 ? 0 : line), line_number_color, text_color,
                        View(line_number_tooltip, line_number_tooltip_size), View(text_tooltip, text_tooltip_size));
}

RBX_EXPORT void rbx_te_add_squiggle(Editor* e, int l1, int i1, int l2, int i2, int type, uint32_t color, const char* tooltip, int tooltip_size)
{
    e->editor.AddSquiggle(Pos(l1, i1), Pos(l2, i2), (size_t)(type < 0 ? 0 : type), color, View(tooltip, tooltip_size));
}

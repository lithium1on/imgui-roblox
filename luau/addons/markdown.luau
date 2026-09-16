-- imgui_markdown addon (github.com/enkisoftware/imgui_markdown, zlib) as ImGui.Markdown.
--
--     local MarkdownAddon = loadstring(game:HttpGet(".../markdown.luau"))()
--     ImGui.Init({ Addons = MarkdownAddon })
--     local link = ImGui.Markdown("# Help\n* one\n* two\n[Docs](https://example.com)")
--     if link then setclipboard(link) end
--
-- ImGui.Markdown(text, config?) draws headings, bullet lists, links, emphasis and horizontal rules in the current window
-- and returns the link that was clicked this frame. config: H1, H2, H3 = { Font, Size, Separator } (defaults: the current
-- font at 1.6x, 1.3x and 1.1x its size, with a separator under H1 and H2), LinkIcon (text before a link's tooltip) and
-- Flags (ImGui.MarkdownFormatFlags, e.g. GithubStyle).

local Modules, Enums, Common = ...

local MarkdownAddon = { Name = "Markdown", Protocol = 1, ImGuiVersion = "1.92.9b", Modules = Modules }

local HEADING_SCALES = { 1.6, 1.3, 1.1 }
local HEADING_SEPARATORS = { true, true, false }

function MarkdownAddon.Install(host)
	local C = Common(host)
	local Call, Release, String = C.Call, C.Release, C.String
	local E = C.Exports("rbx_markdown_", { "heading", "link_icon", "flags", "render", "link", "link_size" })
	local Raw = host.Raw
	local FormatFlags = table.clone(Enums.FormatFlags or {})

	local function Ptr(font)
		if type(font) == "table" then
			return font.__ptr
		end
		return font or 0
	end

	local function Markdown(text, config)
		config = config or {}
		local baseSize = Raw.GetFontSize()
		local currentFont = nil
		for level = 1, 3 do
			local heading = config["H" .. level] or {}
			local font = heading.Font
			if font == nil then
				currentFont = currentFont or Raw.GetFont()
				font = currentFont
			end
			local separator = heading.Separator
			if separator == nil then
				separator = HEADING_SEPARATORS[level]
			end
			Call(E.heading, level - 1, Ptr(font), heading.Size or baseSize * HEADING_SCALES[level], if separator then 1 else 0)
		end
		Call(E.link_icon, (String(config.LinkIcon or "")))
		Call(E.flags, config.Flags or 0)
		local textPtr, size = String(text)
		local clicked = Call(E.render, textPtr, size) ~= 0
		Release()
		if clicked then
			return buffer.readstring(host.Mem(), (Call(E.link)), (Call(E.link_size)))
		end
		return nil
	end

	return {
		Bind = function()
			return { Markdown = Markdown, MarkdownFormatFlags = FormatFlags }
		end,
	}
end

return MarkdownAddon

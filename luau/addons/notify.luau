-- ImGuiNotify addon (github.com/TyomaVader/ImGuiNotify, MIT): toast notifications in the bottom-right corner.
--
--     local NotifyAddon = loadstring(game:HttpGet(".../notify.luau"))()
--     ImGui.Init({ Addons = NotifyAddon })
--     ImGui.InsertNotification({ Type = "Success", Title = "Saved", Content = "Settings written to disk" })
--     ImGui.OnFrame(function()
--         -- windows...
--         ImGui.RenderNotifications() -- once per frame, after your windows
--     end)
--
-- ImGui.InsertNotification(toast) or ImGui.InsertNotification(type, content). toast: Type ("None", "Success",
-- "Warning", "Error", "Info" or an ImGui.ToastType value), Title, Content, DismissTime (milliseconds, default 3000),
-- ButtonLabel and OnButtonPress (a function run when the button is clicked).

local Modules, _, Common = ...

local NotifyAddon = { Name = "Notify", Protocol = 1, ImGuiVersion = "1.92.9b", Modules = Modules }

local TOAST_TYPES = { None = 0, Success = 1, Warning = 2, Error = 3, Info = 4 }

function NotifyAddon.Install(host)
	local E = Common(host).Exports("rbx_notify_", { "insert", "render", "count", "clear", "remove", "take_pressed" })

	local function Call(closure, ...)
		return closure[1](closure, ...)
	end

	local buttons = {} -- button id -> { callback, script }
	local nextButton = 0

	local function Text(value)
		local text = if value == nil then "" else tostring(value)
		local ptr = host.Malloc(#text + 1)
		local mem = host.Mem()
		buffer.writestring(mem, ptr, text)
		buffer.writeu8(mem, ptr + #text, 0)
		return ptr
	end

	local function Insert(script, toast, content)
		if type(toast) ~= "table" then
			toast = { Type = toast, Content = content }
		end
		local toastType = toast.Type or "None"
		if type(toastType) == "string" then
			toastType = TOAST_TYPES[toastType] or error(string.format('[ImGui] unknown toast type "%s"', toastType), 3)
		end
		local button = -1
		if toast.ButtonLabel ~= nil then
			nextButton += 1
			button = nextButton
			buttons[button] = { toast.OnButtonPress, script }
		end
		local title, body, label = Text(toast.Title), Text(toast.Content), Text(toast.ButtonLabel)
		Call(E.insert, toastType, toast.DismissTime or 3000, title, body, label, button)
		host.Free(title)
		host.Free(body)
		host.Free(label)
	end

	local function Render()
		Call(E.render)
		while true do
			local id = Call(E.take_pressed)
			if id < 0 then
				break
			end
			local entry = buttons[id]
			if entry ~= nil and entry[1] ~= nil then
				local ok, err = pcall(entry[1])
				if not ok then
					(warn or print)("[ImGui] notification button error: " .. tostring(err))
				end
			end
		end
		if Call(E.count) == 0 and next(buttons) ~= nil then
			table.clear(buttons)
		end
	end

	return {
		Bind = function(script)
			return {
				InsertNotification = function(toast, content)
					Insert(script, toast, content)
				end,
				RenderNotifications = Render,
				-- index: 0 for the oldest toast
				RemoveNotification = function(index)
					Call(E.remove, index)
				end,
				ClearNotifications = function()
					Call(E.clear)
				end,
				GetNotificationCount = function()
					return Call(E.count)
				end,
				ToastType = table.clone(TOAST_TYPES),
			}
		end,
		Leave = function(script)
			for id, entry in buttons do
				if entry[2] == script then
					buttons[id] = nil
				end
			end
		end,
	}
end

return NotifyAddon

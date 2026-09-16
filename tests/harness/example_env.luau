-- Stand-ins for the Roblox and executor globals the scripts in examples/ use, so they can run under the Luau CLI.
-- build.py joins mock_env.luau, this file, the bundle, example_prelude.luau, the example and example_driver.luau.

local function Signal()
	local handlers = {}
	local signal = {}
	function signal:Connect(fn)
		table.insert(handlers, fn)
		local connection = { Connected = true }
		function connection:Disconnect()
			self.Connected = false
			local index = table.find(handlers, fn)
			if index then
				table.remove(handlers, index)
			end
		end
		return connection
	end
	function signal:Fire(...)
		for _, fn in table.clone(handlers) do
			fn(...)
		end
	end
	return signal
end

local function EnumType(typeName)
	return setmetatable({}, {
		__index = function(self, key)
			local item = setmetatable({ Name = key, EnumType = typeName }, {
				__tostring = function()
					return "Enum." .. typeName .. "." .. key
				end,
			})
			rawset(self, key, item)
			return item
		end,
	})
end
Enum = setmetatable({}, {
	__index = function(self, key)
		local enumType = EnumType(key)
		rawset(self, key, enumType)
		return enumType
	end,
})

Vector2.zero = Vector2.new(0, 0)
Vector2.one = Vector2.new(1, 1)

local red, blue = { Name = "Red" }, { Name = "Blue" }
local playerList = {
	{ Name = "LocalPlayer", DisplayName = "You", UserId = 1, Team = red },
	{ Name = "Builderman", DisplayName = "builderman", UserId = 156, Team = blue },
	{ Name = "Guest1337", DisplayName = "Guest", UserId = 1337 },
}
local Players = { LocalPlayer = playerList[1], PlayerAdded = Signal(), PlayerRemoving = Signal() }
function Players:GetPlayers()
	return table.clone(playerList)
end

local UserInputService = { InputBegan = Signal(), InputEnded = Signal(), InputChanged = Signal() }
function UserInputService:GetMouseLocation()
	return Vector2.new(640, 400)
end
function UserInputService:IsKeyDown()
	return false
end

local HttpService = {}
function HttpService:JSONEncode(value)
	local kind = type(value)
	if kind == "table" then
		local parts = {}
		if #value > 0 then
			for index, item in value do
				parts[index] = self:JSONEncode(item)
			end
			return "[" .. table.concat(parts, ",") .. "]"
		end
		for key, item in value do
			table.insert(parts, string.format("%q:%s", tostring(key), self:JSONEncode(item)))
		end
		return "{" .. table.concat(parts, ",") .. "}"
	elseif kind == "string" then
		return string.format("%q", value)
	elseif kind == "number" or kind == "boolean" then
		return tostring(value)
	end
	return "null"
end
function HttpService:JSONDecode()
	error("JSONDecode is not available in the example test environment")
end

Vector3 = {
	new = function(x, y, z)
		return { X = x or 0, Y = y or 0, Z = z or 0 }
	end,
}

-- Rigid CFrames: a position and a rotation matrix given by rows
local CFrameMeta = {}
CFrameMeta.__index = CFrameMeta
function CFrameMeta:GetComponents()
	return table.unpack(self.Components, 1, 12)
end
function CFrameMeta:Inverse()
	local x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22 = self:GetComponents()
	return CFrame.new(-(r00 * x + r10 * y + r20 * z), -(r01 * x + r11 * y + r21 * z), -(r02 * x + r12 * y + r22 * z),
		r00, r10, r20, r01, r11, r21, r02, r12, r22)
end
CFrame = {
	new = function(x, y, z, ...)
		local rotation = { ... }
		if #rotation == 0 then
			rotation = { 1, 0, 0, 0, 1, 0, 0, 0, 1 }
		end
		return setmetatable({ Components = { x or 0, y or 0, z or 0, table.unpack(rotation, 1, 9) } }, CFrameMeta)
	end,
}

workspace = { CurrentCamera = { ViewportSize = Vector2.new(1280, 800), CFrame = CFrame.new(0, 12, 30), FieldOfView = 70 } }

Instance = {
	new = function(className)
		local instance = { ClassName = className, Name = className, Size = Vector3.new(4, 1, 2), CFrame = CFrame.new(0, 0, 0) }
		function instance:Destroy()
			self.Parent = nil
		end
		return instance
	end,
}

local services = {
	Players = Players,
	UserInputService = UserInputService,
	HttpService = HttpService,
	RunService = { RenderStepped = Signal(), Heartbeat = Signal() },
	Workspace = workspace,
	TextService = {
		GetTextSize = function(_, text, size)
			return Vector2.new(#text * HarnessAdvance(size), size)
		end,
	},
}
game = {
	GetService = function(_, name)
		return assert(services[name], "service " .. tostring(name) .. " is not in the example test environment")
	end,
}

Drawing = { Fonts = { UI = 0, System = 1, Plex = 2, Monospace = 3 } }

ExampleFiles = {}
function isfile(path)
	return ExampleFiles[path] ~= nil
end
function readfile(path)
	return assert(ExampleFiles[path], "no such file: " .. tostring(path))
end
function writefile(path, content)
	ExampleFiles[path] = content
end

local genv = {}
function getgenv()
	return genv
end
function setclipboard(text)
	ExampleClipboard = text
end

ExampleDeferred = {}
task = {
	spawn = function() end,
	delay = function() end,
	wait = function()
		return 0
	end,
	defer = function(fn, ...)
		table.insert(ExampleDeferred, table.pack(fn, ...))
	end,
}

-- ImGuizmo addon (github.com/CedricGuillemet/ImGuizmo, MIT) as ImGui.ImGuizmo: 3D move, rotate and scale handles.
--
--     local GizmoAddon = loadstring(game:HttpGet(".../imguizmo.luau"))()
--     ImGui.Init({ Addons = GizmoAddon })
--     local ImGuizmo = ImGui.ImGuizmo
--     ImGui.OnFrame(function()
--         local changed, cframe = ImGuizmo.ManipulateCFrame(part.CFrame, ImGuizmo.OPERATION.TRANSLATE, ImGuizmo.MODE.WORLD)
--         if changed then part.CFrame = cframe end
--     end)
--
-- Functions keep ImGuizmo's C++ names. Matrices are tables of 16 numbers, column-major like OpenGL (and like
-- ImGuizmo's C++ API); the Roblox helpers convert CFrames and cameras.

local Modules, _, Common = ...

local sqrt, tan, rad, floor = math.sqrt, math.tan, math.rad, math.floor
local readf32, writef32 = buffer.readf32, buffer.writef32

local ImGuizmoAddon = { Name = "ImGuizmo", Protocol = 1, ImGuiVersion = "1.92.9b", Modules = Modules }

local OPERATION = {
	TRANSLATE_X = 1, TRANSLATE_Y = 2, TRANSLATE_Z = 4, ROTATE_X = 8, ROTATE_Y = 16, ROTATE_Z = 32, ROTATE_SCREEN = 64,
	SCALE_X = 128, SCALE_Y = 256, SCALE_Z = 512, BOUNDS = 1024, SCALE_XU = 2048, SCALE_YU = 4096, SCALE_ZU = 8192,
}
OPERATION.TRANSLATE = OPERATION.TRANSLATE_X + OPERATION.TRANSLATE_Y + OPERATION.TRANSLATE_Z
OPERATION.ROTATE = OPERATION.ROTATE_X + OPERATION.ROTATE_Y + OPERATION.ROTATE_Z + OPERATION.ROTATE_SCREEN
OPERATION.SCALE = OPERATION.SCALE_X + OPERATION.SCALE_Y + OPERATION.SCALE_Z
OPERATION.SCALEU = OPERATION.SCALE_XU + OPERATION.SCALE_YU + OPERATION.SCALE_ZU
OPERATION.UNIVERSAL = OPERATION.TRANSLATE + OPERATION.ROTATE + OPERATION.SCALEU

local MODE = { LOCAL = 0, WORLD = 1 }

local COLOR = {
	DIRECTION_X = 0, DIRECTION_Y = 1, DIRECTION_Z = 2, PLANE_X = 3, PLANE_Y = 4, PLANE_Z = 5, SELECTION = 6, INACTIVE = 7,
	TRANSLATION_LINE = 8, SCALE_LINE = 9, ROTATION_USING_BORDER = 10, ROTATION_USING_FILL = 11, HATCHED_AXIS_LINES = 12,
	TEXT = 13, TEXT_SHADOW = 14, COUNT = 15,
}

local STYLE_FIELDS = {
	TranslationLineThickness = 0, TranslationLineArrowSize = 1, RotationLineThickness = 2, RotationOuterLineThickness = 3,
	ScaleLineThickness = 4, ScaleLineCircleSize = 5, HatchedAxisLineThickness = 6, CenterCircleSize = 7,
}

-- Float slots in rbx_imguizmo_buffers
local VIEW, PROJECTION, MATRIX, DELTA, SNAP, BOUNDS, BOUNDS_SNAP, TRANSLATION, ROTATION, SCALE = 0, 16, 32, 48, 64, 67, 73, 76, 79, 82

-- A 4x4 column-major matrix for a CFrame, scaled by size (a Vector3, default 1)
local function CFrameToMatrix(cframe, size)
	local x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22 = cframe:GetComponents()
	local sx, sy, sz = 1, 1, 1
	if size ~= nil then
		sx, sy, sz = size.X, size.Y, size.Z
	end
	return { r00 * sx, r10 * sx, r20 * sx, 0, r01 * sy, r11 * sy, r21 * sy, 0, r02 * sz, r12 * sz, r22 * sz, 0, x, y, z, 1 }
end

-- A CFrame and the scale (a Vector3) of a column-major matrix
local function MatrixToCFrame(m)
	local sx = sqrt(m[1] * m[1] + m[2] * m[2] + m[3] * m[3])
	local sy = sqrt(m[5] * m[5] + m[6] * m[6] + m[7] * m[7])
	local sz = sqrt(m[9] * m[9] + m[10] * m[10] + m[11] * m[11])
	local ix, iy, iz = if sx > 0 then 1 / sx else 0, if sy > 0 then 1 / sy else 0, if sz > 0 then 1 / sz else 0
	local cframe = CFrame.new(
		m[13], m[14], m[15],
		m[1] * ix, m[5] * iy, m[9] * iz,
		m[2] * ix, m[6] * iy, m[10] * iz,
		m[3] * ix, m[7] * iy, m[11] * iz
	)
	return cframe, Vector3.new(sx, sy, sz)
end

-- The camera's view matrix (world to camera)
local function ViewMatrix(camera)
	return CFrameToMatrix(camera.CFrame:Inverse())
end

-- An OpenGL perspective matrix for the camera's vertical FieldOfView. aspect defaults to the viewport's.
local function ProjectionMatrix(camera, nearPlane, farPlane, aspect)
	nearPlane, farPlane = nearPlane or 0.1, farPlane or 5000
	if aspect == nil then
		local viewport = camera.ViewportSize
		aspect = viewport.X / math.max(viewport.Y, 1)
	end
	local f = 1 / tan(rad(camera.FieldOfView) / 2)
	return {
		f / aspect, 0, 0, 0,
		0, f, 0, 0,
		0, 0, (farPlane + nearPlane) / (nearPlane - farPlane), -1,
		0, 0, 2 * farPlane * nearPlane / (nearPlane - farPlane), 0,
	}
end

function ImGuizmoAddon.Install(host)
	local Mem, Raw = host.Mem, host.Raw
	local E = Common(host).Exports("rbx_imguizmo_", {
		"buffers", "begin_frame", "set_drawlist", "set_rect", "set_orthographic", "enable", "set_id", "push_id", "push_id_int",
		"pop_id", "set_axis_mask", "manipulate", "view_manipulate", "decompose", "recompose", "draw", "query", "setting",
		"style_get", "style_set", "style_color_get", "style_color_set",
	})

	local function Call(closure, ...)
		return closure[1](closure, ...)
	end

	local buffers = (Call(E.buffers))

	local function Write(slot, values, count)
		local mem = Mem()
		for index = 1, count do
			writef32(mem, buffers + (slot + index - 1) * 4, values[index] or 0)
		end
	end

	local function Read(slot, count, into)
		local mem = Mem()
		into = into or table.create(count)
		for index = 1, count do
			into[index] = readf32(mem, buffers + (slot + index - 1) * 4)
		end
		return into
	end

	local function Ptr(handle)
		if handle == nil then
			return 0
		end
		return if type(handle) == "table" then handle.__ptr else handle
	end

	local function ColorU32(color)
		if type(color) == "number" then
			return color % 4294967296
		elseif color == nil then
			return 0
		end
		local r, g, b, a
		if color[1] ~= nil then
			r, g, b, a = color[1], color[2], color[3], color[4] or 1
		else
			r, g, b, a = color.R, color.G, color.B, 1
		end
		return floor(r * 255 + 0.5) + floor(g * 255 + 0.5) * 256 + floor(b * 255 + 0.5) * 65536 + floor(a * 255 + 0.5) * 16777216
	end

	local ImGuizmo = {
		OPERATION = OPERATION,
		MODE = MODE,
		COLOR = COLOR,
		CFrameToMatrix = CFrameToMatrix,
		MatrixToCFrame = MatrixToCFrame,
		ViewMatrix = ViewMatrix,
		ProjectionMatrix = ProjectionMatrix,
	}

	function ImGuizmo.BeginFrame()
		Call(E.begin_frame)
	end

	-- nil: the current window's draw list
	function ImGuizmo.SetDrawlist(drawList)
		Call(E.set_drawlist, Ptr(drawList))
	end

	function ImGuizmo.SetRect(x, y, width, height)
		Call(E.set_rect, x, y, width, height)
	end

	function ImGuizmo.SetOrthographic(isOrthographic)
		Call(E.set_orthographic, if isOrthographic then 1 else 0)
	end

	function ImGuizmo.Enable(enable)
		Call(E.enable, if enable == false then 0 else 1)
	end

	function ImGuizmo.SetID(id)
		Call(E.set_id, id)
	end

	function ImGuizmo.PushID(id)
		if type(id) == "number" then
			Call(E.push_id_int, id)
			return
		end
		local text = tostring(id)
		local ptr = host.Malloc(#text + 1)
		local mem = Mem()
		buffer.writestring(mem, ptr, text)
		buffer.writeu8(mem, ptr + #text, 0)
		Call(E.push_id, ptr)
		host.Free(ptr)
	end

	function ImGuizmo.PopID()
		Call(E.pop_id)
	end

	-- With an operation, whether the mouse is over that operation's handles
	function ImGuizmo.IsOver(operation)
		if operation ~= nil then
			return Call(E.query, 5, operation) ~= 0
		end
		return Call(E.query, 0, 0) ~= 0
	end

	for op, name in { [1] = "IsUsing", [2] = "IsUsingViewManipulate", [3] = "IsViewManipulateHovered", [4] = "IsUsingAny" } do
		ImGuizmo[name] = function()
			return Call(E.query, op, 0) ~= 0
		end
	end

	function ImGuizmo.SetGizmoSizeClipSpace(value)
		Call(E.setting, 0, value)
	end

	function ImGuizmo.AllowAxisFlip(value)
		Call(E.setting, 1, if value then 1 else 0)
	end

	function ImGuizmo.SetAxisLimit(value)
		Call(E.setting, 2, value)
	end

	function ImGuizmo.SetPlaneLimit(value)
		Call(E.setting, 3, value)
	end

	function ImGuizmo.SetAxisMask(x, y, z)
		Call(E.set_axis_mask, if x then 1 else 0, if y then 1 else 0, if z then 1 else 0)
	end

	-- Updates matrix (16 numbers) in place and returns changed, matrix, deltaMatrix.
	-- snap: { x, y, z } (or one number); localBounds: { minX, minY, minZ, maxX, maxY, maxZ } with OPERATION.BOUNDS
	function ImGuizmo.Manipulate(view, projection, operation, mode, matrix, snap, localBounds, boundsSnap)
		Write(VIEW, view, 16)
		Write(PROJECTION, projection, 16)
		Write(MATRIX, matrix, 16)
		if type(snap) == "number" then
			snap = { snap, snap, snap }
		end
		if snap ~= nil then
			Write(SNAP, snap, 3)
		end
		if localBounds ~= nil then
			Write(BOUNDS, localBounds, 6)
			Write(BOUNDS_SNAP, boundsSnap or { 0, 0, 0 }, 3)
		end
		local changed = Call(E.manipulate, operation, mode, if snap ~= nil then 1 else 0, if localBounds ~= nil then 1 else 0) ~= 0
		Read(MATRIX, 16, matrix)
		return changed, matrix, Read(DELTA, 16)
	end

	-- The view cube: updates view in place and returns it
	function ImGuizmo.ViewManipulate(view, length, position, size, backgroundColor)
		Write(VIEW, view, 16)
		Call(E.view_manipulate, length, position.X, position.Y, size.X, size.Y, ColorU32(backgroundColor))
		return Read(VIEW, 16, view)
	end

	-- Returns translation, rotation (degrees) and scale as { x, y, z } tables
	function ImGuizmo.DecomposeMatrixToComponents(matrix)
		Write(MATRIX, matrix, 16)
		Call(E.decompose)
		return Read(TRANSLATION, 3), Read(ROTATION, 3), Read(SCALE, 3)
	end

	function ImGuizmo.RecomposeMatrixFromComponents(translation, rotation, scale)
		Write(TRANSLATION, translation, 3)
		Write(ROTATION, rotation, 3)
		Write(SCALE, scale, 3)
		Call(E.recompose)
		return Read(MATRIX, 16)
	end

	function ImGuizmo.DrawGrid(view, projection, matrix, gridSize)
		Write(VIEW, view, 16)
		Write(PROJECTION, projection, 16)
		Write(MATRIX, matrix, 16)
		Call(E.draw, 0, gridSize)
	end

	local function DrawEach(what)
		return function(view, projection, matrices)
			Write(VIEW, view, 16)
			Write(PROJECTION, projection, 16)
			for _, matrix in matrices do
				Write(MATRIX, matrix, 16)
				Call(E.draw, what, 0)
			end
		end
	end

	-- matrices: a list of 16-number tables
	ImGuizmo.DrawCubes = DrawEach(1)
	ImGuizmo.DrawAxes = DrawEach(2)

	-- style.TranslationLineThickness = 4; style.Colors[ImGuizmo.COLOR.SELECTION] = Color3.new(1, 1, 0)
	local Colors = setmetatable({}, {
		__index = function(_, index)
			local u32 = Call(E.style_color_get, index) % 4294967296
			local function channel(shift)
				return (floor(u32 / shift) % 256) / 255
			end
			return { channel(1), channel(256), channel(65536), channel(16777216) }
		end,
		__newindex = function(_, index, color)
			Call(E.style_color_set, index, ColorU32(color))
		end,
	})
	local Style = setmetatable({}, {
		__index = function(_, key)
			if key == "Colors" then
				return Colors
			end
			local field = STYLE_FIELDS[key]
			return if field ~= nil then Call(E.style_get, field) else nil
		end,
		__newindex = function(_, key, value)
			local field = STYLE_FIELDS[key] or error(string.format('[ImGui] ImGuizmo.Style has no field "%s"', tostring(key)), 2)
			Call(E.style_set, field, value)
		end,
	})

	function ImGuizmo.GetStyle()
		return Style
	end

	-- Manipulates a CFrame with handles drawn over the game. Returns changed, the new CFrame, and the scale (a Vector3).
	-- options: Camera (workspace.CurrentCamera), Size (a Vector3 the scale starts from, default 1, 1, 1), Snap (a number
	-- or Vector3), DrawList (default: the foreground draw list), NearPlane and FarPlane
	function ImGuizmo.ManipulateCFrame(cframe, operation, mode, options)
		options = options or {}
		local camera = options.Camera or workspace.CurrentCamera
		local display = Raw.GetIO().DisplaySize
		Call(E.set_drawlist, Ptr(options.DrawList or Raw.GetForegroundDrawList()))
		Call(E.set_rect, 0, 0, display.X, display.Y)
		local snap = options.Snap
		if typeof(snap) == "Vector3" then
			snap = { snap.X, snap.Y, snap.Z }
		end
		local matrix = CFrameToMatrix(cframe, options.Size)
		local changed = ImGuizmo.Manipulate(ViewMatrix(camera), ProjectionMatrix(camera, options.NearPlane, options.FarPlane, display.X / math.max(display.Y, 1)),
			operation or OPERATION.TRANSLATE, mode or MODE.WORLD, matrix, snap)
		local newCFrame, scale = MatrixToCFrame(matrix)
		return changed, newCFrame, scale
	end

	return {
		Bind = function()
			return { ImGuizmo = ImGuizmo }
		end,
	}
end

return ImGuizmoAddon

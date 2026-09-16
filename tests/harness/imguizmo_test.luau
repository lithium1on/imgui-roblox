-- The ImGuizmo addon (imguizmo.luau) linked into the bundle: matrices round-trip through decompose and recompose, the
-- grid and gizmo draw, Manipulate leaves the matrix alone without input and moves it when a handle is dragged with the
-- mouse, style values read back, and the CFrame and camera helpers agree with a small CFrame stand-in.
local ImGui = ImGuiBundle
local W, H = 800, 600
local failures, warnings, stepErrors = 0, 0, 0

local realPrint = print
print = function(first, ...)
	if first == "[warn]" then
		warnings += 1
	end
	realPrint(first, ...)
end

local function check(name, ok)
	realPrint((if ok then "PASS " else "FAIL ") .. name)
	if not ok then
		failures += 1
	end
end

local function near(a, b, tolerance)
	return type(a) == "number" and math.abs(a - b) <= (tolerance or 1e-3)
end

-- Rigid CFrames: position and a rotation matrix given by rows
Vector3 = Vector3 or {
	new = function(x, y, z)
		return { X = x, Y = y, Z = z }
	end,
}
local CFrameMeta = {}
CFrameMeta.__index = CFrameMeta
function CFrameMeta:GetComponents()
	return table.unpack(self.c, 1, 12)
end
function CFrameMeta:Inverse()
	local x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22 = self:GetComponents()
	return CFrame.new(
		-(r00 * x + r10 * y + r20 * z), -(r01 * x + r11 * y + r21 * z), -(r02 * x + r12 * y + r22 * z),
		r00, r10, r20, r01, r11, r21, r02, r12, r22
	)
end
CFrame = {
	new = function(x, y, z, ...)
		local rotation = { ... }
		if #rotation == 0 then
			rotation = { 1, 0, 0, 0, 1, 0, 0, 0, 1 }
		end
		return setmetatable({ c = { x, y, z, table.unpack(rotation, 1, 9) } }, CFrameMeta)
	end,
}

ImGui.Init({
	RenderMode = "DrawingImmediate", DrawingImmediate = MockDrawingImmediate, AutoRender = false, Input = false,
	DisplaySize = Vector2.new(W, H), Addons = ImGuiAddons.imguizmo,
	MeasureText = function(_, size, text)
		return (utf8.len(text) or #text) * HarnessAdvance(size)
	end,
})
local ImGuizmo = ImGui.ImGuizmo
check("ImGui.ImGuizmo and its enums", ImGuizmo ~= nil and ImGuizmo.OPERATION.TRANSLATE == 7 and ImGuizmo.MODE.WORLD == 1
	and ImGuizmo.COLOR.COUNT == 15)

local matrix = ImGuizmo.RecomposeMatrixFromComponents({ 1, 2, 3 }, { 0, 90, 0 }, { 2, 2, 2 })
local t, r, s = ImGuizmo.DecomposeMatrixToComponents(matrix)
check(string.format("decompose(recompose) round-trips (%.2f %.2f %.2f / %.2f / %.2f)", t[1], t[2], t[3], r[2], s[1]),
	near(t[1], 1) and near(t[2], 2) and near(t[3], 3) and near(r[2], 90, 0.01) and near(s[1], 2) and near(s[3], 2))

local rotated = CFrame.new(5, 6, 7, 0, 0, 1, 0, 1, 0, -1, 0, 0) -- 90 degrees around Y
local cframe, scale = ImGuizmo.MatrixToCFrame(ImGuizmo.CFrameToMatrix(rotated, Vector3.new(2, 3, 4)))
local a, b = { rotated:GetComponents() }, { cframe:GetComponents() }
local same = true
for index = 1, 12 do
	same = same and near(a[index], b[index])
end
check("CFrameToMatrix and MatrixToCFrame round-trip with a scale", same and near(scale.X, 2) and near(scale.Y, 3) and near(scale.Z, 4))

local camera = { CFrame = CFrame.new(0, 0, 10), FieldOfView = 70, ViewportSize = Vector2.new(W, H) }
local view = ImGuizmo.ViewMatrix(camera)
local projection = ImGuizmo.ProjectionMatrix(camera)
check("ViewMatrix moves the world opposite to the camera", near(view[15], -10) and near(view[1], 1))
check("ProjectionMatrix is a perspective projection", near(projection[12], -1) and projection[1] > 0 and projection[6] > 0)

local style = ImGuizmo.GetStyle()
style.TranslationLineThickness = 5
style.Colors[ImGuizmo.COLOR.SELECTION] = Color3.new(1, 0, 0)
local selection = style.Colors[ImGuizmo.COLOR.SELECTION]
check("style values read back", near(style.TranslationLineThickness, 5) and near(selection[1], 1) and near(selection[2], 0))

local identity = { 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1 }
local gizmoMatrix = table.clone(identity)
local seen = {}
ImGui.OnFrame(function()
	ImGuizmo.BeginFrame()
	ImGuizmo.SetRect(0, 0, W, H)
	ImGuizmo.DrawGrid(view, projection, identity, 10)
	local changed = ImGuizmo.Manipulate(view, projection, ImGuizmo.OPERATION.TRANSLATE, ImGuizmo.MODE.WORLD, gizmoMatrix)
	seen.changed = seen.changed or changed
	seen.over = ImGuizmo.IsOver()
	seen.using = ImGuizmo.IsUsing()
	local helperChanged, helperCFrame = ImGuizmo.ManipulateCFrame(CFrame.new(100, 0, 0), ImGuizmo.OPERATION.ROTATE, ImGuizmo.MODE.LOCAL,
		{ Camera = camera })
	seen.helperChanged, seen.helperCFrame = helperChanged, helperCFrame
end)

local function frame()
	table.clear(DrawCalls)
	local ok, err = pcall(ImGui.Step, 1 / 60, W, H)
	if not ok then
		stepErrors += 1
		realPrint("  step error: " .. tostring(err))
	end
end

frame()
local calls = #DrawCalls
check(string.format("the grid and gizmo draw (%d calls) without errors or assertions", calls), calls > 10 and stepErrors == 0 and warnings == 0)
check("Manipulate leaves the matrix alone without input", not seen.changed and not seen.using and near(gizmoMatrix[13], 0))
check("ManipulateCFrame returns the CFrame unchanged without input", seen.helperChanged == false
	and near(({ seen.helperCFrame:GetComponents() })[1], 100))

-- Find a point over the X axis handle, which runs right from the screen center, then drag it
local handle = nil
for x = 410, 560, 6 do
	ImGui.AddMousePosEvent(x, H / 2)
	frame()
	if seen.over then
		handle = x
		break
	end
end
check("the mouse finds the X axis handle", handle ~= nil)
if handle ~= nil then
	ImGui.AddMouseButtonEvent(0, true)
	frame()
	for step = 1, 4 do
		ImGui.AddMousePosEvent(handle + step * 20, H / 2)
		frame()
	end
	local using = seen.using
	ImGui.AddMouseButtonEvent(0, false)
	frame()
	check(string.format("dragging the handle moves the matrix along X (%.3f, %.3f)", gizmoMatrix[13], gizmoMatrix[14]),
		using and seen.changed and gizmoMatrix[13] > 0.1 and near(gizmoMatrix[14], 0, 1e-2))
end
check(string.format("no errors (%d) or assertions (%d) while dragging", stepErrors, warnings), stepErrors == 0 and warnings == 0)

ImGui.Shutdown()
realPrint(string.format("RESULT %d failure(s)", failures))

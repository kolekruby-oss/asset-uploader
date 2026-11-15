--[[
  Custom SaveInstance Exporter  |  Xeno Executor  |  Output: .rbxlx (Roblox XML place file)
  Only for experiences you own or have permission to export.
  Modules: Compat, ErrorHandler, Progress, Batch, ServiceManager, Scanner, Serializer,
           TerrainExporter, FileWriter, UI, Controller
  NOT tested inside Xeno by the author. See notes at the bottom of the response.
]]

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local CONFIG = {
	BatchSize = 150,           -- instances per batch before yielding
	TerrainChunk = 32,         -- voxels per axis per ReadVoxels chunk
	OutputFile = "SaveInstance_" .. tostring(game.PlaceId) .. ".rbxlx",
	ReportFile = "SaveInstance_" .. tostring(game.PlaceId) .. "_report.txt",
}

local State = { cancelled = false, running = false }

--------------------------------------------------------------------------------
-- COMPAT: only reports/uses functions that actually exist
--------------------------------------------------------------------------------
local Compat = {}
Compat.caps = {
	writefile = typeof(writefile) == "function" and writefile or nil,
	appendfile = typeof(appendfile) == "function" and appendfile or nil,
	delfile = typeof(delfile) == "function" and delfile or nil,
	isfile = typeof(isfile) == "function" and isfile or nil,
	gethiddenproperty = typeof(gethiddenproperty) == "function" and gethiddenproperty or nil,
	decompile = typeof(decompile) == "function" and decompile or nil,
	gethui = typeof(gethui) == "function" and gethui or nil,
}

function Compat.report()
	local lines = {}
	for _, k in ipairs({ "writefile", "appendfile", "delfile", "isfile", "gethiddenproperty", "decompile", "gethui" }) do
		lines[#lines + 1] = k .. ": " .. (Compat.caps[k] and "yes" or "NO")
	end
	return table.concat(lines, ", ")
end

--------------------------------------------------------------------------------
-- ERROR HANDLER: aggregated, nothing is skipped silently
--------------------------------------------------------------------------------
local Errors = { list = {}, index = {} }

function Errors.reset()
	Errors.list, Errors.index = {}, {}
end

function Errors.log(kind, class, msg)
	local key = kind .. "|" .. class .. "|" .. msg
	local e = Errors.index[key]
	if not e then
		e = { kind = kind, class = class, msg = msg, count = 0 }
		Errors.index[key] = e
		Errors.list[#Errors.list + 1] = e
	end
	e.count = e.count + 1
end

function Errors.format()
	local lines = { "SaveInstance report", "Compat: " .. Compat.report(), "" }
	for _, e in ipairs(Errors.list) do
		lines[#lines + 1] = string.format("[%s] %s: %s (x%d)", e.kind, e.class, e.msg, e.count)
	end
	return table.concat(lines, "\n")
end

--------------------------------------------------------------------------------
-- PROGRESS: real counters only
--------------------------------------------------------------------------------
local Progress = { state = {}, onUpdate = nil }

function Progress.reset()
	Progress.state = {
		phase = "Idle", total = 0, processed = 0, exported = 0,
		failed = 0, skipped = 0, status = "Ready", done = false,
	}
end

function Progress.emit()
	if Progress.onUpdate then
		pcall(Progress.onUpdate, Progress.state)
	end
end

function Progress.percent()
	local s = Progress.state
	if s.done then return 100 end
	if s.total <= 0 then return 0 end
	return math.min(99, math.floor(s.processed / s.total * 100))
end

Progress.reset()

--------------------------------------------------------------------------------
-- BATCH PROCESSOR
--------------------------------------------------------------------------------
local Batch = {}

local function isCancelled()
	return State.cancelled
end

-- Runs fn over list in batches, yields between batches. Returns false if cancelled.
function Batch.run(list, fn, size)
	local i, n = 1, #list
	while i <= n do
		if isCancelled() then return false end
		local last = math.min(i + size - 1, n)
		for k = i, last do
			local ok, err = pcall(fn, list[k])
			if not ok then
				Errors.log("failed", "BatchHandler", tostring(err))
			end
		end
		i = last + 1
		Progress.emit()
		task.wait()
	end
	return not isCancelled()
end

-- Stepper for loops that cannot be pre-listed. Returns false when cancelled.
function Batch.newStepper(size)
	local c = 0
	return function()
		c = c + 1
		if c >= size then
			c = 0
			Progress.emit()
			task.wait()
			if isCancelled() then return false end
		end
		return true
	end
end

--------------------------------------------------------------------------------
-- SERVICE MANAGER
--------------------------------------------------------------------------------
local ServiceManager = {
	names = {
		"Workspace", "ReplicatedStorage", "ReplicatedFirst", "StarterGui", "StarterPlayer",
		"Players", "Lighting", "SoundService", "Teams", "MaterialService",
	},
}

function ServiceManager.get(name)
	local ok, svc = pcall(game.GetService, game, name)
	if ok and svc then return svc end
	return nil
end

--------------------------------------------------------------------------------
-- Shared registry (referents + excluded set)
--------------------------------------------------------------------------------
local Registry = { refs = {}, excluded = {}, nextId = 0, step = nil, chunks = {} }

function Registry.reset()
	Registry.refs, Registry.excluded, Registry.nextId, Registry.chunks = {}, {}, 0, {}
end

function Registry.assign(inst)
	Registry.nextId = Registry.nextId + 1
	Registry.refs[inst] = "RBX" .. Registry.nextId
end

--------------------------------------------------------------------------------
-- Helpers: XML escaping, base64, numbers
--------------------------------------------------------------------------------
local function esc(s)
	s = string.gsub(s, "[\0-\8\11\12\14-\31]", "")
	s = string.gsub(s, "&", "&amp;")
	s = string.gsub(s, "<", "&lt;")
	s = string.gsub(s, ">", "&gt;")
	s = string.gsub(s, '"', "&quot;")
	s = string.gsub(s, "'", "&apos;")
	return s
end

local function cdata(s)
	s = string.gsub(s, "[\0-\8\11\12\14-\31]", "")
	return (string.gsub(s, "]]>", "]]]]><![CDATA[>"))
end

local B64 = {}
do
	local alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
	for i = 0, 63 do B64[i] = string.sub(alphabet, i + 1, i + 1) end
end

local function b64(s)
	local out = {}
	local len = #s
	local SLICE = 3 * 8192
	local i = 1
	while i <= len do
		local j = math.min(i + SLICE - 1, len)
		local sl, n = {}, 0
		for k = i, j, 3 do
			local a, b, c = string.byte(s, k, math.min(k + 2, len))
			local v = a * 65536 + (b or 0) * 256 + (c or 0)
			n = n + 1
			sl[n] = B64[math.floor(v / 262144) % 64] .. B64[math.floor(v / 4096) % 64]
				.. (b and B64[math.floor(v / 64) % 64] or "=") .. (c and B64[v % 64] or "=")
		end
		out[#out + 1] = table.concat(sl)
		i = j + 1
		if len > SLICE and i <= len then task.wait() end
	end
	return table.concat(out)
end

local function num(v)
	if v ~= v then return "NAN" end
	if v == math.huge then return "INF" end
	if v == -math.huge then return "-INF" end
	return string.format("%.9g", v)
end

--------------------------------------------------------------------------------
-- SERIALIZER: type writers
--------------------------------------------------------------------------------
local W = {}
W.string = function(n, v) return '<string name="' .. n .. '">' .. esc(v) .. "</string>" end
W.bool = function(n, v) return '<bool name="' .. n .. '">' .. tostring(v) .. "</bool>" end
W.int = function(n, v) return '<int name="' .. n .. '">' .. string.format("%d", v) .. "</int>" end
W.float = function(n, v) return '<float name="' .. n .. '">' .. num(v) .. "</float>" end
W.double = function(n, v) return '<double name="' .. n .. '">' .. num(v) .. "</double>" end
W.token = function(n, v)
	local val = typeof(v) == "EnumItem" and v.Value or tonumber(v)
	return '<token name="' .. n .. '">' .. string.format("%d", val) .. "</token>"
end
W.brickcolor = function(n, v) return '<int name="' .. n .. '">' .. string.format("%d", v.Number) .. "</int>" end
W.Vector2 = function(n, v)
	return '<Vector2 name="' .. n .. '"><X>' .. num(v.X) .. "</X><Y>" .. num(v.Y) .. "</Y></Vector2>"
end
W.Vector3 = function(n, v)
	return '<Vector3 name="' .. n .. '"><X>' .. num(v.X) .. "</X><Y>" .. num(v.Y) .. "</Y><Z>" .. num(v.Z) .. "</Z></Vector3>"
end
W.Color3 = function(n, v)
	return '<Color3 name="' .. n .. '"><R>' .. num(v.R) .. "</R><G>" .. num(v.G) .. "</G><B>" .. num(v.B) .. "</B></Color3>"
end
W.Color3uint8 = function(n, v)
	local r = math.floor(v.R * 255 + 0.5)
	local g = math.floor(v.G * 255 + 0.5)
	local b = math.floor(v.B * 255 + 0.5)
	return '<Color3uint8 name="' .. n .. '">' .. string.format("%d", 4278190080 + r * 65536 + g * 256 + b) .. "</Color3uint8>"
end
W.UDim = function(n, v)
	return '<UDim name="' .. n .. '"><S>' .. num(v.Scale) .. "</S><O>" .. string.format("%d", v.Offset) .. "</O></UDim>"
end
W.UDim2 = function(n, v)
	return '<UDim2 name="' .. n .. '"><XS>' .. num(v.X.Scale) .. "</XS><XO>" .. string.format("%d", v.X.Offset)
		.. "</XO><YS>" .. num(v.Y.Scale) .. "</YS><YO>" .. string.format("%d", v.Y.Offset) .. "</YO></UDim2>"
end
local CF_NAMES = { "X", "Y", "Z", "R00", "R01", "R02", "R10", "R11", "R12", "R20", "R21", "R22" }
W.CFrame = function(n, v)
	local c = { v:GetComponents() }
	local t = { '<CoordinateFrame name="' .. n .. '">' }
	for i = 1, 12 do
		t[#t + 1] = "<" .. CF_NAMES[i] .. ">" .. num(c[i]) .. "</" .. CF_NAMES[i] .. ">"
	end
	t[#t + 1] = "</CoordinateFrame>"
	return table.concat(t)
end
W.content = function(n, v)
	if v == nil or v == "" then
		return '<Content name="' .. n .. '"><null></null></Content>'
	end
	return '<Content name="' .. n .. '"><url>' .. esc(tostring(v)) .. "</url></Content>"
end
W.ref = function(n, v)
	local r = Registry.refs[v]
	if r then return '<Ref name="' .. n .. '">' .. r .. "</Ref>" end
	Errors.log("note", "Ref", n .. " points outside export set, written as null")
	return '<Ref name="' .. n .. '">null</Ref>'
end

--------------------------------------------------------------------------------
-- SERIALIZER: property maps ("Name:type[:fileName]")
--------------------------------------------------------------------------------
local TEXT = { "Text:string", "TextColor3:Color3", "TextSize:int", "TextScaled:bool", "TextWrapped:bool",
	"TextTransparency:float", "Font:token", "TextXAlignment:token", "TextYAlignment:token" }
local IMAGE = { "Image:content", "ImageColor3:Color3", "ImageTransparency:float", "ScaleType:token" }

local CLASS_PROPS = {
	{ "Instance", { "Name:string", "Archivable:bool" } },
	{ "Model", { "PrimaryPart:ref" } },
	{ "BasePart", { "Anchored:bool", "CanCollide:bool", "CanTouch:bool", "CanQuery:bool", "CastShadow:bool",
		"Massless:bool", "Locked:bool", "Transparency:float", "Reflectance:float", "Material:token",
		"CFrame:CFrame", "Size:Vector3:size", "Color:Color3uint8:Color3uint8", "CollisionGroup:string" } },
	{ "Part", { "Shape:token:shape" } },
	{ "MeshPart", { "MeshId:content", "TextureID:content", "CollisionFidelity:token", "RenderFidelity:token" } },
	{ "SpawnLocation", { "Neutral:bool", "Duration:int", "AllowTeamChangeOnTouch:bool", "TeamColor:brickcolor" } },
	{ "SpecialMesh", { "MeshId:content", "TextureId:content", "MeshType:token", "Scale:Vector3", "Offset:Vector3", "VertexColor:Vector3" } },
	{ "Decal", { "Texture:content", "Face:token", "Color3:Color3", "Transparency:float", "ZIndex:int" } },
	{ "Texture", { "StudsPerTileU:float", "StudsPerTileV:float" } },
	{ "Attachment", { "CFrame:CFrame", "Visible:bool" } },
	{ "JointInstance", { "Part0:ref", "Part1:ref", "C0:CFrame", "C1:CFrame" } },
	{ "WeldConstraint", { "Part0:ref", "Part1:ref" } },
	{ "Light", { "Brightness:float", "Color:Color3", "Enabled:bool", "Shadows:bool" } },
	{ "PointLight", { "Range:float" } },
	{ "SpotLight", { "Range:float", "Angle:float" } },
	{ "SurfaceLight", { "Range:float", "Angle:float", "Face:token" } },
	{ "Sound", { "SoundId:content", "Volume:float", "PlaybackSpeed:float", "Looped:bool",
		"RollOffMaxDistance:float", "RollOffMinDistance:float" } },
	{ "StringValue", { "Value:string" } },
	{ "BoolValue", { "Value:bool" } },
	{ "IntValue", { "Value:int" } },
	{ "NumberValue", { "Value:double" } },
	{ "ObjectValue", { "Value:ref" } },
	{ "Color3Value", { "Value:Color3" } },
	{ "Vector3Value", { "Value:Vector3" } },
	{ "CFrameValue", { "Value:CFrame" } },
	{ "Script", { "Disabled:bool", "RunContext:token" } },
	{ "LocalScript", { "Disabled:bool" } },
	{ "GuiObject", { "Active:bool", "AnchorPoint:Vector2", "BackgroundColor3:Color3", "BackgroundTransparency:float",
		"BorderColor3:Color3", "BorderSizePixel:int", "Position:UDim2", "Size:UDim2", "Rotation:float",
		"Visible:bool", "ZIndex:int", "LayoutOrder:int", "ClipsDescendants:bool" } },
	{ "TextLabel", TEXT }, { "TextButton", TEXT }, { "TextBox", TEXT },
	{ "ImageLabel", IMAGE }, { "ImageButton", IMAGE },
	{ "ScreenGui", { "ResetOnSpawn:bool", "DisplayOrder:int", "Enabled:bool", "IgnoreGuiInset:bool" } },
	{ "UICorner", { "CornerRadius:UDim" } },
	{ "UIStroke", { "Color:Color3", "Thickness:float", "Transparency:float" } },
	{ "UIListLayout", { "FillDirection:token", "SortOrder:token", "Padding:UDim",
		"HorizontalAlignment:token", "VerticalAlignment:token" } },
	{ "Workspace", { "Gravity:float", "FallenPartsDestroyHeight:float" } },
	{ "Terrain", { "WaterColor:Color3", "WaterReflectance:float", "WaterTransparency:float",
		"WaterWaveSize:float", "WaterWaveSpeed:float", "Decoration:bool" } },
	{ "Lighting", { "Ambient:Color3", "OutdoorAmbient:Color3", "Brightness:float", "ColorShift_Top:Color3",
		"ColorShift_Bottom:Color3", "FogColor:Color3", "FogEnd:float", "FogStart:float", "GlobalShadows:bool",
		"EnvironmentDiffuseScale:float", "EnvironmentSpecularScale:float", "ExposureCompensation:float",
		"ClockTime:float", "GeographicLatitude:float", "Technology:token" } },
	{ "Sky", { "SkyboxBk:content", "SkyboxDn:content", "SkyboxFt:content", "SkyboxLf:content",
		"SkyboxRt:content", "SkyboxUp:content", "StarCount:int", "CelestialBodiesShown:bool",
		"SunAngularSize:float", "MoonAngularSize:float" } },
	{ "Atmosphere", { "Density:float", "Offset:float", "Color:Color3", "Decay:Color3", "Glare:float", "Haze:float" } },
	{ "PostEffect", { "Enabled:bool" } },
	{ "BloomEffect", { "Intensity:float", "Size:float", "Threshold:float" } },
	{ "BlurEffect", { "Size:float" } },
	{ "ColorCorrectionEffect", { "Brightness:float", "Contrast:float", "Saturation:float", "TintColor:Color3" } },
	{ "SunRaysEffect", { "Intensity:float", "Spread:float" } },
	{ "Team", { "TeamColor:brickcolor", "AutoAssignable:bool" } },
	{ "SoundService", { "AmbientReverb:token", "DistanceFactor:float", "DopplerScale:float", "RolloffScale:float" } },
	{ "MaterialVariant", { "BaseMaterial:token", "ColorMap:content", "MetalnessMap:content",
		"NormalMap:content", "RoughnessMap:content", "StudsPerTile:float" } },
	{ "Camera", { "CFrame:CFrame", "FieldOfView:float" } },
}

-- classes that are plain containers: no partial warning when only Name is exported
local PLAIN = {
	Folder = true, Configuration = true, StarterPlayer = true, StarterPlayerScripts = true,
	StarterCharacterScripts = true, ReplicatedStorage = true, ReplicatedFirst = true, StarterGui = true,
	Teams = true, MaterialService = true, Players = true, StarterPack = true,
}

for _, entry in ipairs(CLASS_PROPS) do
	local parsed = {}
	for _, s in ipairs(entry[2]) do
		local n, t, f = string.match(s, "^([^:]+):([^:]+):?(.*)$")
		parsed[#parsed + 1] = { n = n, t = t, f = (f ~= "" and f) or n }
	end
	entry.props = parsed
end

local function getprop(inst, name)
	return inst[name]
end

local propCache = {}

local function resolve(inst)
	local cn = inst.ClassName
	local c = propCache[cn]
	if c then return c end
	local list, matched = {}, 0
	for _, entry in ipairs(CLASS_PROPS) do
		local okIs, isA = pcall(inst.IsA, inst, entry[1])
		if okIs and isA then
			for _, p in ipairs(entry.props) do list[#list + 1] = p end
			if entry[1] ~= "Instance" then matched = matched + 1 end
		end
	end
	c = { props = list, partial = (matched == 0 and not PLAIN[cn]), defaults = nil }
	-- default values (to skip unchanged properties); only for creatable classes
	local okNew, d = pcall(Instance.new, cn)
	if okNew and d then
		local defs = {}
		for _, p in ipairs(list) do
			if p.t ~= "ref" then
				local okp, v = pcall(getprop, d, p.n)
				if okp and v ~= nil then defs[p.n] = v end
			end
		end
		c.defaults = defs
		pcall(d.Destroy, d)
	end
	propCache[cn] = c
	return c
end

-- Attribute binary (AttributesSerialize). Type ids: String 0x02, Bool 0x03, Float64 0x06,
-- Color3 0x0F, Vector3 0x11. Other attribute types are reported, not written.
local function attributeBinary(inst, cn)
	local attrs = inst:GetAttributes()
	local names = {}
	for k in pairs(attrs) do names[#names + 1] = k end
	if #names == 0 then return nil end
	table.sort(names)
	local out, count = {}, 0
	for _, k in ipairs(names) do
		local v = attrs[k]
		local t = typeof(v)
		local tag, payload
		if t == "string" then
			tag, payload = 0x02, string.pack("<I4", #v) .. v
		elseif t == "boolean" then
			tag, payload = 0x03, (v and "\1" or "\0")
		elseif t == "number" then
			tag, payload = 0x06, string.pack("<d", v)
		elseif t == "Vector3" then
			tag, payload = 0x11, string.pack("<fff", v.X, v.Y, v.Z)
		elseif t == "Color3" then
			tag, payload = 0x0F, string.pack("<fff", v.R, v.G, v.B)
		else
			Errors.log("partial", cn, "attribute type " .. t .. " not supported, attribute dropped")
		end
		if tag then
			count = count + 1
			out[#out + 1] = string.pack("<I4", #k) .. k .. string.char(tag) .. payload
		end
	end
	if count == 0 then return nil end
	return string.pack("<I4", count) .. table.concat(out)
end

--------------------------------------------------------------------------------
-- TERRAIN EXPORTER
--------------------------------------------------------------------------------
local TerrainExporter = { result = nil }

function TerrainExporter.reset()
	TerrainExporter.result = nil
end

-- Builds chunk list from Terrain.MaxExtents (voxel units, resolution 4).
function TerrainExporter.plan(terrain)
	Registry.chunks = {}
	local ok, ext = pcall(getprop, terrain, "MaxExtents")
	if not ok or typeof(ext) ~= "Region3int16" then
		Errors.log("warning", "Terrain", "MaxExtents unavailable, voxel verification skipped")
		return
	end
	local mn, mx = ext.Min, ext.Max
	local C = CONFIG.TerrainChunk
	local chunks = {}
	for x = mn.X, mx.X, C do
		for y = mn.Y, mx.Y, C do
			for z = mn.Z, mx.Z, C do
				chunks[#chunks + 1] = { x, y, z }
			end
		end
	end
	Registry.chunks = chunks
end

-- Returns XML fragment with terrain binary properties. Raises "CANCELLED" on cancel.
function TerrainExporter.fragment(inst)
	local out = {}
	local gridBytes = 0
	if Compat.caps.gethiddenproperty then
		for _, key in ipairs({ "SmoothGrid", "PhysicsGrid", "MaterialColors" }) do
			local ok, v = pcall(Compat.caps.gethiddenproperty, inst, key)
			if ok and type(v) == "string" and v ~= "" then
				out[#out + 1] = '<BinaryString name="' .. key .. '">' .. b64(v) .. "</BinaryString>"
				if key == "SmoothGrid" then gridBytes = #v end
			else
				Errors.log("warning", "Terrain", key .. " not readable via gethiddenproperty")
			end
		end
	else
		Errors.log("warning", "Terrain", "gethiddenproperty missing: terrain binary data cannot be read")
	end

	-- verify voxel data chunk by chunk (real progress)
	local C = CONFIG.TerrainChunk
	local chunks = Registry.chunks
	local voxels, nonEmpty = 0, 0
	local mats = {}
	for ci = 1, #chunks do
		if State.cancelled then error("CANCELLED") end
		local c = chunks[ci]
		local region = Region3.new(Vector3.new(c[1], c[2], c[3]) * 4, Vector3.new(c[1] + C, c[2] + C, c[3] + C) * 4)
		local ok, m, o = pcall(inst.ReadVoxels, inst, region, 4)
		if ok and type(o) == "table" then
			local found = 0
			for x = 1, #o do
				local ox, mx = o[x], m[x]
				for y = 1, #ox do
					local oy, my = ox[y], mx[y]
					for z = 1, #oy do
						if oy[z] > 0 then
							found = found + 1
							local nm = my[z].Name
							mats[nm] = (mats[nm] or 0) + 1
						end
					end
				end
			end
			if found > 0 then nonEmpty = nonEmpty + 1 end
			voxels = voxels + found
		else
			Errors.log("failed", "Terrain", "ReadVoxels failed: " .. tostring(m))
		end
		Progress.state.processed = Progress.state.processed + 1
		Progress.state.status = string.format("Terrain chunk %d/%d", ci, #chunks)
		if Registry.step and not Registry.step() then error("CANCELLED") end
	end

	local matList = {}
	for k, v in pairs(mats) do matList[#matList + 1] = k .. "=" .. v end
	table.sort(matList)
	if gridBytes > 0 then
		if voxels == 0 then
			Errors.log("warning", "Terrain", "SmoothGrid present but ReadVoxels found no solid voxels, verify in Studio")
		end
		TerrainExporter.result = string.format("Terrain: SmoothGrid written (%d bytes). Verified %d solid voxels in %d/%d chunks. Materials: %s",
			gridBytes, voxels, nonEmpty, #chunks, table.concat(matList, ", "))
	elseif voxels > 0 then
		Errors.log("failed", "Terrain", "NOT EXPORTED: " .. voxels .. " voxels readable but SmoothGrid unavailable, cannot encode")
		TerrainExporter.result = "Terrain: NOT EXPORTED (voxels exist but SmoothGrid could not be read)"
	else
		TerrainExporter.result = "Terrain: no solid voxels found (empty or unreadable)"
	end
	return table.concat(out)
end

--------------------------------------------------------------------------------
-- SERIALIZER: one instance -> XML open fragment; DFS driver
--------------------------------------------------------------------------------
local Serializer = {}

function Serializer.open(inst)
	local cn = inst.ClassName
	local info = resolve(inst)
	local out = { '<Item class="', cn, '" referent="', Registry.refs[inst], '"><Properties>' }

	if info.partial then
		Errors.log("partial", cn, "no property map: only Name, attributes and tags exported")
	end

	for i = 1, #info.props do
		local p = info.props[i]
		local ok, v = pcall(getprop, inst, p.n)
		if not ok then
			Errors.log("property", cn, p.n .. " unreadable")
		elseif v ~= nil then
			local d = info.defaults and info.defaults[p.n]
			if p.n == "Name" or d == nil or v ~= d then
				local okw, s = pcall(W[p.t], p.f, v)
				if okw then
					out[#out + 1] = s
				else
					Errors.log("property", cn, p.n .. " serialize error")
				end
			end
		end
	end

	if inst:IsA("LuaSourceContainer") then
		local src
		local ok, s = pcall(getprop, inst, "Source")
		if ok and type(s) == "string" and s ~= "" then src = s end
		if not src and Compat.caps.decompile then
			local ok2, s2 = pcall(Compat.caps.decompile, inst)
			if ok2 and type(s2) == "string" and s2 ~= "" then src = s2 end
		end
		if not src then
			src = "-- [SaveInstance] source unavailable"
			Errors.log("partial", cn, "script source unavailable")
		end
		out[#out + 1] = '<ProtectedString name="Source"><![CDATA[' .. cdata(src) .. "]]></ProtectedString>"
	end

	local okA, attrBin = pcall(attributeBinary, inst, cn)
	if okA and attrBin then
		out[#out + 1] = '<BinaryString name="AttributesSerialize">' .. b64(attrBin) .. "</BinaryString>"
	elseif not okA then
		Errors.log("partial", cn, "attributes unreadable")
	end

	local okT, tags = pcall(inst.GetTags, inst)
	if okT and tags and #tags > 0 then
		out[#out + 1] = '<BinaryString name="Tags">' .. b64(table.concat(tags, "\0")) .. "</BinaryString>"
	end

	if cn == "Terrain" then
		out[#out + 1] = TerrainExporter.fragment(inst)
	end

	out[#out + 1] = "</Properties>"
	return table.concat(out)
end

local function failSubtree(inst, reasonClass)
	local ok, desc = pcall(inst.GetDescendants, inst)
	if not ok then return end
	local s = Progress.state
	for _, d in ipairs(desc) do
		if Registry.refs[d] then
			Registry.refs[d] = nil
			s.skipped = s.skipped + 1
			s.processed = s.processed + 1
			Errors.log("skipped", d.ClassName, "parent " .. reasonClass .. " failed to serialize")
		end
	end
end

-- Exports every root (service). Returns false when cancelled.
function Serializer.run(roots, writer)
	local step = Batch.newStepper(CONFIG.BatchSize)
	Registry.step = step
	local s = Progress.state

	for _, root in ipairs(roots) do
		local stack = {}

		local function push(inst)
			local ok, frag = pcall(Serializer.open, inst)
			if not ok then
				if not State.cancelled then
					Errors.log("failed", inst.ClassName, tostring(frag))
				end
				s.failed = s.failed + 1
				s.processed = s.processed + 1
				Registry.refs[inst] = nil
				failSubtree(inst, inst.ClassName)
				return
			end
			writer.add(frag)
			s.exported = s.exported + 1
			s.processed = s.processed + 1
			stack[#stack + 1] = { kids = inst:GetChildren(), i = 0 }
		end

		s.status = "Exporting " .. root.Name
		push(root)
		while #stack > 0 do
			if State.cancelled then return false end
			local f = stack[#stack]
			f.i = f.i + 1
			local kid = f.kids[f.i]
			if kid then
				if Registry.refs[kid] then
					push(kid)
				elseif not Registry.excluded[kid] then
					-- created after scan, or dropped because a parent failed
					if kid.Parent and not Registry.refs[kid.Parent] then
						-- parent failed: already counted
					else
						Errors.log("skipped", kid.ClassName, "created after scan")
						s.total = s.total + 1
						s.skipped = s.skipped + 1
						s.processed = s.processed + 1
					end
				end
				if not step() then return false end
			else
				writer.add("</Item>")
				stack[#stack] = nil
			end
		end
	end
	return not State.cancelled
end

--------------------------------------------------------------------------------
-- SCANNER
--------------------------------------------------------------------------------
local Scanner = {}

local EXCLUDE_CLASS = {
	Player = "Player objects cannot be stored in a place file",
}

-- Returns { roots = {...}, scanned = n, excluded = n } or nil when cancelled.
function Scanner.scan(serviceNames)
	Registry.reset()
	local roots, lists, total = {}, {}, 0
	for _, name in ipairs(serviceNames) do
		local svc = ServiceManager.get(name)
		if svc then
			local ok, desc = pcall(svc.GetDescendants, svc)
			if ok then
				roots[#roots + 1] = svc
				lists[#lists + 1] = desc
				total = total + #desc + 1
			else
				Errors.log("failed", name, "GetDescendants failed")
			end
		else
			Errors.log("failed", name, "service not accessible")
		end
	end

	local s = Progress.state
	s.phase, s.total, s.processed = "Scan", total, 0
	local excludedN = 0

	local function scanOne(inst)
		s.processed = s.processed + 1
		if Registry.refs[inst] or Registry.excluded[inst] then return end
		local cn = inst.ClassName
		local reason = EXCLUDE_CLASS[cn]
		if Registry.excluded[inst.Parent] then
			reason = "parent excluded"
		elseif not reason and cn == "Model" and Players:GetPlayerFromCharacter(inst) then
			reason = "player character"
		end
		if reason then
			Registry.excluded[inst] = true
			excludedN = excludedN + 1
			Errors.log("skipped", cn, reason)
		else
			Registry.assign(inst)
		end
	end

	for idx, svc in ipairs(roots) do
		s.status = "Scanning " .. svc.Name
		Registry.assign(svc)
		s.processed = s.processed + 1
		if not Batch.run(lists[idx], scanOne, CONFIG.BatchSize) then return nil end
	end

	-- terrain plan
	local chunkCount = 0
	for _, svc in ipairs(roots) do
		if svc.ClassName == "Workspace" then
			local t = svc:FindFirstChildOfClass("Terrain")
			if t and Registry.refs[t] then
				TerrainExporter.plan(t)
				chunkCount = #Registry.chunks
			end
		end
	end

	return { roots = roots, scanned = total, excluded = excludedN, chunks = chunkCount }
end

--------------------------------------------------------------------------------
-- FILE WRITER
--------------------------------------------------------------------------------
local FileWriter = { buf = {}, size = 0, mode = "memory", path = nil }

function FileWriter.open(path)
	FileWriter.path, FileWriter.buf, FileWriter.size = path, {}, 0
	if Compat.caps.appendfile then
		FileWriter.mode = "stream"
		Compat.caps.writefile(path, "")
	else
		FileWriter.mode = "memory"
		Errors.log("warning", "FileWriter", "appendfile missing: whole file buffered in memory")
	end
end

function FileWriter.flush()
	if FileWriter.mode == "stream" and #FileWriter.buf > 0 then
		Compat.caps.appendfile(FileWriter.path, table.concat(FileWriter.buf))
		FileWriter.buf, FileWriter.size = {}, 0
	end
end

function FileWriter.add(str)
	FileWriter.buf[#FileWriter.buf + 1] = str
	FileWriter.size = FileWriter.size + #str
	if FileWriter.mode == "stream" and FileWriter.size > 262144 then
		FileWriter.flush()
	end
end

function FileWriter.close()
	if FileWriter.mode == "stream" then
		FileWriter.flush()
	else
		Compat.caps.writefile(FileWriter.path, table.concat(FileWriter.buf))
		FileWriter.buf = {}
	end
end

function FileWriter.abort()
	FileWriter.buf, FileWriter.size = {}, 0
	if FileWriter.path and Compat.caps.delfile then
		pcall(Compat.caps.delfile, FileWriter.path)
	end
end

--------------------------------------------------------------------------------
-- UI CONTROLLER
--------------------------------------------------------------------------------
local UI = {}
local COLORS = {
	bg = Color3.fromRGB(30, 31, 38), title = Color3.fromRGB(22, 23, 29), panel = Color3.fromRGB(40, 42, 51),
	text = Color3.fromRGB(235, 236, 240), sub = Color3.fromRGB(160, 164, 176),
	accent = Color3.fromRGB(0, 120, 215), danger = Color3.fromRGB(196, 62, 62),
	ok = Color3.fromRGB(46, 160, 90), neutral = Color3.fromRGB(62, 65, 78),
}

local function new(class, props, parent)
	local o = Instance.new(class)
	for k, v in pairs(props) do o[k] = v end
	o.Parent = parent
	return o
end

local function makeButton(text, x, y, w, h, color, parent)
	local b = new("TextButton", {
		Text = text, Size = UDim2.fromOffset(w, h), Position = UDim2.fromOffset(x, y),
		BackgroundColor3 = color, TextColor3 = COLORS.text, Font = Enum.Font.GothamMedium,
		TextSize = 13, BorderSizePixel = 0, AutoButtonColor = true,
	}, parent)
	new("UICorner", { CornerRadius = UDim.new(0, 6) }, b)
	return b
end

function UI.build(handlers)
	local parentGui
	local okp, p = pcall(function()
		return Compat.caps.gethui and Compat.caps.gethui() or game:GetService("CoreGui")
	end)
	if okp and p then
		parentGui = p
	else
		parentGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	end

	local gui = new("ScreenGui", {
		Name = "SaveInstanceExporter", ResetOnSpawn = false, DisplayOrder = 1000,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	}, parentGui)

	local win = new("Frame", {
		Size = UDim2.fromOffset(420, 552), Position = UDim2.new(0.5, -210, 0.5, -276),
		BackgroundColor3 = COLORS.bg, BorderSizePixel = 0, ClipsDescendants = true, Active = true,
	}, gui)
	new("UICorner", { CornerRadius = UDim.new(0, 8) }, win)

	local title = new("Frame", { Size = UDim2.new(1, 0, 0, 32), BackgroundColor3 = COLORS.title, BorderSizePixel = 0 }, win)
	new("TextLabel", {
		Text = "SaveInstance Exporter", Size = UDim2.new(1, -80, 1, 0), Position = UDim2.fromOffset(12, 0),
		BackgroundTransparency = 1, TextColor3 = COLORS.text, Font = Enum.Font.GothamBold, TextSize = 14,
		TextXAlignment = Enum.TextXAlignment.Left,
	}, title)
	local minBtn = makeButton("-", 352, 4, 28, 24, COLORS.neutral, title)
	local closeBtn = makeButton("X", 384, 4, 28, 24, COLORS.danger, title)

	local content = new("Frame", {
		Size = UDim2.new(1, 0, 1, -32), Position = UDim2.fromOffset(0, 32), BackgroundTransparency = 1,
	}, win)

	new("TextLabel", {
		Text = "Services", Size = UDim2.fromOffset(200, 18), Position = UDim2.fromOffset(8, 6),
		BackgroundTransparency = 1, TextColor3 = COLORS.sub, Font = Enum.Font.GothamMedium, TextSize = 12,
		TextXAlignment = Enum.TextXAlignment.Left,
	}, content)

	local list = new("ScrollingFrame", {
		Size = UDim2.fromOffset(404, 190), Position = UDim2.fromOffset(8, 26), BackgroundColor3 = COLORS.panel,
		BorderSizePixel = 0, ScrollBarThickness = 4, CanvasSize = UDim2.new(0, 0, 0, 0),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
	}, content)
	new("UICorner", { CornerRadius = UDim.new(0, 6) }, list)
	new("UIListLayout", { Padding = UDim.new(0, 2), SortOrder = Enum.SortOrder.LayoutOrder }, list)
	new("UIPadding", { PaddingTop = UDim.new(0, 4), PaddingLeft = UDim.new(0, 4), PaddingRight = UDim.new(0, 4) }, list)

	local selected, rows = {}, {}
	local function paintRow(name)
		local r = rows[name]
		r.Text = (selected[name] and "[x]  " or "[  ]  ") .. name
		r.TextColor3 = selected[name] and COLORS.text or COLORS.sub
	end
	for i, name in ipairs(ServiceManager.names) do
		selected[name] = true
		local r = new("TextButton", {
			Size = UDim2.new(1, -4, 0, 28), BackgroundColor3 = COLORS.bg, BorderSizePixel = 0, LayoutOrder = i,
			Font = Enum.Font.Gotham, TextSize = 13, TextXAlignment = Enum.TextXAlignment.Left, Text = "",
			AutoButtonColor = true,
		}, list)
		new("UICorner", { CornerRadius = UDim.new(0, 4) }, r)
		new("UIPadding", { PaddingLeft = UDim.new(0, 10) }, r)
		rows[name] = r
		paintRow(name)
		r.MouseButton1Click:Connect(function()
			if State.running then return end
			selected[name] = not selected[name]
			paintRow(name)
		end)
	end

	local selAll = makeButton("Select All", 8, 224, 199, 28, COLORS.neutral, content)
	local deselAll = makeButton("Deselect All", 213, 224, 199, 28, COLORS.neutral, content)
	local startBtn = makeButton("Start Export", 8, 260, 199, 32, COLORS.accent, content)
	local cancelBtn = makeButton("Cancel Export", 213, 260, 199, 32, COLORS.danger, content)
	cancelBtn.Active = false
	cancelBtn.BackgroundTransparency = 0.5

	local barBg = new("Frame", { Size = UDim2.fromOffset(404, 20), Position = UDim2.fromOffset(8, 304), BackgroundColor3 = COLORS.panel, BorderSizePixel = 0 }, content)
	new("UICorner", { CornerRadius = UDim.new(0, 6) }, barBg)
	local fill = new("Frame", { Size = UDim2.new(0, 0, 1, 0), BackgroundColor3 = COLORS.accent, BorderSizePixel = 0 }, barBg)
	new("UICorner", { CornerRadius = UDim.new(0, 6) }, fill)
	local pctLabel = new("TextLabel", {
		Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1, Text = "0%", TextColor3 = COLORS.text,
		Font = Enum.Font.GothamBold, TextSize = 12, ZIndex = 2,
	}, barBg)

	local stats = new("TextLabel", {
		Size = UDim2.fromOffset(404, 52), Position = UDim2.fromOffset(8, 330), BackgroundTransparency = 1,
		TextColor3 = COLORS.text, Font = Enum.Font.Gotham, TextSize = 12, TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top, Text = "Phase: Idle\nTotal: 0 | Processed: 0 | Exported: 0\nFailed: 0 | Skipped: 0",
	}, content)
	local status = new("TextLabel", {
		Size = UDim2.fromOffset(404, 34), Position = UDim2.fromOffset(8, 388), BackgroundTransparency = 1,
		TextColor3 = COLORS.sub, Font = Enum.Font.Gotham, TextSize = 12, TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top, TextWrapped = true, Text = "Ready",
	}, content)
	local notice = new("TextLabel", {
		Size = UDim2.fromOffset(404, 82), Position = UDim2.fromOffset(8, 428), BackgroundColor3 = COLORS.panel,
		TextColor3 = COLORS.sub, Font = Enum.Font.Gotham, TextSize = 12, TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, BorderSizePixel = 0,
		Text = "Compat: " .. Compat.report(),
	}, content)
	new("UICorner", { CornerRadius = UDim.new(0, 6) }, notice)
	new("UIPadding", { PaddingTop = UDim.new(0, 6), PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8) }, notice)

	-- dragging
	local conns = {}
	local dragging, dragStart, startPos
	conns[#conns + 1] = title.InputBegan:Connect(function(i)
		if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
			dragging, dragStart, startPos = true, i.Position, win.Position
		end
	end)
	conns[#conns + 1] = UserInputService.InputChanged:Connect(function(i)
		if dragging and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
			local d = i.Position - dragStart
			win.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X, startPos.Y.Scale, startPos.Y.Offset + d.Y)
		end
	end)
	conns[#conns + 1] = UserInputService.InputEnded:Connect(function(i)
		if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
			dragging = false
		end
	end)

	local minimized = false
	minBtn.MouseButton1Click:Connect(function()
		minimized = not minimized
		content.Visible = not minimized
		win.Size = minimized and UDim2.fromOffset(420, 32) or UDim2.fromOffset(420, 552)
	end)
	closeBtn.MouseButton1Click:Connect(function()
		State.cancelled = true
		for _, c in ipairs(conns) do c:Disconnect() end
		Progress.onUpdate = nil
		gui:Destroy()
	end)
	selAll.MouseButton1Click:Connect(function()
		if State.running then return end
		for _, n in ipairs(ServiceManager.names) do selected[n] = true paintRow(n) end
	end)
	deselAll.MouseButton1Click:Connect(function()
		if State.running then return end
		for _, n in ipairs(ServiceManager.names) do selected[n] = false paintRow(n) end
	end)
	startBtn.MouseButton1Click:Connect(function()
		if State.running then return end
		local chosen = {}
		for _, n in ipairs(ServiceManager.names) do
			if selected[n] then chosen[#chosen + 1] = n end
		end
		handlers.start(chosen)
	end)
	cancelBtn.MouseButton1Click:Connect(function()
		if State.running then handlers.cancel() end
	end)

	local api = {}
	function api.update(s)
		local pct = Progress.percent()
		fill.Size = UDim2.new(pct / 100, 0, 1, 0)
		pctLabel.Text = pct .. "%"
		stats.Text = string.format("Phase: %s\nTotal: %d | Processed: %d | Exported: %d\nFailed: %d | Skipped: %d",
			s.phase, s.total, s.processed, s.exported, s.failed, s.skipped)
		status.Text = s.status
	end
	function api.setRunning(r)
		startBtn.Active = not r
		startBtn.BackgroundTransparency = r and 0.5 or 0
		cancelBtn.Active = r
		cancelBtn.BackgroundTransparency = r and 0 or 0.5
	end
	function api.notify(kind, msg)
		notice.Text = msg
		notice.TextColor3 = COLORS.text
		notice.BackgroundColor3 = kind == "error" and COLORS.danger or (kind == "ok" and COLORS.ok or COLORS.panel)
	end
	return api
end

--------------------------------------------------------------------------------
-- CONTROLLER
--------------------------------------------------------------------------------
local Controller = {}
local ui

local XML_HEADER = '<roblox xmlns:xmime="http://www.w3.org/2005/05/xmlmime" '
	.. 'xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" '
	.. 'xsi:noNamespaceSchemaLocation="http://www.roblox.com/roblox.xsd" version="4">\n'
	.. '<Meta name="ExplicitAutoJoints">true</Meta>\n'

local function finish(kind, msg)
	State.running = false
	Progress.emit()
	if ui then
		ui.setRunning(false)
		ui.notify(kind, msg)
	end
end

local function runExport(serviceNames)
	if not Compat.caps.writefile then
		finish("error", "Export impossible: writefile is not available in this executor.\n" .. Compat.report())
		return
	end
	if #serviceNames == 0 then
		finish("error", "No service selected.")
		return
	end

	Errors.reset()
	TerrainExporter.reset()
	Progress.reset()
	Progress.state.phase = "Scan"

	local scan = Scanner.scan(serviceNames)
	if not scan then
		finish("error", "Cancelled during scan. No file written.")
		return
	end
	if #scan.roots == 0 then
		finish("error", "None of the selected services could be accessed.")
		return
	end

	-- export phase counters
	local s = Progress.state
	s.phase = "Export"
	s.total = scan.scanned + scan.chunks
	s.processed = scan.excluded
	s.skipped = scan.excluded
	s.exported, s.failed = 0, 0
	Progress.emit()

	FileWriter.open(CONFIG.OutputFile)
	FileWriter.add(XML_HEADER)
	local completed = Serializer.run(scan.roots, FileWriter)
	if not completed then
		FileWriter.abort()
		finish("error", "Export cancelled. Partial file removed (if delfile exists).")
		return
	end
	FileWriter.add("</roblox>")

	s.phase = "Write"
	s.status = "Writing file"
	Progress.emit()
	FileWriter.close()

	pcall(Compat.caps.writefile, CONFIG.ReportFile, Errors.format() .. "\n\n" .. (TerrainExporter.result or "Terrain: not selected"))

	s.done = true
	s.status = "Done"
	local msg = string.format("Export complete: %d exported, %d failed, %d skipped.\nFile: %s (executor workspace folder)\nReport: %s",
		s.exported, s.failed, s.skipped, CONFIG.OutputFile, CONFIG.ReportFile)
	if TerrainExporter.result then msg = msg .. "\n" .. TerrainExporter.result end
	finish((s.failed > 0) and "error" or "ok", msg)
end

function Controller.start(serviceNames)
	if State.running then return end
	State.running, State.cancelled = true, false
	if ui then
		ui.setRunning(true)
		ui.notify("info", "Export started...")
	end
	task.spawn(function()
		local ok, err = pcall(runExport, serviceNames)
		if not ok then
			FileWriter.abort()
			finish("error", "Fatal error: " .. tostring(err))
		end
	end)
end

function Controller.cancel()
	State.cancelled = true
	Progress.state.status = "Cancelling..."
	Progress.emit()
end

Progress.reset()
ui = UI.build({ start = Controller.start, cancel = Controller.cancel })
Progress.onUpdate = ui.update
ui.update(Progress.state)

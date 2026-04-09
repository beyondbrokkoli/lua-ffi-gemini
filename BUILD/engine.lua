local ffi = require("ffi")
local json = require("dkjson")
local Factory = require("sys_factory")
local Engine = {
manifest = {},
terminal = { open = false, scroll = 0, lines = {} }
}
local minX, minY, minZ = 1e30, 1e30, 1e30
local maxX, maxY, maxZ = -1e30, -1e30, -1e30
local function Topology_Cylinder(id)
local SLIDES_PER_RING = 16
local yaw = (id % SLIDES_PER_RING) * (math.pi / 8)
local row = math.floor(id / SLIDES_PER_RING)
local RADIUS = 7500
local ROW_HEIGHT = 2000
local y = row * ROW_HEIGHT
local x = math.sin(yaw) * RADIUS
local z = math.cos(yaw) * RADIUS
return x, y, z, yaw, 0
end
local ActiveTopology = Topology_Cylinder
local function BuildSlideMesh(x, y, z, w, h, thickness, color)
local id = Factory.CreateTriObject(x, y, z, 8, 12, 2000, false, false)
local vStart = Obj_VertStart[id]
local tStart = Obj_TriStart[id]
local hw, hh, ht = w * 0.5, h * 0.5, thickness * 0.5
local verts = {
{-hw, -hh, -ht}, {hw, -hh, -ht}, {hw, hh, -ht}, {-hw, hh, -ht},
{-hw, -hh,  ht}, {hw, -hh,  ht}, {hw, hh,  ht}, {-hw, hh,  ht}
}
for i = 1, 8 do
Vert_LX[vStart + (i - 1)] = verts[i][1]
Vert_LY[vStart + (i - 1)] = verts[i][2]
Vert_LZ[vStart + (i - 1)] = verts[i][3]
end
local indices = {
0,2,1,  0,3,2,  4,5,6,  4,6,7,  0,1,5,  0,5,4,
1,2,6,  1,6,5,  2,3,7,  2,7,6,  3,0,4,  3,4,7
}
for i = 1, #indices, 3 do
local tIdx = tStart + math.floor((i - 1) / 3)
Tri_V1[tIdx] = indices[i] + vStart
Tri_V2[tIdx] = indices[i+1] + vStart
Tri_V3[tIdx] = indices[i+2] + vStart
Tri_Color[tIdx] = color
end
return id
end
local function ProcessSlideNode(id, data)
local w = data.w or 1600
local h = data.h or 900
local thickness = data.thickness or 40
local color = data.color or 0xFFFFFFFF
local hw, hh, ht = w * 0.5, h * 0.5, thickness * 0.5
local px, py, pz = data.x, data.y, data.z
minX, maxX = math.min(minX, px - hw), math.max(maxX, px + hw)
minY, maxY = math.min(minY, py - hh), math.max(maxY, py + hh)
minZ, maxZ = math.min(minZ, pz - ht), math.max(maxZ, pz + ht)
local yaw = data.yaw or 0
local pitch = math.max(-1.56, math.min(1.56, data.pitch or 0))
local cy, sy = math.cos(yaw), math.sin(yaw)
local cp, sp = math.cos(pitch), math.sin(pitch)
local fwx, fwy, fwz = sy * cp, sp, cy * cp
local rtx, rty, rtz = cy, 0, -sy
local upx = fwy * rtz
local upy = fwz * rtx - fwx * rtz
local upz = -fwy * rtx
Box_X[id], Box_Y[id], Box_Z[id] = px, py, pz
Box_HW[id], Box_HH[id], Box_HT[id] = hw, hh, ht
Box_CosA[id], Box_SinA[id] = cy, sy
Box_NX[id], Box_NY[id], Box_NZ[id] = fwx, fwy, fwz
Box_FWX[id], Box_FWY[id], Box_FWZ[id] = fwx, fwy, fwz
Box_RTX[id], Box_RTY[id], Box_RTZ[id] = rtx, 0, rtz
Box_UPX[id], Box_UPY[id], Box_UPZ[id] = upx, upy, upz
local halfDiag = math.sqrt(hw^2 + hh^2 + ht^2)
Sphere_X[id], Sphere_Y[id], Sphere_Z[id] = px, py, pz
Sphere_RSq[id] = (halfDiag + 100)^2
local mId = BuildSlideMesh(px, py, pz, w, h, thickness, color)
print(string.format("[AUDIT-INFO]: Mesh Spawner created Object %d for Slide %d", mId, id))
Obj_X[mId], Obj_Y[mId], Obj_Z[mId] = px, py, pz
Obj_Yaw[mId], Obj_Pitch[mId] = yaw, pitch
Obj_FWX[mId], Obj_FWY[mId], Obj_FWZ[mId] = fwx, fwy, fwz
Obj_RTX[mId], Obj_RTY[mId], Obj_RTZ[mId] = rtx, rty, rtz
Obj_UPX[mId], Obj_UPY[mId], Obj_UPZ[mId] = upx, upy, upz
end
function Engine.Boot(json_path)
print("[AUDIT-INFO]: Booting Engine. Reading " .. json_path)
local content = love.filesystem.read(json_path)
if not content then
print("[AUDIT-FATAL]: Could not find " .. json_path .. " in virtual filesystem!")
return nil
end
local data, pos, err = json.decode(content)
if err or type(data) ~= "table" then
print("[AUDIT-FATAL]: JSON Parse Error or invalid structure: " .. tostring(err))
return nil
end
local keys = {}
for k in pairs(data) do table.insert(keys, k) end
table.sort(keys, function(a, b) return tonumber(a) < tonumber(b) end)
local count = 0
local textPayload = {}
for i, original_key in ipairs(keys) do
local id = i - 1
local node = data[original_key]
local px, py, pz, pyaw, ppitch = ActiveTopology(id)
node.x, node.y, node.z = px, py, pz
node.yaw, node.pitch = pyaw, ppitch
ProcessSlideNode(id, node)
textPayload[id] = {
title = node.text,
content = node.content
}
count = count + 1
end
print(string.format("[AUDIT-INFO]: Assembly Line Complete. %d Slides Built.", count))
return {
textPayload = textPayload,
NumSlides = count,
bounds = {
minX = minX - 8000, minY = minY - 8000, minZ = minZ - 8000,
maxX = maxX + 8000, maxY = maxY + 8000, maxZ = maxZ + 8000
}
}
end
return Engine

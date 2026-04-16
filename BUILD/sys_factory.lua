local ffi = require("ffi")
local bit = require("bit")
local pi, cos, sin, floor = math.pi, math.cos, math.sin, math.floor
local sqrt = math.sqrt
local Factory = {}
function Factory.CreateTriObject(x, y, z, vCount, tCount, radius, isKinematic, hasCollision, isAutonomous)
local id = NumObjects
NumObjects = NumObjects + 1
Obj_X[id], Obj_Y[id], Obj_Z[id] = x, y, z
Obj_Yaw[id], Obj_Pitch[id] = 0, 0
Obj_Radius[id] = radius or 50
Obj_FWX[id], Obj_FWY[id], Obj_FWZ[id] = 0, 0, 1
Obj_RTX[id], Obj_RTY[id], Obj_RTZ[id] = 1, 0, 0
Obj_UPX[id], Obj_UPY[id], Obj_UPZ[id] = 0, 1, 0
Obj_VertStart[id] = NumTotalVerts
Obj_VertCount[id] = vCount
Obj_TriStart[id] = NumTotalTris
Obj_TriCount[id] = tCount
NumTotalVerts = NumTotalVerts + vCount
NumTotalTris = NumTotalTris + tCount
if isKinematic then
if isAutonomous then
Pool_Autonomous[Pool_Autonomous_Count] = id
Pool_Autonomous_Count = Pool_Autonomous_Count + 1
else
Pool_Kinematic[Pool_Kinematic_Count] = id
Pool_Kinematic_Count = Pool_Kinematic_Count + 1
end
end
if hasCollision then
Pool_Collider[Pool_Collider_Count] = id
Pool_Collider_Count = Pool_Collider_Count + 1
end
Pool_Solid[Pool_Solid_Count] = id
Pool_Solid_Count = Pool_Solid_Count + 1
return id
end
function Factory.CreateSlideMesh(x, y, z, w, h, thickness, color)
local maxDiagonal = sqrt((w/2)^2 + (h/2)^2 + (thickness/2)^2)
local id = Factory.CreateTriObject(x, y, z, 8, 12, maxDiagonal, false, false, false)
local vStart, tStart = Obj_VertStart[id], Obj_TriStart[id]
local hw, hh, ht = w/2, h/2, thickness/2
local verts = {
{-hw, -hh, -ht}, {hw, -hh, -ht}, {hw, hh, -ht}, {-hw, hh, -ht},
{-hw, -hh,  ht}, {hw, -hh,  ht}, {hw, hh,  ht}, {-hw, hh,  ht}
}
for i, v in ipairs(verts) do
local vIdx = vStart + (i - 1)
Vert_LX[vIdx], Vert_LY[vIdx], Vert_LZ[vIdx] = v[1], v[2], v[3]
end
local indices = {
0,2,1, 0,3,2, 4,5,6, 4,6,7, 0,1,5, 0,5,4,
1,2,6, 1,6,5, 2,3,7, 2,7,6, 3,0,4, 3,4,7
}
for i = 1, #indices, 3 do
local tIdx = tStart + math.floor((i-1)/3)
Tri_V1[tIdx], Tri_V2[tIdx], Tri_V3[tIdx] = indices[i] + vStart, indices[i+1] + vStart, indices[i+2] + vStart
Tri_Color[tIdx] = color
end
return id
end
function Factory.CreatePropCube(x, y, z, size, color, isKinematic, hasCollision, isAutonomous)
local maxDiagonal = sqrt(3 * (size/2)^2)
local id = Factory.CreateTriObject(x, y, z, 8, 12, maxDiagonal, isKinematic, hasCollision, isAutonomous)
local vStart, tStart = Obj_VertStart[id], Obj_TriStart[id]
local hs = size / 2
local verts = {
{-hs, -hs, -hs}, {hs, -hs, -hs}, {hs, hs, -hs}, {-hs, hs, -hs},
{-hs, -hs,  hs}, {hs, -hs,  hs}, {hs, hs,  hs}, {-hs, hs,  hs}
}
for i, v in ipairs(verts) do
local vIdx = vStart + (i - 1)
Vert_LX[vIdx], Vert_LY[vIdx], Vert_LZ[vIdx] = v[1], v[2], v[3]
end
local indices = {
0,2,1, 0,3,2, 4,5,6, 4,6,7, 0,1,5, 0,5,4,
1,2,6, 1,6,5, 2,3,7, 2,7,6, 3,0,4, 3,4,7
}
for i = 1, #indices, 3 do
local tIdx = tStart + floor((i-1)/3)
Tri_V1[tIdx], Tri_V2[tIdx], Tri_V3[tIdx] = indices[i] + vStart, indices[i+1] + vStart, indices[i+2] + vStart
Tri_Color[tIdx] = color
end
return id
end
function Factory.CreatePropPyramid(x, y, z, size, color, isKinematic, hasCollision, isAutonomous)
local maxDiagonal = sqrt(size^2 + size^2 + size^2)
local id = Factory.CreateTriObject(x, y, z, 5, 6, maxDiagonal, isKinematic, hasCollision, isAutonomous)
local vStart, tStart = Obj_VertStart[id], Obj_TriStart[id]
local verts = {
{0, size, 0}, {-size, -size, -size}, {size, -size, -size},
{size, -size, size}, {-size, -size, size}
}
for i, v in ipairs(verts) do
local vIdx = vStart + (i - 1)
Vert_LX[vIdx], Vert_LY[vIdx], Vert_LZ[vIdx] = v[1], v[2], v[3]
end
local indices = { 0,1,2, 0,2,3, 0,3,4, 0,4,1, 1,4,3, 1,3,2 }
for i = 1, #indices, 3 do
local tIdx = tStart + floor((i-1)/3)
Tri_V1[tIdx], Tri_V2[tIdx], Tri_V3[tIdx] = vStart + indices[i], vStart + indices[i+1], vStart + indices[i+2]
Tri_Color[tIdx] = color
end
return id
end
function Factory.CreateDataSpike(x, y, z, height, color, isKinematic, hasCollision, isAutonomous)
local w = height * 0.3
local maxDiagonal = sqrt(w^2 + height^2)
local id = Factory.CreateTriObject(x, y, z, 6, 8, maxDiagonal, isKinematic, hasCollision, isAutonomous)
local vStart, tStart = Obj_VertStart[id], Obj_TriStart[id]
local verts = {
{0, height, 0}, {0, -height, 0},
{w, 0, w}, {w, 0, -w}, {-w, 0, -w}, {-w, 0, w}
}
for j, v in ipairs(verts) do
local vIdx = vStart + (j - 1)
Vert_LX[vIdx], Vert_LY[vIdx], Vert_LZ[vIdx] = v[1], v[2], v[3]
end
local indices = { 0,2,3, 0,3,4, 0,4,5, 0,5,2, 1,3,2, 1,4,3, 1,5,4, 1,2,5 }
for j = 1, #indices, 3 do
local tIdx = tStart + floor((j-1)/3)
Tri_V1[tIdx], Tri_V2[tIdx], Tri_V3[tIdx] = indices[j] + vStart, indices[j+1] + vStart, indices[j+2] + vStart
Tri_Color[tIdx] = color
end
return id
end
function Factory.CreateTorus(cx, cy, cz, mainRadius, tubeRadius, segments, sides, baseColor, isKinematic, hasCollision, isAutonomous)
local vCount = segments * sides
local tCount = segments * sides * 2
local bound = mainRadius + tubeRadius
local id = Factory.CreateTriObject(cx, cy, cz, vCount, tCount, bound, isKinematic, hasCollision, isAutonomous)
local vStart, tStart = Obj_VertStart[id], Obj_TriStart[id]
local r, g, b = bit.band(bit.rshift(baseColor, 16), 0xFF), bit.band(bit.rshift(baseColor, 8), 0xFF), bit.band(baseColor, 0xFF)
local altColor = bit.bor(0xFF000000, bit.lshift(floor(r * 0.6), 16), bit.lshift(floor(g * 0.6), 8), floor(b * 0.6))
local vIdx = vStart
for i = 0, segments - 1 do
local th = (i / segments) * pi * 2
for j = 0, sides - 1 do
local ph = (j / sides) * pi * 2
Vert_LX[vIdx] = (mainRadius + tubeRadius * cos(ph)) * cos(th)
Vert_LY[vIdx] = tubeRadius * sin(ph)
Vert_LZ[vIdx] = (mainRadius + tubeRadius * cos(ph)) * sin(th)
vIdx = vIdx + 1
end
end
local tIdx = tStart
for i = 0, segments - 1 do
local i_next = (i + 1) % segments
for j = 0, sides - 1 do
local j_next = (j + 1) % sides
local a, b_idx = (i * sides + j) + vStart, (i_next * sides + j) + vStart
local c, d = (i_next * sides + j_next) + vStart, (i * sides + j_next) + vStart
local col = (i + j) % 2 == 0 and baseColor or altColor
Tri_V1[tIdx], Tri_V2[tIdx], Tri_V3[tIdx] = a, c, b_idx
Tri_Color[tIdx] = col; tIdx = tIdx + 1
Tri_V1[tIdx], Tri_V2[tIdx], Tri_V3[tIdx] = a, d, c
Tri_Color[tIdx] = col; tIdx = tIdx + 1
end
end
return id
end
function Factory.CreateTerminalSlide(x, y, z, w, h, thickness, color)
local maxDiagonal = sqrt((w/2)^2 + (h/2)^2 + (thickness/2)^2)
local id = NumObjects
NumObjects = NumObjects + 1
Obj_X[id], Obj_Y[id], Obj_Z[id] = x, y, z
Obj_Yaw[id], Obj_Pitch[id] = 0, 0
Obj_Radius[id] = maxDiagonal
Obj_FWX[id], Obj_FWY[id], Obj_FWZ[id] = 0, 0, 1
Obj_RTX[id], Obj_RTY[id], Obj_RTZ[id] = 1, 0, 0
Obj_UPX[id], Obj_UPY[id], Obj_UPZ[id] = 0, 1, 0
Obj_VertStart[id] = NumTotalVerts
Obj_VertCount[id] = 8
Obj_TriStart[id] = NumTotalTris
Obj_TriCount[id] = 12
NumTotalVerts = NumTotalVerts + 8
NumTotalTris = NumTotalTris + 12
local vStart, tStart = Obj_VertStart[id], Obj_TriStart[id]
local hw, hh, ht = w/2, h/2, thickness/2
local verts = {
{-hw, -hh, -ht}, {hw, -hh, -ht}, {hw, hh, -ht}, {-hw, hh, -ht},
{-hw, -hh, ht}, {hw, -hh, ht}, {hw, hh, ht}, {-hw, hh, ht}
}
for i, v in ipairs(verts) do
local vIdx = vStart + (i - 1)
Vert_LX[vIdx], Vert_LY[vIdx], Vert_LZ[vIdx] = v[1], v[2], v[3]
end
local indices = {
0,2,1, 0,3,2, 4,5,6, 4,6,7, 0,1,5, 0,5,4,
1,2,6, 1,6,5, 2,3,7, 2,7,6, 3,0,4, 3,4,7
}
for i = 1, #indices, 3 do
local tIdx = tStart + math.floor((i-1)/3)
Tri_V1[tIdx], Tri_V2[tIdx], Tri_V3[tIdx] = indices[i] + vStart, indices[i+1] + vStart, indices[i+2] + vStart
Tri_Color[tIdx] = color
end
return id
end
return Factory

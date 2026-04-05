local ffi = require("ffi")
local bit = require("bit")
local pi, cos, sin, floor = math.pi, math.cos, math.sin, math.floor

local Factory = {}

function Factory.CreateTriObject(x, y, z, vCount, tCount, radius, isKinematic, hasCollision)
    local id = NumObjects
    NumObjects = NumObjects + 1
    Obj_X[id], Obj_Y[id], Obj_Z[id] = x, y, z
    Obj_Yaw[id], Obj_Pitch[id] = 0, 0
    Obj_Radius[id] = radius or 50
    Obj_VertStart[id] = NumTotalVerts
    Obj_VertCount[id] = vCount
    Obj_TriStart[id] = NumTotalTris
    Obj_TriCount[id] = tCount
    NumTotalVerts = NumTotalVerts + vCount
    NumTotalTris = NumTotalTris + tCount

    if isKinematic then
        Pool_Kinematic[Pool_Kinematic_Count] = id
        Pool_Kinematic_Count = Pool_Kinematic_Count + 1
    end
    if hasCollision then
        Pool_Collider[Pool_Collider_Count] = id
        Pool_Collider_Count = Pool_Collider_Count + 1
    end
    Pool_Solid[Pool_Solid_Count] = id
    Pool_Solid_Count = Pool_Solid_Count + 1
    return id
end

function Factory.CreateTorus(cx, cy, cz, mainRadius, tubeRadius, segments, sides, baseColor, hasCollision)
    baseColor = baseColor or 0xFFFFCC44
    local bound = mainRadius + tubeRadius
    local vCount = segments * sides
    local tCount = segments * sides * 2
    local id = Factory.CreateTriObject(cx, cy, cz, vCount, tCount, bound, true, hasCollision)

    local vStart = Obj_VertStart[id]
    local tStart = Obj_TriStart[id]

    local r = bit.band(bit.rshift(baseColor, 16), 0xFF)
    local g = bit.band(bit.rshift(baseColor, 8), 0xFF)
    local b = bit.band(baseColor, 0xFF)
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
            local a = (i * sides + j) + vStart
            local b_idx = (i_next * sides + j) + vStart
            local c = (i_next * sides + j_next) + vStart
            local d = (i * sides + j_next) + vStart
            local useAlt = (i + j) % 2 == 0
            local col = useAlt and baseColor or altColor
            Tri_V1[tIdx], Tri_V2[tIdx], Tri_V3[tIdx] = a, c, b_idx
            Tri_Color[tIdx] = col
            tIdx = tIdx + 1
            Tri_V1[tIdx], Tri_V2[tIdx], Tri_V3[tIdx] = a, d, c
            Tri_Color[tIdx] = col
            tIdx = tIdx + 1
        end
    end
    return id
end

return Factory

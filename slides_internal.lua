local SlidesInternal = {}
function SlidesInternal.BuildSlideMesh(api, id_tag, config) local w, h = config.w or 1600, config.h or 900
    local thickness = config.thickness or 40
    local color = config.color or 0xFFFFFFFF
    local id = api.CreateTriObject(config.x, config.y, config.z, 8, 12, 2000, false, false)
    local vStart = api.Obj_VertStart[id]
    local tStart = api.Obj_TriStart[id]
    local hw, hh, ht = w/2, h/2, thickness/2
    local verts = { {-hw, -hh, -ht}, {hw, -hh, -ht}, {hw, hh, -ht}, {-hw, hh, -ht}, {-hw, -hh, ht}, {hw, -hh, ht}, {hw, hh, ht}, {-hw, hh, ht} }
    for i, v in ipairs(verts) do local vIdx = vStart + (i - 1)
        api.Vert_LX[vIdx], api.Vert_LY[vIdx], api.Vert_LZ[vIdx] = v[1], v[2], v[3]
    end
    local indices = { 0,2,1, 0,3,2, 4,5,6, 4,6,7, 0,1,5, 0,5,4, 1,2,6, 1,6,5, 2,3,7, 2,7,6, 3,0,4, 3,4,7 }
    for i = 1, #indices, 3 do local tIdx = tStart + math.floor((i-1)/3)
        api.Tri_V1[tIdx] = indices[i] + vStart
        api.Tri_V2[tIdx] = indices[i+1] + vStart
        api.Tri_V3[tIdx] = indices[i+2] + vStart
        api.Tri_Color[tIdx] = color
    end
    return id
end
function SlidesInternal.CrystalCompanion(api, numSlides, crystalsPerSlide) local colors = {0xFFFFCC44, 0xFF44CCFF, 0xFFCC44FF, 0xFFFFFFFF}
    for i = 0, numSlides - 1 do local sx = api.Sphere_X[i]
        local sy = api.Sphere_Y[i]
        local sz = api.Sphere_Z[i]
        local radius = math.sqrt(api.Sphere_RSq[i])
        for j = 1, crystalsPerSlide do local phi = math.random() * math.pi * 2
            local costheta = (math.random() * 2) - 1
            local theta = math.acos(costheta)
            local r = (radius * 0.4) + (math.random() * radius * 0.5)
            local lx = r * math.sin(theta) * math.cos(phi)
            local ly = r * math.sin(theta) * math.sin(phi)
            local lz = r * math.cos(theta)
            local tId = api.CreateTorus(sx + lx, sy + ly, sz + lz, 20, 8, 8, 3, colors[math.random(#colors)], true)
            api.Obj_HomeIdx[tId] = i
            api.Obj_VelX[tId] = (math.random() - 0.5) * 40
            api.Obj_VelY[tId] = (math.random() - 0.5) * 40
            api.Obj_VelZ[tId] = (math.random() - 0.5) * 40
            api.Obj_RotSpeedYaw[tId] = (math.random() - 0.5) * 3
            api.Obj_RotSpeedPitch[tId] = (math.random() - 0.5) * 3
            api.Obj_Yaw[tId] = math.random() * math.pi * 2
            api.Obj_Pitch[tId] = math.random() * math.pi * 2
        end end end
function SlidesInternal.SpawnHeroDonut(api, homeSlideIdx)
    local sx = api.Sphere_X[homeSlideIdx]
    local sy = api.Sphere_Y[homeSlideIdx]
    local sz = api.Sphere_Z[homeSlideIdx]

    -- A highly detailed (64x32), thick, smaller donut.
    -- Color: 0xFF444444 (The Crystal Blue)
    -- The last argument is 'true': It gets a Hitbox!
    local tId = api.CreateTorus(sx, sy, sz, 45, 20, 64, 32, 0xFFFF99CC, true)

    api.Obj_HomeIdx[tId] = homeSlideIdx
    
    -- Give it some aggressive starting velocity
    api.Obj_VelX[tId] = 120
    api.Obj_VelY[tId] = 80
    api.Obj_VelZ[tId] = 150
    
    -- Give it a fast, mesmerizing spin
    api.Obj_RotSpeedYaw[tId] = 2.5
    api.Obj_RotSpeedPitch[tId] = 1.8
end

function SlidesInternal.SpawnBouncingCube(api, homeIdx)
    local sx = api.Sphere_X[homeIdx]
    local sy = api.Sphere_Y[homeIdx]
    local sz = api.Sphere_Z[homeIdx]
    
    local size = 40
    local color = 0xFFFF3366 -- Neon Pink!

    -- 8 Verts, 12 Tris. isKinematic = true, hasCollision = true
    local id = api.CreateTriObject(sx, sy, sz, 8, 12, size * 1.73, true, true)

    local vStart = api.Obj_VertStart[id]
    local tStart = api.Obj_TriStart[id]
    local hs = size / 2

    local verts = {
        {-hs, -hs, -hs}, {hs, -hs, -hs}, {hs, hs, -hs}, {-hs, hs, -hs},
        {-hs, -hs, hs}, {hs, -hs, hs}, {hs, hs, hs}, {-hs, hs, hs}
    }
    for i, v in ipairs(verts) do
        local vIdx = vStart + (i - 1)
        api.Vert_LX[vIdx], api.Vert_LY[vIdx], api.Vert_LZ[vIdx] = v[1], v[2], v[3]
    end

    local indices = {
        0,2,1, 0,3,2, 4,5,6, 4,6,7, 0,1,5, 0,5,4,
        1,2,6, 1,6,5, 2,3,7, 2,7,6, 3,0,4, 3,4,7
    }
    for i = 1, #indices, 3 do
        local tIdx = tStart + math.floor((i-1)/3)
        api.Tri_V1[tIdx] = indices[i] + vStart
        api.Tri_V2[tIdx] = indices[i+1] + vStart
        api.Tri_V3[tIdx] = indices[i+2] + vStart
        api.Tri_Color[tIdx] = color
    end

    api.Obj_HomeIdx[id] = homeIdx
    
    -- Give it an aggressive initial explosion velocity
    api.Obj_VelX[id] = (math.random() - 0.5) * 250
    api.Obj_VelY[id] = (math.random() - 0.5) * 250
    api.Obj_VelZ[id] = (math.random() - 0.5) * 250
    
    -- Crazy spin
    api.Obj_RotSpeedYaw[id] = (math.random() - 0.5) * 8
    api.Obj_RotSpeedPitch[id] = (math.random() - 0.5) * 8
end
function SlidesInternal.SpawnPyramid(api, homeIdx)
    local sx = api.Sphere_X[homeIdx]
    local sy = api.Sphere_Y[homeIdx]
    local sz = api.Sphere_Z[homeIdx]
    
    local s = 30 + math.random() * 30
    local color = 0xFF33FF99 -- Neon Green

    -- 5 Verts, 6 Tris. isKinematic = true, hasCollision = true
    local id = api.CreateTriObject(sx, sy, sz, 5, 6, s * 1.5, true, true)
    local vStart = api.Obj_VertStart[id]
    local tStart = api.Obj_TriStart[id]

    local verts = {
        {0, s, 0}, {-s, -s, -s}, {s, -s, -s}, {s, -s, s}, {-s, -s, s}
    }
    for i, v in ipairs(verts) do
        local vIdx = vStart + (i - 1)
        api.Vert_LX[vIdx], api.Vert_LY[vIdx], api.Vert_LZ[vIdx] = v[1], v[2], v[3]
    end

    local indices = { 0,1,2, 0,2,3, 0,3,4, 0,4,1,  1,4,3, 1,3,2 }
    for i = 1, #indices, 3 do
        local tIdx = tStart + math.floor((i-1)/3)
        api.Tri_V1[tIdx], api.Tri_V2[tIdx], api.Tri_V3[tIdx] = vStart + indices[i], vStart + indices[i+1], vStart + indices[i+2]
        api.Tri_Color[tIdx] = color
    end

    api.Obj_HomeIdx[id] = homeIdx
    api.Obj_VelX[id] = (math.random() - 0.5) * 300
    api.Obj_VelY[id] = (math.random() - 0.5) * 300
    api.Obj_VelZ[id] = (math.random() - 0.5) * 300
    api.Obj_RotSpeedYaw[id] = (math.random() - 0.5) * 10
    api.Obj_RotSpeedPitch[id] = (math.random() - 0.5) * 10
end

function SlidesInternal.SpawnChaosCluster(api, homeIdx, count)
    for i = 1, count do
        local roll = math.random(1, 3)
        if roll == 1 then 
            SlidesInternal.SpawnBouncingCube(api, homeIdx)
        elseif roll == 2 then 
            SlidesInternal.SpawnPyramid(api, homeIdx)
        else
            -- Spawn a tiny, hyper-fast neon purple donut
            local sx, sy, sz = api.Sphere_X[homeIdx], api.Sphere_Y[homeIdx], api.Sphere_Z[homeIdx]
            local tId = api.CreateTorus(sx, sy, sz, 15, 6, 16, 8, 0xFFFF33FF, true)
            api.Obj_HomeIdx[tId] = homeIdx
            api.Obj_VelX[tId] = (math.random() - 0.5) * 400
            api.Obj_VelY[tId] = (math.random() - 0.5) * 400
            api.Obj_VelZ[tId] = (math.random() - 0.5) * 400
            api.Obj_RotSpeedYaw[tId] = (math.random() - 0.5) * 15
            api.Obj_RotSpeedPitch[tId] = (math.random() - 0.5) * 15
        end
    end
end
function SlidesInternal.SpawnParticleAccelerator(api, homeIdx, count)
    local sx, sy, sz = api.Sphere_X[homeIdx], api.Sphere_Y[homeIdx], api.Sphere_Z[homeIdx]
    local colors = {0xFFFF3366, 0xFF33FF99, 0xFF44CCFF, 0xFFFFFF00}
    
    for i = 1, count do
        local size = 15 + math.random() * 15
        local color = colors[math.random(#colors)]
        
        -- Spawn tiny lightweight cubes
        local id = api.CreateTriObject(sx, sy, sz, 8, 12, size * 1.73, true, true)
        local vStart, tStart = api.Obj_VertStart[id], api.Obj_TriStart[id]
        local hs = size / 2
        local verts = {
            {-hs, -hs, -hs}, {hs, -hs, -hs}, {hs, hs, -hs}, {-hs, hs, -hs},
            {-hs, -hs, hs}, {hs, -hs, hs}, {hs, hs, hs}, {-hs, hs, hs}
        }
        for j, v in ipairs(verts) do
            local vIdx = vStart + (j - 1)
            api.Vert_LX[vIdx], api.Vert_LY[vIdx], api.Vert_LZ[vIdx] = v[1], v[2], v[3]
        end
        local indices = {
            0,2,1, 0,3,2, 4,5,6, 4,6,7, 0,1,5, 0,5,4,
            1,2,6, 1,6,5, 2,3,7, 2,7,6, 3,0,4, 3,4,7
        }
        for j = 1, #indices, 3 do
            local tIdx = tStart + math.floor((j-1)/3)
            api.Tri_V1[tIdx], api.Tri_V2[tIdx], api.Tri_V3[tIdx] = indices[j] + vStart, indices[j+1] + vStart, indices[j+2] + vStart
            api.Tri_Color[tIdx] = color
        end
        api.Obj_HomeIdx[id] = homeIdx
        api.Obj_VelX[id], api.Obj_VelY[id], api.Obj_VelZ[id] = (math.random()-0.5)*1500, (math.random()-0.5)*1500, (math.random()-0.5)*1500
        api.Obj_RotSpeedYaw[id], api.Obj_RotSpeedPitch[id] = (math.random()-0.5)*30, (math.random()-0.5)*30
    end
end
function SlidesInternal.SpawnDeepSpaceAsteroids(api, count)
    local colors = {0xFF444444, 0xFF666666, 0xFF333333, 0xFF888888} -- Space Greys!
    
    for i = 1, count do
        local size = 50 + math.random() * 150
        local color = colors[math.random(#colors)]
        
        -- Distribute them across the entire 9000-unit map length!
        local x = (math.random() - 0.5) * 16000 
        local y = (math.random() - 0.5) * 8000  
        local z = -2000 + math.random() * 17000 
        
        local id = api.CreateTriObject(x, y, z, 8, 12, size * 1.73, true, true)
        local vStart = api.Obj_VertStart[id]
        local tStart = api.Obj_TriStart[id]
        
        -- Randomly warp the XYZ scale so they look like jagged asteroids
        local hx = size * (0.5 + math.random() * 0.5)
        local hy = size * (0.5 + math.random() * 0.5)
        local hz = size * (0.5 + math.random() * 0.5)
        
        local verts = {
            {-hx, -hy, -hz}, {hx, -hy, -hz}, {hx, hy, -hz}, {-hx, hy, -hz},
            {-hx, -hy, hz}, {hx, -hy, hz}, {hx, hy, hz}, {-hx, hy, hz}
        }
        for j, v in ipairs(verts) do
            local vIdx = vStart + (j - 1)
            api.Vert_LX[vIdx], api.Vert_LY[vIdx], api.Vert_LZ[vIdx] = v[1], v[2], v[3]
        end
        
        local indices = {
            0,2,1, 0,3,2, 4,5,6, 4,6,7, 0,1,5, 0,5,4,
            1,2,6, 1,6,5, 2,3,7, 2,7,6, 3,0,4, 3,4,7
        }
        for j = 1, #indices, 3 do
            local tIdx = tStart + math.floor((j-1)/3)
            api.Tri_V1[tIdx] = indices[j] + vStart
            api.Tri_V2[tIdx] = indices[j+1] + vStart
            api.Tri_V3[tIdx] = indices[j+2] + vStart
            api.Tri_Color[tIdx] = color
        end
        
        api.Obj_HomeIdx[id] = -1 -- THE DEEP SPACE FLAG! 
        
        -- Ambient drift
        api.Obj_VelX[id] = (math.random() - 0.5) * 80
        api.Obj_VelY[id] = (math.random() - 0.5) * 80
        api.Obj_VelZ[id] = (math.random() - 0.5) * 80
        api.Obj_RotSpeedYaw[id] = (math.random() - 0.5) * 1.5
        api.Obj_RotSpeedPitch[id] = (math.random() - 0.5) * 1.5
    end
end
function SlidesInternal.SpawnSpaceAsteroids(api, count)
    -- A palette of 5 distinct grey/charcoal shades for the "textured" look
    local colors = {0xFF333333, 0xFF4A4A4A, 0xFF5C5C5C, 0xFF707070, 0xFF858585}
    
    -- The Golden Ratio, used to calculate perfect Icosahedrons
    local phi = (1.0 + math.sqrt(5.0)) / 2.0 

    for i = 1, count do
        local size = 50 + math.random() * 120
        
        -- Distribute across the deep space map
        local x = (math.random() - 0.5) * 16000 
        local y = (math.random() - 0.5) * 8000  
        local z = -2000 + math.random() * 17000 
        
        -- An Icosahedron has 12 Vertices and 20 Triangles
        local id = api.CreateTriObject(x, y, z, 12, 20, size * 2.0, true, true)
        local vStart = api.Obj_VertStart[id]
        local tStart = api.Obj_TriStart[id]
        
        -- Base Icosahedron vertex coordinates
        local base_verts = {
            {-1,  phi,  0}, { 1,  phi,  0}, {-1, -phi,  0}, { 1, -phi,  0},
            { 0, -1,  phi}, { 0,  1,  phi}, { 0, -1, -phi}, { 0,  1, -phi},
            { phi,  0, -1}, { phi,  0,  1}, {-phi,  0, -1}, {-phi,  0,  1}
        }
        
        -- Apply the jagged distortion!
        for j, v in ipairs(base_verts) do
            local vIdx = vStart + (j - 1)
            -- Randomize how far each point is from the center (creates craters/spikes)
            local distortion = size * (0.5 + math.random() * 0.7) 
            api.Vert_LX[vIdx] = v[1] * distortion
            api.Vert_LY[vIdx] = v[2] * distortion
            api.Vert_LZ[vIdx] = v[3] * distortion
        end
        
        -- Map the 20 triangles connecting the vertices
        local indices = {
            0,11,5,  0,5,1,   0,1,7,   0,7,10,  0,10,11,
            1,5,9,   5,11,4,  11,10,2, 10,7,6,  7,1,8,
            3,9,4,   3,4,2,   3,2,6,   3,6,8,   3,8,9,
            4,9,5,   2,4,11,  6,2,10,  8,6,7,   9,8,1
        }
        
        for j = 1, #indices, 3 do
            local tIdx = tStart + math.floor((j-1)/3)
            api.Tri_V1[tIdx] = indices[j] + vStart
            api.Tri_V2[tIdx] = indices[j+1] + vStart
            api.Tri_V3[tIdx] = indices[j+2] + vStart
            
            -- SURGICAL SPICE: Randomize the color PER TRIANGLE!
            -- This simulates complex faceted rock surfaces catching the light.
            api.Tri_Color[tIdx] = colors[math.random(#colors)]
        end
        
        api.Obj_HomeIdx[id] = -1 -- DEEP SPACE FLAG!
        
        -- Smooth ambient tumbling
        api.Obj_VelX[id] = (math.random() - 0.5) * 80
        api.Obj_VelY[id] = (math.random() - 0.5) * 80
        api.Obj_VelZ[id] = (math.random() - 0.5) * 80
        api.Obj_RotSpeedYaw[id] = (math.random() - 0.5) * 1.5
        api.Obj_RotSpeedPitch[id] = (math.random() - 0.5) * 1.5
    end
end
function SlidesInternal.SpawnDataSpikes(api, count)
    local colors = {0xFF00FFFF, 0xFFFF00FF, 0xFF00FF88, 0xFFFFFFFF} -- Cyan, Magenta, Neon Green, White
    
    for i = 1, count do
        local h = 40 + math.random() * 60 -- Height of the spike
        local w = h * 0.3                 -- Width (sharp and narrow)
        
        local x = (math.random() - 0.5) * 16000
        local y = (math.random() - 0.5) * 8000
        local z = -2000 + math.random() * 17000
        
        local id = api.CreateTriObject(x, y, z, 6, 8, h, true, true)
        local vStart = api.Obj_VertStart[id]
        local tStart = api.Obj_TriStart[id]
        
        -- The 6 Vertices of a Bi-pyramid (Octahedron)
        local verts = {
            {0, h, 0},   -- 0: Top Point
            {0, -h, 0},  -- 1: Bottom Point
            {w, 0, w},   -- 2: Equator 1
            {w, 0, -w},  -- 3: Equator 2
            {-w, 0, -w}, -- 4: Equator 3
            {-w, 0, w}   -- 5: Equator 4
        }
        
        for j, v in ipairs(verts) do
            local vIdx = vStart + (j - 1)
            api.Vert_LX[vIdx], api.Vert_LY[vIdx], api.Vert_LZ[vIdx] = v[1], v[2], v[3]
        end
        
        -- The 8 Triangles
        local indices = {
            0,2,3,  0,3,4,  0,4,5,  0,5,2, -- Top half
            1,3,2,  1,4,3,  1,5,4,  1,2,5  -- Bottom half
        }
        
        local color = colors[math.random(#colors)]
        for j = 1, #indices, 3 do
            local tIdx = tStart + math.floor((j-1)/3)
            api.Tri_V1[tIdx] = indices[j] + vStart
            api.Tri_V2[tIdx] = indices[j+1] + vStart
            api.Tri_V3[tIdx] = indices[j+2] + vStart
            api.Tri_Color[tIdx] = color
        end
        
        api.Obj_HomeIdx[id] = -1
        api.Obj_VelX[id] = (math.random() - 0.5) * 150
        api.Obj_VelY[id] = (math.random() - 0.5) * 150
        api.Obj_VelZ[id] = (math.random() - 0.5) * 150
        
        -- Make them spin rapidly like drill bits
        api.Obj_RotSpeedYaw[id] = (math.random() - 0.5) * 5.0
        api.Obj_RotSpeedPitch[id] = (math.random() - 0.5) * 5.0
    end
end
return SlidesInternal

local ffi = require("ffi")
local bit = require("bit")

-- ==========================================
-- 1. FFI DEFINITIONS & LOCALIZATIONS
-- ==========================================
ffi.cdef[[
    typedef struct { float x, y, z; } Vec3;
    typedef struct { Vec3 pos; Vec3 fw, rt, up; float yaw, pitch, fov; } Entity;
    typedef struct { int v1, v2, v3; uint32_t color; } Triangle;
    typedef struct { float x, y, z; bool valid; } ProjectOut;
]]

local floor, ceil, max, min = math.floor, math.ceil, math.max, math.min
local sqrt, cos, sin = math.sqrt, math.cos, math.sin

-- ==========================================
-- 2. GLOBAL STATE & BUFFERS
-- ==========================================
local CANVAS_W, CANVAS_H, HALF_W, HALF_H
local ScreenBuffer, ScreenPtr, ZBuffer, ScreenImage
local Cam = ffi.new("Entity")
local TriObjects = {}

-- NEW: Track whether the mouse is locked to the game
local isMouseCaptured = false

local resizeTimer = 0
local pendingResize = false

local function ReinitBuffers(w, h)
    CANVAS_W, CANVAS_H = w, h
    HALF_W, HALF_H = w * 0.5, h * 0.5

    ScreenBuffer = love.image.newImageData(CANVAS_W, CANVAS_H)
    ScreenImage = love.graphics.newImage(ScreenBuffer)

    ScreenPtr = ffi.cast("uint32_t*", ScreenBuffer:getPointer())
    ZBuffer = ffi.new("float[?]", CANVAS_W * CANVAS_H)

    Cam.fov = (CANVAS_W / 800) * 600
end

-- ==========================================
-- 3. THE PLATINUM TRIANGLE KERNEL
-- ==========================================
function CreateTriObject(x, y, z, vCount, tCount)
    local obj = {
        transform = ffi.new("Entity"),
        verts     = ffi.new("Vec3[?]", vCount),
        tris      = ffi.new("Triangle[?]", tCount),
        vCache    = ffi.new("Vec3[?]", vCount),
        pCache    = ffi.new("ProjectOut[?]", vCount),
        vCount = vCount, tCount = tCount
    }
    obj.transform.pos = {x=x, y=y, z=z}
    table.insert(TriObjects, obj)
    return obj
end

local function UpdateBasis(ent)
    local cy, sy = cos(ent.yaw), sin(ent.yaw)
    local cp, sp = cos(ent.pitch), sin(ent.pitch)
    ent.fw.x, ent.fw.y, ent.fw.z = sy * cp, sp, cy * cp
    ent.rt.x, ent.rt.z = cy, -sy
    ent.up.x = ent.fw.y * ent.rt.z - ent.fw.z * ent.rt.y
    ent.up.y = ent.fw.z * ent.rt.x - ent.fw.x * ent.rt.z
    ent.up.z = ent.fw.x * ent.rt.y - ent.fw.y * ent.rt.x
end

-- ==========================================
-- 4. SCANLINE RASTERIZER (Pointer Edition)
-- ==========================================
local function RasterizeTriangle(p1, p2, p3, shadedColor)
    if p1.y > p2.y then p1, p2 = p2, p1 end
    if p1.y > p3.y then p1, p3 = p3, p1 end
    if p2.y > p3.y then p2, p3 = p3, p2 end

    local h = p3.y - p1.y
    if h < 1 then return end
    local inv_h = 1 / h

    local y_start = max(0, ceil(p1.y))
    local y_end   = min(CANVAS_H - 1, floor(p3.y))

    for y = y_start, y_end do
        local is_upper = y < p2.y
        local segment_h = is_upper and (p2.y - p1.y) or (p3.y - p2.y)
        if segment_h < 1 then segment_h = 1 end

        local t1 = (y - p1.y) * inv_h
        local t2 = (y - (is_upper and p1.y or p2.y)) / segment_h

        local ax, az = p1.x + (p3.x-p1.x)*t1, p1.z + (p3.z-p1.z)*t1
        local bx, bz

        if is_upper then
            bx, bz = p1.x + (p2.x-p1.x)*t2, p1.z + (p2.z-p1.z)*t2
        else
            bx, bz = p2.x + (p3.x-p2.x)*t2, p2.z + (p3.z-p2.z)*t2
        end

        if ax > bx then ax, bx = bx, ax; az, bz = bz, az end

        local row_width = bx - ax
        if row_width > 0 then
            local z_step = (bz - az) / row_width
            local start_x = max(0, ceil(ax))
            local end_x   = min(CANVAS_W - 1, floor(bx))

            local current_z = az + z_step * (start_x - ax)

            local row_idx = y * CANVAS_W
            local z_row = ZBuffer + row_idx
            local s_row = ScreenPtr + row_idx

            for x = start_x, end_x do
                if current_z < z_row[x] then
                    z_row[x] = current_z
                    s_row[x] = shadedColor
                end
                current_z = current_z + z_step
            end
        end
    end
end

-- ==========================================
-- 5. MATH & PROJECTION
-- ==========================================
local function ProjectToScreen(wx, wy, wz, out_p)
    local dx, dy, dz = wx-Cam.pos.x, wy-Cam.pos.y, wz-Cam.pos.z
    local cz = dx*Cam.fw.x + dy*Cam.fw.y + dz*Cam.fw.z
    if cz < 0.1 then
        out_p.valid = false
        return
    end
    local f = Cam.fov / cz
    out_p.x = HALF_W + (dx*Cam.rt.x + dy*Cam.rt.y + dz*Cam.rt.z) * f
    out_p.y = HALF_H + (dx*Cam.up.x + dy*Cam.up.y + dz*Cam.up.z) * f
    out_p.z = cz
    out_p.valid = true
end

-- ==========================================
-- SHAPE GENERATORS
-- ==========================================
local function CreateCube(cx, cy, cz, size)
    local s = size * 0.5
    local cube = CreateTriObject(cx, cy, cz, 8, 12)
    local v, t = cube.verts, cube.tris

    -- 8 Vertices
    v[0] = {x=-s, y=-s, z=-s}; v[1] = {x= s, y=-s, z=-s}
    v[2] = {x= s, y= s, z=-s}; v[3] = {x=-s, y= s, z=-s}
    v[4] = {x=-s, y=-s, z= s}; v[5] = {x= s, y=-s, z= s}
    v[6] = {x= s, y= s, z= s}; v[7] = {x=-s, y= s, z= s}

    -- 12 Triangles (CCW Winding for correct normals)
    local c1, c2, c3 = 0xFFEE4444, 0xFF44EE44, 0xFF4444EE
    local c4, c5, c6 = 0xFFEEEE44, 0xFFEE44EE, 0xFF44EEEE

    -- Front
    t[0] = {v1=0, v2=2, v3=1, color=c1}; t[1] = {v1=0, v2=3, v3=2, color=c1}
    -- Back
    t[2] = {v1=5, v2=7, v3=4, color=c2}; t[3] = {v1=5, v2=6, v3=7, color=c2}
    -- Top
    t[4] = {v1=3, v2=6, v3=2, color=c3}; t[5] = {v1=3, v2=7, v3=6, color=c3}
    -- Bottom
    t[6] = {v1=4, v2=1, v3=5, color=c4}; t[7] = {v1=4, v2=0, v3=1, color=c4}
    -- Right
    t[8] = {v1=1, v2=6, v3=5, color=c5}; t[9] = {v1=1, v2=2, v3=6, color=c5}
    -- Left
    t[10]= {v1=4, v2=3, v3=0, color=c6}; t[11]= {v1=4, v2=7, v3=3, color=c6}

    return cube
end

local function CreateIcosahedron(cx, cy, cz, size)
    local ico = CreateTriObject(cx, cy, cz, 12, 20)
    local v, t = ico.verts, ico.tris
    local phi = (1.0 + math.sqrt(5.0)) / 2.0

    -- 12 Vertices based on orthogonal rectangles
    local verts = {
        {-1,  phi,  0}, { 1,  phi,  0}, {-1, -phi,  0}, { 1, -phi,  0},
        { 0, -1,  phi}, { 0,  1,  phi}, { 0, -1, -phi}, { 0,  1, -phi},
        { phi,  0, -1}, { phi,  0,  1}, {-phi,  0, -1}, {-phi,  0,  1}
    }

    for i=0, 11 do
        v[i] = {x = verts[i+1][1]*size, y = verts[i+1][2]*size, z = verts[i+1][3]*size}
    end

    -- 20 Triangles
    local indices = {
        {0, 11, 5}, {0, 5, 1}, {0, 1, 7}, {0, 7, 10}, {0, 10, 11},
        {1, 5, 9}, {5, 11, 4}, {11, 10, 2}, {10, 7, 6}, {7, 1, 8},
        {3, 9, 4}, {3, 4, 2}, {3, 2, 6}, {3, 6, 8}, {3, 8, 9},
        {4, 9, 5}, {2, 4, 11}, {6, 2, 10}, {8, 6, 7}, {9, 8, 1}
    }

    local c1, c2 = 0xFF00FFCC, 0xFF0088AA
    for i=0, 19 do
        local color = (i % 2 == 0) and c1 or c2
        -- Reverse winding order to match your backface culling
        t[i] = {v1=indices[i+1][1], v2=indices[i+1][3], v3=indices[i+1][2], color=color}
    end

    return ico
end

local function CreateUVSphere(cx, cy, cz, radius, rings, sectors)
    local vCount = (rings + 1) * (sectors + 1)
    local tCount = rings * sectors * 2
    local sph = CreateTriObject(cx, cy, cz, vCount, tCount)

    local vIdx, tIdx = 0, 0

    -- Generate Vertices
    for i = 0, rings do
        local phi = (i / rings) * math.pi
        for j = 0, sectors do
            local theta = (j / sectors) * math.pi * 2
            sph.verts[vIdx] = {
                x = radius * math.sin(phi) * math.cos(theta),
                y = radius * math.cos(phi),
                z = radius * math.sin(phi) * math.sin(theta)
            }
            vIdx = vIdx + 1
        end
    end

    -- Generate Triangles
    local c1, c2 = 0xFFFF5555, 0xFFAA2222
    for i = 0, rings - 1 do
        for j = 0, sectors - 1 do
            local a = i * (sectors + 1) + j
            local b = a + sectors + 1
            local c = a + 1
            local d = b + 1

            local color = ((i+j) % 2 == 0) and c1 or c2

            sph.tris[tIdx] = {v1=a, v2=c, v3=b, color=color}; tIdx = tIdx + 1
            sph.tris[tIdx] = {v1=b, v2=c, v3=d, color=color}; tIdx = tIdx + 1
        end
    end

    return sph
end

-- ==========================================
-- 6. LÖVE CALLBACKS
-- ==========================================
function love.load()
    local startW, startH = love.graphics.getDimensions()
    ReinitBuffers(startW, startH)
    love.window.setMode(CANVAS_W, CANVAS_H, {resizable=true})

    -- Pull camera back a bit to see everything
    Cam.pos = {x=32, y=35, z=-50}

    -- 1. The Classic Torus
    local segs, sides = 32, 16
    local tor = CreateTriObject(0, 35, 0, segs*sides, segs*sides*2)
    local R, r, vIdx, tIdx = 12, 5, 0, 0
    for i=0, segs-1 do
        local th = (i/segs) * math.pi * 2
        for j=0, sides-1 do
            local ph = (j/sides) * math.pi * 2
            tor.verts[vIdx] = {x=(R+r*math.cos(ph))*math.cos(th), y=r*math.sin(ph), z=(R+r*math.cos(ph))*math.sin(th)}
            vIdx = vIdx + 1
        end
    end
    for i=0, segs-1 do
        local i_next = (i+1)%segs
        for j=0, sides-1 do
            local j_next = (j+1)%sides
            local a, b, c, d = i*sides+j, i_next*sides+j, i_next*sides+j_next, i*sides+j_next
            tor.tris[tIdx] = {v1=a, v2=c, v3=b, color=0xFFCC66FF}; tIdx = tIdx + 1
            tor.tris[tIdx] = {v1=a, v2=d, v3=c, color=0xFFAA44DD}; tIdx = tIdx + 1
        end
    end

    -- 2. Add the Platonic Cube
    CreateCube(32, 35, 32, 15)

    -- 3. Add the Icosahedron
    CreateIcosahedron(64, 35, 0, 10)

    -- 4. Add the UV Sphere
    CreateUVSphere(32, 35, -32, 12, 20, 20)
end

function love.update(dt)
    if pendingResize then
        resizeTimer = resizeTimer - dt
        if resizeTimer <= 0 then
            ReinitBuffers(love.graphics.getWidth(), love.graphics.getHeight())
            pendingResize = false
        end
        return
    end

    local s = 40 * dt
    if love.keyboard.isDown("w") then Cam.pos.x = Cam.pos.x + Cam.fw.x * s; Cam.pos.y = Cam.pos.y + Cam.fw.y * s; Cam.pos.z = Cam.pos.z + Cam.fw.z * s end
    if love.keyboard.isDown("s") then Cam.pos.x = Cam.pos.x - Cam.fw.x * s; Cam.pos.y = Cam.pos.y - Cam.fw.y * s; Cam.pos.z = Cam.pos.z - Cam.fw.z * s end
    if love.keyboard.isDown("a") then Cam.pos.x = Cam.pos.x - Cam.rt.x * s; Cam.pos.z = Cam.pos.z - Cam.rt.z * s end
    if love.keyboard.isDown("d") then Cam.pos.x = Cam.pos.x + Cam.rt.x * s; Cam.pos.z = Cam.pos.z + Cam.rt.z * s end
    if love.keyboard.isDown("e") then Cam.pos.y = Cam.pos.y - s end
    if love.keyboard.isDown("q") then Cam.pos.y = Cam.pos.y + s end

    -- Existing Keyboard Rotation (Always active as fallback)
    local rotSpeed = 2 * dt
    if love.keyboard.isDown("left")  then Cam.yaw = Cam.yaw - rotSpeed end
    if love.keyboard.isDown("right") then Cam.yaw = Cam.yaw + rotSpeed end
    if love.keyboard.isDown("up")    then Cam.pitch = Cam.pitch - rotSpeed end
    if love.keyboard.isDown("down")  then Cam.pitch = Cam.pitch + rotSpeed end

    Cam.pitch = max(-1.56, min(1.56, Cam.pitch))

    UpdateBasis(Cam)

    for _, obj in ipairs(TriObjects) do
        obj.transform.yaw = obj.transform.yaw + dt
        obj.transform.pitch = obj.transform.pitch + dt * 0.5
        UpdateBasis(obj.transform)
    end
end

function love.draw()
    if pendingResize then
        love.graphics.clear(0.05, 0.05, 0.05)
        love.graphics.print("REBUILDING SWAPCHAIN...", 20, 20)
        return
    end

    -- EXTREME FAST CLEAR: Use FFI to clear both buffers instantly
    ffi.fill(ScreenPtr, CANVAS_W * CANVAS_H * 4, 0)

    -- 0x7F byte pattern translates to roughly 3.4e38 in float representation
    ffi.fill(ZBuffer, CANVAS_W * CANVAS_H * 4, 0x7F)

    for _, obj in ipairs(TriObjects) do
        for i=0, obj.vCount-1 do
            local v, tr = obj.verts[i], obj.transform
            local wx = tr.pos.x + v.x*tr.rt.x + v.y*tr.up.x + v.z*tr.fw.x
            local wy = tr.pos.y + v.x*tr.rt.y + v.y*tr.up.y + v.z*tr.fw.y
            local wz = tr.pos.z + v.x*tr.rt.z + v.y*tr.up.z + v.z*tr.fw.z
            ProjectToScreen(wx, wy, wz, obj.pCache[i])
            obj.vCache[i].x, obj.vCache[i].y, obj.vCache[i].z = wx, wy, wz
        end

        for i=0, obj.tCount-1 do
            local t = obj.tris[i]
            local v1, v2, v3 = obj.vCache[t.v1], obj.vCache[t.v2], obj.vCache[t.v3]
            local p1, p2, p3 = obj.pCache[t.v1], obj.pCache[t.v2], obj.pCache[t.v3]

            if p1.valid and p2.valid and p3.valid then
                local nx = (v2.y-v1.y)*(v3.z-v1.z)-(v2.z-v1.z)*(v3.y-v1.y)
                local ny = (v2.z-v1.z)*(v3.x-v1.x)-(v2.x-v1.x)*(v3.z-v1.z)
                local nz = (v2.x-v1.x)*(v3.y-v1.y)-(v2.y-v1.y)*(v3.x-v1.x)
                local dotCam = nx*(v1.x-Cam.pos.x) + ny*(v1.y-Cam.pos.y) + nz*(v1.z-Cam.pos.z)

                if dotCam < 0 then
                    local len = sqrt(nx*nx + ny*ny + nz*nz)
                    nx, ny, nz = nx/len, ny/len, nz/len
                    local lightDot = max(0.2, min(1.0, nx*0.5 + ny*1.0 + nz*0.5))

                    local r = bit.band(bit.rshift(t.color, 16), 0xFF) * lightDot
                    local g = bit.band(bit.rshift(t.color, 8), 0xFF) * lightDot
                    local b = bit.band(t.color, 0xFF) * lightDot
                    local shadedColor = 0xFF000000 + bit.lshift(r, 16) + bit.lshift(g, 8) + b

                    RasterizeTriangle(p1, p2, p3, shadedColor)
                end
            end
        end
    end

    ScreenImage:replacePixels(ScreenBuffer)

    -- THE GHOSTBUSTER FIX: Tell LÖVE to overwrite the screen directly instead of blending
    love.graphics.setBlendMode("replace")
    love.graphics.draw(ScreenImage, 0, 0)

    -- Reset to standard blend mode for drawing text so it doesn't look weird
    love.graphics.setBlendMode("alpha")
    love.graphics.print("ULTIMA PLATIN | PTR ARITHMETIC | FPS: "..love.timer.getFPS(), 10, 10)

    -- NEW: Status indicator for the mouse
    local status = isMouseCaptured and "MOUSE LOCKED (J to unlock)" or "MOUSE FREE (J to lock)"
    love.graphics.print(status, 10, 30)
end

function love.resize(w, h)
    pendingResize = true
    resizeTimer = 0.2
end

function love.keypressed(key)
    if key == "f" then
        love.window.setFullscreen(not love.window.getFullscreen())
    elseif key == "j" then
        -- NEW: Toggle the state and update relative mode
        isMouseCaptured = not isMouseCaptured
        love.mouse.setRelativeMode(isMouseCaptured)
    elseif key == "escape" then
        love.event.quit()
    end
end

function love.mousemoved(x, y, dx, dy)
    if isMouseCaptured then
        local sensitivity = 0.002
        Cam.yaw = Cam.yaw + (dx * sensitivity)
        Cam.pitch = Cam.pitch + (dy * sensitivity)
    end
end

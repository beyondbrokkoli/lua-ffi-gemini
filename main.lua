local ffi = require("ffi")

-- 1. FFI DEFINITIONS (High-Performance Memory Layout)
ffi.cdef[[
    typedef struct { float x, y, z; } Vec3;

    typedef struct {
        Vec3 pos;
        Vec3 fw, rt, up;
        float yaw, pitch, fov;
    } Entity;

    /* Pre-decoded voxel for the Static World to avoid math in draw loop */
    typedef struct {
        float x, y, z;
        uint32_t color;
    } StaticVoxel;

    typedef struct {
        uint32_t color;
        uint8_t active;
    } Voxel;
]]

-- 2. ENGINE CONSTANTS
local STRIDE = 64
local WORLD_SIZE = STRIDE * STRIDE * STRIDE
local CANVAS_W, CANVAS_H = 800, 800
local MAX_DIST_SQ = 150 * 150 -- Distance culling (squared for speed)

-- 3. GLOBAL STATE
local World = ffi.new("Voxel[?]", WORLD_SIZE)
local StaticList = ffi.new("StaticVoxel[?]", WORLD_SIZE)
local StaticCount = 0

local Cam = ffi.new("Entity")
local ScreenBuffer = love.image.newImageData(CANVAS_W, CANVAS_H)
local ScreenPtr = ffi.cast("uint32_t*", ScreenBuffer:getPointer())
local ZBuffer = ffi.new("float[?]", CANVAS_W * CANVAS_H)
local ScreenImage = love.graphics.newImage(ScreenBuffer)

-- 4. THE VOXEL OBJECT KERNEL
local Objects = {}

function CreateVoxelObject(x, y, z, color, count)
    local obj = {
        transform = ffi.new("Entity"),
        voxels = ffi.new("Vec3[?]", count), -- FFI Array: Cache Locality Win
        count = count,
        color = color or 0xFFFFFFFF
    }
    obj.transform.pos = {x=x, y=y, z=z}
    table.insert(Objects, obj)
    return obj
end

-- 5. MATH & PROJECTION
local function UpdateBasis(ent)
    local cy, sy = math.cos(ent.yaw), math.sin(ent.yaw)
    local cp, sp = math.cos(ent.pitch), math.sin(ent.pitch)
    ent.fw.x, ent.fw.y, ent.fw.z = sy * cp, sp, cy * cp
    ent.rt.x, ent.rt.y, ent.rt.z = cy, 0, -sy
    ent.up.x = ent.fw.y * ent.rt.z - ent.fw.z * ent.rt.y
    ent.up.y = ent.fw.z * ent.rt.x - ent.fw.x * ent.rt.z
    ent.up.z = ent.fw.x * ent.rt.y - ent.fw.y * ent.rt.x
end

-- Inline-ready projection
local function ProjectAndDraw(wx, wy, wz, color)
    local dx, dy, dz = wx - Cam.pos.x, wy - Cam.pos.y, wz - Cam.pos.z
    
    -- Distance Culling (Square check is faster than sqrt)
    if (dx*dx + dy*dy + dz*dz) > MAX_DIST_SQ then return end

    local cz = dx * Cam.fw.x + dy * Cam.fw.y + dz * Cam.fw.z
    if cz > 0.5 then 
        local cx = dx * Cam.rt.x + dy * Cam.rt.y + dz * Cam.rt.z
        local cy = dx * Cam.up.x + dy * Cam.up.y + dz * Cam.up.z
        local f = Cam.fov / cz
        local sx = math.floor((CANVAS_W / 2) + (cx * f))
        local sy = math.floor((CANVAS_H / 2) + (cy * f))
        
        if sx >= 0 and sx < CANVAS_W and sy >= 0 and sy < CANVAS_H then
            local pIdx = sy * CANVAS_W + sx
            if cz < ZBuffer[pIdx] then
                ZBuffer[pIdx] = cz
                ScreenPtr[pIdx] = color
            end
        end
    end
end

-- 6. LÖVE CALLBACKS
function love.load()
    love.window.setMode(CANVAS_W, CANVAS_H)
    Cam.pos, Cam.fov = {x=32, y=32, z=-30}, 600

    -- Populate Floor (Example)
    for x=0, STRIDE-1 do
        for z=0, STRIDE-1 do
            local idx = (z * STRIDE * STRIDE) + ((STRIDE-1) * STRIDE) + x
            World[idx] = {color = 0xFF444444, active = 1}
        end
    end

    -- Precompute Static World (The 10x Speedup)
    StaticCount = 0
    for i=0, WORLD_SIZE-1 do
        if World[i].active == 1 then
            local lz = math.floor(i / (STRIDE * STRIDE))
            local ly = math.floor((i % (STRIDE * STRIDE)) / STRIDE)
            local lx = i % STRIDE
            StaticList[StaticCount] = {x=lx, y=ly, z=lz, color=World[i].color}
            StaticCount = StaticCount + 1
        end
    end

    -- Create a High-Density Dynamic Sphere
    local ball = CreateVoxelObject(32, 32, 32, 0xFF00FF77, 1000)
    for i=0, 999 do
        local phi = math.acos(1 - 2 * (i / 1000))
        local theta = math.pi * (1 + 5^0.5) * i
        ball.voxels[i].x = math.cos(theta) * math.sin(phi) * 6
        ball.voxels[i].y = math.sin(theta) * math.sin(phi) * 6
        ball.voxels[i].z = math.cos(phi) * 6
    end
end

function love.update(dt)
    -- Camera Movement
    local s = 30 * dt
    if love.keyboard.isDown("w") then 
        Cam.pos.x = Cam.pos.x + Cam.fw.x*s; Cam.pos.y = Cam.pos.y + Cam.fw.y*s; Cam.pos.z = Cam.pos.z + Cam.fw.z*s 
    end
    if love.keyboard.isDown("s") then 
        Cam.pos.x = Cam.pos.x - Cam.fw.x*s; Cam.pos.y = Cam.pos.y - Cam.fw.y*s; Cam.pos.z = Cam.pos.z - Cam.fw.z*s 
    end
    if love.keyboard.isDown("d") then Cam.pos.x = Cam.pos.x + Cam.rt.x*s; Cam.pos.z = Cam.pos.z + Cam.rt.z*s end
    if love.keyboard.isDown("a") then Cam.pos.x = Cam.pos.x - Cam.rt.x*s; Cam.pos.z = Cam.pos.z - Cam.rt.z*s end

    local rs = 1.8 * dt
    if love.keyboard.isDown("left")  then Cam.yaw = Cam.yaw - rs end
    if love.keyboard.isDown("right") then Cam.yaw = Cam.yaw + rs end
    if love.keyboard.isDown("up")    then Cam.pitch = Cam.pitch - rs end
    if love.keyboard.isDown("down")  then Cam.pitch = Cam.pitch + rs end
    UpdateBasis(Cam)

    -- Dynamic Spin
    for _, obj in ipairs(Objects) do
        obj.transform.yaw = obj.transform.yaw + dt
        UpdateBasis(obj.transform)
    end
end

function love.draw()
    ffi.fill(ScreenPtr, CANVAS_W * CANVAS_H * 4, 0)
    for i=0, (CANVAS_W * CANVAS_H)-1 do ZBuffer[i] = 100000 end

    -- 1. Draw Static World (No math, just raw data walk)
    for i=0, StaticCount-1 do
        local v = StaticList[i]
        ProjectAndDraw(v.x, v.y, v.z, v.color)
    end

    -- 2. Draw Dynamic Objects
    for _, obj in ipairs(Objects) do
        local t = obj.transform
        for i=0, obj.count-1 do
            local v = obj.voxels[i]
            local wx = t.pos.x + v.x * t.rt.x + v.y * t.up.x + v.z * t.fw.x
            local wy = t.pos.y + v.x * t.rt.y + v.y * t.up.y + v.z * t.fw.y
            local wz = t.pos.z + v.x * t.rt.z + v.y * t.up.z + v.z * t.fw.z
            ProjectAndDraw(wx, wy, wz, obj.color)
        end
    end

    ScreenImage:replacePixels(ScreenBuffer)
    love.graphics.draw(ScreenImage, 0, 0)
    love.graphics.print("ULTIMA PLATIN | FPS: "..love.timer.getFPS().." | Culling: Active", 10, 10)
end

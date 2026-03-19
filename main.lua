local ffi = require("ffi")

-- 1. FFI DEFINITIONS (Strict C-style comments)
ffi.cdef[[
    typedef struct { float x, y, z; } Vec3;

    typedef struct {
        Vec3 pos;       /* World Position */
        Vec3 fw, rt, up;/* Basis Vectors  */
        float yaw, pitch, fov;
    } Entity;           /* Shared by Camera and Objects */

    typedef struct {
        uint32_t color;
        uint8_t active;
    } Voxel;
]]

-- 2. ENGINE CONSTANTS
local STRIDE = 64
local WORLD_SIZE = STRIDE * STRIDE * STRIDE
local CANVAS_W, CANVAS_H = 800, 800

-- 3. GLOBAL STATE
local World = ffi.new("Voxel[?]", WORLD_SIZE)
local StaticIndices = ffi.new("uint32_t[?]", WORLD_SIZE)
local StaticCount = 0

local Cam = ffi.new("Entity")
local ScreenBuffer = love.image.newImageData(CANVAS_W, CANVAS_H)
local ScreenPtr = ffi.cast("uint32_t*", ScreenBuffer:getPointer())
local ZBuffer = ffi.new("float[?]", CANVAS_W * CANVAS_H)
local ScreenImage = love.graphics.newImage(ScreenBuffer)

-- 4. VOXEL OBJECT SYSTEM
local Objects = {}

function CreateVoxelObject(x, y, z, color)
    local obj = {
        transform = ffi.new("Entity"),
        voxels = {}, -- Stores local Vec3 offsets
        color = color or 0xFFFFFFFF
    }
    obj.transform.pos = {x=x, y=y, z=z}
    table.insert(Objects, obj)
    return obj
end

-- 5. MATH KERNEL (The Engine Heart)
local function UpdateBasis(ent)
    local cy, sy = math.cos(ent.yaw), math.sin(ent.yaw)
    local cp, sp = math.cos(ent.pitch), math.sin(ent.pitch)
    -- Forward
    ent.fw.x, ent.fw.y, ent.fw.z = sy * cp, sp, cy * cp
    -- Right
    ent.rt.x, ent.rt.y, ent.rt.z = cy, 0, -sy
    -- Up (Cross Product)
    ent.up.x = ent.fw.y * ent.rt.z - ent.fw.z * ent.rt.y
    ent.up.y = ent.fw.z * ent.rt.x - ent.fw.x * ent.rt.z
    ent.up.z = ent.fw.x * ent.rt.y - ent.fw.y * ent.rt.x
end

local function ProjectAndDraw(wx, wy, wz, color)
    local dx, dy, dz = wx - Cam.pos.x, wy - Cam.pos.y, wz - Cam.pos.z
    -- World -> Camera Space
    local cz = dx * Cam.fw.x + dy * Cam.fw.y + dz * Cam.fw.z
    if cz > 0.5 then
        local cx = dx * Cam.rt.x + dy * Cam.rt.y + dz * Cam.rt.zlocal ffi = require("ffi")

-- 1. FFI DEFINITIONS (Strict C-style comments)
ffi.cdef[[
    typedef struct { float x, y, z; } Vec3;

    typedef struct {
        Vec3 pos;       /* World Position */
        Vec3 fw, rt, up;/* Basis Vectors  */
        float yaw, pitch, fov;
    } Entity;           /* Shared by Camera and Objects */

    typedef struct {
        uint32_t color;
        uint8_t active;
    } Voxel;
]]

-- 2. ENGINE CONSTANTS
local STRIDE = 64
local WORLD_SIZE = STRIDE * STRIDE * STRIDE
local CANVAS_W, CANVAS_H = 800, 800

-- 3. GLOBAL STATE
local World = ffi.new("Voxel[?]", WORLD_SIZE)
local StaticIndices = ffi.new("uint32_t[?]", WORLD_SIZE)
local StaticCount = 0

local Cam = ffi.new("Entity")
local ScreenBuffer = love.image.newImageData(CANVAS_W, CANVAS_H)
local ScreenPtr = ffi.cast("uint32_t*", ScreenBuffer:getPointer())
local ZBuffer = ffi.new("float[?]", CANVAS_W * CANVAS_H)
local ScreenImage = love.graphics.newImage(ScreenBuffer)

-- 4. VOXEL OBJECT SYSTEM
local Objects = {}

function CreateVoxelObject(x, y, z, color)
    local obj = {
        transform = ffi.new("Entity"),
        voxels = {}, -- Stores local Vec3 offsets
        color = color or 0xFFFFFFFF
    }
    obj.transform.pos = {x=x, y=y, z=z}
    table.insert(Objects, obj)
    return obj
end

-- 5. MATH KERNEL (The Engine Heart)
local function UpdateBasis(ent)
    local cy, sy = math.cos(ent.yaw), math.sin(ent.yaw)
    local cp, sp = math.cos(ent.pitch), math.sin(ent.pitch)
    -- Forward
    ent.fw.x, ent.fw.y, ent.fw.z = sy * cp, sp, cy * cp
    -- Right
    ent.rt.x, ent.rt.y, ent.rt.z = cy, 0, -sy
    -- Up (Cross Product)
    ent.up.x = ent.fw.y * ent.rt.z - ent.fw.z * ent.rt.y
    ent.up.y = ent.fw.z * ent.rt.x - ent.fw.x * ent.rt.z
    ent.up.z = ent.fw.x * ent.rt.y - ent.fw.y * ent.rt.x
end

local function ProjectAndDraw(wx, wy, wz, color)
    local dx, dy, dz = wx - Cam.pos.x, wy - Cam.pos.y, wz - Cam.pos.z
    -- World -> Camera Space
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

    -- Create Static Floor
    for x=0, STRIDE-1 do
        for z=0, STRIDE-1 do
            local idx = (z * STRIDE * STRIDE) + ((STRIDE-1) * STRIDE) + x
            World[idx] = {color = 0xFF333333, active = 1}
        end
    end
    -- Sync Static List (O(N^3) done once)
    StaticCount = 0
    for i=0, WORLD_SIZE-1 do
        if World[i].active == 1 then StaticIndices[StaticCount] = i; StaticCount = StaticCount + 1 end
    end

    -- Create Dynamic Object: A Rotating Cube
    local spinner = CreateVoxelObject(32, 32, 32, 0xFF00AAFF)
    for x=-4, 4 do for y=-4, 4 do for z=-4, 4 do
        table.insert(spinner.voxels, {x=x, y=y, z=z})
    end end end
end

function love.update(dt)
    -- Camera Movement (Perspective-Relative)
    local s = 30 * dt
    if love.keyboard.isDown("w") then
        Cam.pos.x = Cam.pos.x + Cam.fw.x * s; Cam.pos.y = Cam.pos.y + Cam.fw.y * s; Cam.pos.z = Cam.pos.z + Cam.fw.z * s
    end
    if love.keyboard.isDown("s") then
        Cam.pos.x = Cam.pos.x - Cam.fw.x * s; Cam.pos.y = Cam.pos.y - Cam.fw.y * s; Cam.pos.z = Cam.pos.z - Cam.fw.z * s
    end
    if love.keyboard.isDown("d") then Cam.pos.x = Cam.pos.x + Cam.rt.x * s; Cam.pos.z = Cam.pos.z + Cam.rt.z * s end
    if love.keyboard.isDown("a") then Cam.pos.x = Cam.pos.x - Cam.rt.x * s; Cam.pos.z = Cam.pos.z - Cam.rt.z * s end

    -- Rotation
    local rs = 2 * dt
    if love.keyboard.isDown("left") then Cam.yaw = Cam.yaw - rs end
    if love.keyboard.isDown("right") then Cam.yaw = Cam.yaw + rs end
    if love.keyboard.isDown("up") then Cam.pitch = Cam.pitch - rs end
    if love.keyboard.isDown("down") then Cam.pitch = Cam.pitch + rs end
    UpdateBasis(Cam)

    -- Rotate the Dynamic Object
    for _, obj in ipairs(Objects) do
        obj.transform.yaw = obj.transform.yaw + dt
        obj.transform.pitch = obj.transform.pitch + (dt * 0.5)
        UpdateBasis(obj.transform)
    end
end

function love.draw()
    ffi.fill(ScreenPtr, CANVAS_W * CANVAS_H * 4, 0)
    for i=0, (CANVAS_W * CANVAS_H)-1 do ZBuffer[i] = 100000 end

    -- DRAW STATIC WORLD
    for i=0, StaticCount-1 do
        local idx = StaticIndices[i]
        local lz = math.floor(idx / (STRIDE * STRIDE))
        local ly = math.floor((idx % (STRIDE * STRIDE)) / STRIDE)
        local lx = idx % STRIDE
        ProjectAndDraw(lx, ly, lz, World[idx].color)
    end

    -- DRAW DYNAMIC OBJECTS (Local -> World -> Camera)
    for _, obj in ipairs(Objects) do
        local t = obj.transform
        for _, v in ipairs(obj.voxels) do
            -- Local to World Rotation
            local wx = t.pos.x + v.x * t.rt.x + v.y * t.up.x + v.z * t.fw.x
            local wy = t.pos.y + v.x * t.rt.y + v.y * t.up.y + v.z * t.fw.y
            local wz = t.pos.z + v.x * t.rt.z + v.y * t.up.z + v.z * t.fw.z
            ProjectAndDraw(wx, wy, wz, obj.color)
        end
    end

    ScreenImage:replacePixels(ScreenBuffer)
    love.graphics.draw(ScreenImage, 0, 0)
    love.graphics.print("PLATIN Template | Objects: "..#Objects.." | Static: "..StaticCount, 10, 10)
end
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

    -- Create Static Floor
    for x=0, STRIDE-1 do
        for z=0, STRIDE-1 do
            local idx = (z * STRIDE * STRIDE) + ((STRIDE-1) * STRIDE) + x
            World[idx] = {color = 0xFF333333, active = 1}
        end
    end
    -- Sync Static List (O(N^3) done once)
    StaticCount = 0
    for i=0, WORLD_SIZE-1 do
        if World[i].active == 1 then StaticIndices[StaticCount] = i; StaticCount = StaticCount + 1 end
    end

    -- Create Dynamic Object: A Rotating Cube
    local spinner = CreateVoxelObject(32, 32, 32, 0xFF00AAFF)
    for x=-4, 4 do for y=-4, 4 do for z=-4, 4 do
        table.insert(spinner.voxels, {x=x, y=y, z=z})
    end end end
end

function love.update(dt)
    -- Camera Movement (Perspective-Relative)
    local s = 30 * dt
    if love.keyboard.isDown("w") then
        Cam.pos.x = Cam.pos.x + Cam.fw.x * s; Cam.pos.y = Cam.pos.y + Cam.fw.y * s; Cam.pos.z = Cam.pos.z + Cam.fw.z * s
    end
    if love.keyboard.isDown("s") then
        Cam.pos.x = Cam.pos.x - Cam.fw.x * s; Cam.pos.y = Cam.pos.y - Cam.fw.y * s; Cam.pos.z = Cam.pos.z - Cam.fw.z * s
    end
    if love.keyboard.isDown("d") then Cam.pos.x = Cam.pos.x + Cam.rt.x * s; Cam.pos.z = Cam.pos.z + Cam.rt.z * s end
    if love.keyboard.isDown("a") then Cam.pos.x = Cam.pos.x - Cam.rt.x * s; Cam.pos.z = Cam.pos.z - Cam.rt.z * s end

    -- Rotation
    local rs = 2 * dt
    if love.keyboard.isDown("left") then Cam.yaw = Cam.yaw - rs end
    if love.keyboard.isDown("right") then Cam.yaw = Cam.yaw + rs end
    if love.keyboard.isDown("up") then Cam.pitch = Cam.pitch - rs end
    if love.keyboard.isDown("down") then Cam.pitch = Cam.pitch + rs end
    UpdateBasis(Cam)

    -- Rotate the Dynamic Object
    for _, obj in ipairs(Objects) do
        obj.transform.yaw = obj.transform.yaw + dt
        obj.transform.pitch = obj.transform.pitch + (dt * 0.5)
        UpdateBasis(obj.transform)
    end
end

function love.draw()
    ffi.fill(ScreenPtr, CANVAS_W * CANVAS_H * 4, 0)
    for i=0, (CANVAS_W * CANVAS_H)-1 do ZBuffer[i] = 100000 end

    -- DRAW STATIC WORLD
    for i=0, StaticCount-1 do
        local idx = StaticIndices[i]
        local lz = math.floor(idx / (STRIDE * STRIDE))
        local ly = math.floor((idx % (STRIDE * STRIDE)) / STRIDE)
        local lx = idx % STRIDE
        ProjectAndDraw(lx, ly, lz, World[idx].color)
    end

    -- DRAW DYNAMIC OBJECTS (Local -> World -> Camera)
    for _, obj in ipairs(Objects) do
        local t = obj.transform
        for _, v in ipairs(obj.voxels) do
            -- Local to World Rotation
            local wx = t.pos.x + v.x * t.rt.x + v.y * t.up.x + v.z * t.fw.x
            local wy = t.pos.y + v.x * t.rt.y + v.y * t.up.y + v.z * t.fw.y
            local wz = t.pos.z + v.x * t.rt.z + v.y * t.up.z + v.z * t.fw.z
            ProjectAndDraw(wx, wy, wz, obj.color)
        end
    end

    ScreenImage:replacePixels(ScreenBuffer)
    love.graphics.draw(ScreenImage, 0, 0)
    love.graphics.print("PLATIN Template | Objects: "..#Objects.." | Static: "..StaticCount, 10, 10)
end

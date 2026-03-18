local ffi = require("ffi")

-- 1. FFI DEFINITIONS (C-style comments)
ffi.cdef[[
    typedef struct {
        float x, y, z;
    } Vec3;

    typedef struct {
        Vec3 pos;       /* World Position */
        Vec3 fw;        /* Forward Vector */
        Vec3 rt;        /* Right Vector   */
        Vec3 up;        /* Up Vector      */
        float yaw;      /* Horizontal Rot */
        float pitch;    /* Vertical Rot   */
        float fov;      /* Field of View  */
    } Camera;

    typedef struct {
        uint32_t color; /* 0xAABBGGRR     */
        uint8_t active; /* Voxel State    */
    } Voxel;
]]

-- 2. ENGINE CONSTANTS
local STRIDE = 64 -- The "Unit". 64^3 = 262,144 voxels.
local WORLD_SIZE = STRIDE * STRIDE * STRIDE
local CANVAS_W, CANVAS_H = 800, 800

-- 3. GLOBAL STATE
local World = ffi.new("Voxel[?]", WORLD_SIZE)
local Cam = ffi.new("Camera")
local ScreenBuffer = love.image.newImageData(CANVAS_W, CANVAS_H)
local ScreenPtr = ffi.cast("uint32_t*", ScreenBuffer:getPointer())
local ZBuffer = ffi.new("float[?]", CANVAS_W * CANVAS_H)
local ScreenImage = love.graphics.newImage(ScreenBuffer)

-- 4. UTILITY FUNCTIONS
local function GetIdx(x, y, z)
    if x < 0 or x >= STRIDE or y < 0 or y >= STRIDE or z < 0 or z >= STRIDE then return nil end
    return z * (STRIDE * STRIDE) + y * STRIDE + x
end

local function SetVoxel(x, y, z, color)
    local idx = GetIdx(math.floor(x), math.floor(y), math.floor(z))
    if idx then
        World[idx].color = color
        World[idx].active = 1
    end
end

-- 5. CAMERA LOGIC (The 10x Speedup)
local function UpdateCameraVectors()
    local cy, sy = math.cos(Cam.yaw), math.sin(Cam.yaw)
    local cp, sp = math.cos(Cam.pitch), math.sin(Cam.pitch)

    -- Forward Vector: Direction camera looks
    Cam.fw.x, Cam.fw.y, Cam.fw.z = sy * cp, sp, cy * cp

    -- Right Vector: Perpendicular to Forward and World-Up
    Cam.rt.x, Cam.rt.y, Cam.rt.z = cy, 0, -sy

    -- Up Vector: Cross product of Right and Forward
    Cam.up.x = Cam.fw.y * Cam.rt.z - Cam.fw.z * Cam.rt.y
    Cam.up.y = Cam.fw.z * Cam.rt.x - Cam.fw.x * Cam.rt.z
    Cam.up.z = Cam.fw.x * Cam.rt.y - Cam.fw.y * Cam.rt.x
end

-- 6. LÖVE CALLBACKS
function love.load()
    love.window.setMode(CANVAS_W, CANVAS_H, {resizable=false})

    -- Initialize Camera
    Cam.pos = {x = STRIDE/2, y = STRIDE/2, z = -20}
    Cam.fov = 600 -- Pixels per unit distance
    Cam.yaw = 0
    Cam.pitch = 0

    -- Populate World with Shapes (Stamping into the Grid)
    -- Floor
    for x = 0, STRIDE-1 do
        for z = 0, STRIDE-1 do
            SetVoxel(x, STRIDE-1, z, 0xFF444444)
        end
    end

    -- A Cube
    for x = 20, 30 do
        for y = 40, 50 do
            for z = 20, 30 do
                SetVoxel(x, y, z, 0xFFDDEE00)
            end
        end
    end

    -- A Sphere
    local r = 8
    local cx, cy, cz = 45, 45, 45
    for x = cx-r, cx+r do
        for y = cy-r, cy+r do
            for z = cz-r, cz+r do
                local dist = (x-cx)^2 + (y-cy)^2 + (z-cz)^2
                if dist < r*r then SetVoxel(x, y, z, 0xFF00FF77) end
            end
        end
    end
end

function love.update(dt)
    -- Movement
    local speed = 20 * dt
    if love.keyboard.isDown("w") then Cam.pos.z = Cam.pos.z + speed end
    if love.keyboard.isDown("s") then Cam.pos.z = Cam.pos.z - speed end
    if love.keyboard.isDown("a") then Cam.pos.x = Cam.pos.x - speed end
    if love.keyboard.isDown("d") then Cam.pos.x = Cam.pos.x + speed end
    if love.keyboard.isDown("q") then Cam.pos.y = Cam.pos.y - speed end
    if love.keyboard.isDown("e") then Cam.pos.y = Cam.pos.y + speed end

    -- Rotation
    local rotSpeed = 1.5 * dt
    if love.keyboard.isDown("left")  then Cam.yaw = Cam.yaw - rotSpeed end
    if love.keyboard.isDown("right") then Cam.yaw = Cam.yaw + rotSpeed end
    if love.keyboard.isDown("up")    then Cam.pitch = Cam.pitch - rotSpeed end
    if love.keyboard.isDown("down")  then Cam.pitch = Cam.pitch + rotSpeed end

    UpdateCameraVectors()
end

function love.draw()
    -- Clear Buffers
    ffi.fill(ScreenPtr, CANVAS_W * CANVAS_H * 4, 0)
    for i = 0, (CANVAS_W * CANVAS_H) - 1 do ZBuffer[i] = 100000 end

    -- RENDER LOOP: Iterate through the world
    -- Note: For massive speed, only iterate voxels that are ACTIVE.
    for z = 0, STRIDE-1 do
        for y = 0, STRIDE-1 do
            for x = 0, STRIDE-1 do
                local idx = z * (STRIDE * STRIDE) + y * STRIDE + x
                local vox = World[idx]

                if vox.active == 1 then
                    -- Vector from Camera to Voxel
                    local dx = x - Cam.pos.x
                    local dy = y - Cam.pos.y
                    local dz = z - Cam.pos.z

                    -- Project using Dot Products (Camera Basis)
                    local camZ = dx * Cam.fw.x + dy * Cam.fw.y + dz * Cam.fw.z

                    if camZ > 0.1 then -- Clipping
                        local camX = dx * Cam.rt.x + dy * Cam.rt.y + dz * Cam.rt.z
                        local camY = dx * Cam.up.x + dy * Cam.up.y + dz * Cam.up.z

                        -- Perspective
                        local f = Cam.fov / camZ
                        local sx = math.floor((CANVAS_W / 2) + (camX * f))
                        local sy = math.floor((CANVAS_H / 2) + (camY * f))

                        if sx >= 0 and sx < CANVAS_W and sy >= 0 and sy < CANVAS_H then
                            local pixIdx = sy * CANVAS_W + sx
                            if camZ < ZBuffer[pixIdx] then
                                ZBuffer[pixIdx] = camZ
                                ScreenPtr[pixIdx] = vox.color
                            end
                        end
                    end
                end
            end
        end
    end

    ScreenImage:replacePixels(ScreenBuffer)
    love.graphics.draw(ScreenImage, 0, 0)

    love.graphics.print("WASD/QE: Move | Arrows: Rotate | Voxels: " .. STRIDE^3, 10, 10)
end

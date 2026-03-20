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

-- Localizing hot functions for LuaJIT performance
local floor, ceil, max, min = math.floor, math.ceil, math.max, math.min
local sqrt, cos, sin = math.sqrt, math.cos, math.sin
local abs = math.abs

-- ==========================================
-- 2. GLOBAL STATE & BUFFERS
-- ==========================================
local CANVAS_W, CANVAS_H, HALF_W, HALF_H
local ScreenBuffer, ScreenPtr, ZBuffer, ScreenImage
local Cam = ffi.new("Entity")
local TriObjects = {}

local Z_FAR = 100000
local resizeTimer = 0
local pendingResize = false

-- SINGLE POINT of truth for memory and projection constants
local function ReinitBuffers(w, h)
    CANVAS_W, CANVAS_H = w, h
    HALF_W, HALF_H = w * 0.5, h * 0.5

    ScreenBuffer = love.image.newImageData(CANVAS_W, CANVAS_H)
    ScreenImage = love.graphics.newImage(ScreenBuffer)

    ScreenPtr = ffi.cast("uint32_t*", ScreenBuffer:getPointer())
    ZBuffer = ffi.new("float[?]", CANVAS_W * CANVAS_H)

    -- Update FOV relative to width
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

    -- Pre-calculate Y bounds
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

            -- POINTER ARITHMETIC: Get the base address of the current row
            local row_idx = y * CANVAS_W
            local z_row = ZBuffer + row_idx
            local s_row = ScreenPtr + row_idx

            for x = start_x, end_x do
                -- Raw index access is extremely fast in FFI
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
-- 6. LÖVE CALLBACKS
-- ==========================================
function love.load()
    local startW, startH = love.graphics.getDimensions()
    ReinitBuffers(startW, startH)
    love.window.setMode(CANVAS_W, CANVAS_H, {resizable=true})

    Cam.pos = {x=32, y=35, z=-20}

    -- TORUS GENERATION
    local segs, sides = 32, 16
    local tor = CreateTriObject(32, 35, 32, segs*sides, segs*sides*2)
    local R, r, vIdx, tIdx = 12, 5, 0, 0

    for i=0, segs-1 do
        local th = (i/segs) * math.pi * 2
        for j=0, sides-1 do
            local ph = (j/sides) * math.pi * 2
            tor.verts[vIdx] = {
                x = (R + r * cos(ph)) * cos(th),
                y = r * sin(ph),
                z = (R + r * cos(ph)) * sin(th)
            }
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

    -- Movement logic
    local s = 40 * dt
    if love.keyboard.isDown("w") then
        Cam.pos.x = Cam.pos.x + Cam.fw.x * s
        Cam.pos.y = Cam.pos.y + Cam.fw.y * s
        Cam.pos.z = Cam.pos.z + Cam.fw.z * s
    end
    if love.keyboard.isDown("s") then
        Cam.pos.x = Cam.pos.x - Cam.fw.x * s
        Cam.pos.y = Cam.pos.y - Cam.fw.y * s
        Cam.pos.z = Cam.pos.z - Cam.fw.z * s
    end
    if love.keyboard.isDown("a") then
        Cam.pos.x = Cam.pos.x - Cam.rt.x * s
        Cam.pos.z = Cam.pos.z - Cam.rt.z * s
    end
    if love.keyboard.isDown("d") then
        Cam.pos.x = Cam.pos.x + Cam.rt.x * s
        Cam.pos.z = Cam.pos.z + Cam.rt.z * s
    end
    if love.keyboard.isDown("e") then Cam.pos.y = Cam.pos.y - s end
    if love.keyboard.isDown("q") then Cam.pos.y = Cam.pos.y + s end

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

    -- Fast Clear
    ffi.fill(ScreenPtr, CANVAS_W * CANVAS_H * 4, 0)
    for i=0, (CANVAS_W * CANVAS_H)-1 do ZBuffer[i] = Z_FAR end

    for _, obj in ipairs(TriObjects) do
        -- 1. TRANSFORM & PROJECT
        for i=0, obj.vCount-1 do
            local v, tr = obj.verts[i], obj.transform
            local wx = tr.pos.x + v.x*tr.rt.x + v.y*tr.up.x + v.z*tr.fw.x
            local wy = tr.pos.y + v.x*tr.rt.y + v.y*tr.up.y + v.z*tr.fw.y
            local wz = tr.pos.z + v.x*tr.rt.z + v.y*tr.up.z + v.z*tr.fw.z

            ProjectToScreen(wx, wy, wz, obj.pCache[i])
            obj.vCache[i].x, obj.vCache[i].y, obj.vCache[i].z = wx, wy, wz
        end

        -- 2. DRAW TRIANGLES
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
    love.graphics.draw(ScreenImage, 0, 0)
    love.graphics.print("ULTIMA PLATIN | PTR ARITHMETIC | FPS: "..love.timer.getFPS(), 10, 10)
end

function love.resize(w, h)
    pendingResize = true
    resizeTimer = 0.2
end

function love.keypressed(key)
    if key == "f" then
        love.window.setFullscreen(not love.window.getFullscreen())
    end
end

-- main.lua
local ffi = require("ffi")
local bit = require("bit")

-- ==========================================
-- 1. FFI DEFINITIONS & LOCALIZATIONS
-- ==========================================
-- Added pre-unpacked colors for zero-overhead lighting
ffi.cdef[[
    typedef struct { float x, y, z; } Vec3;
    typedef struct { Vec3 pos; Vec3 fw, rt, up; float yaw, pitch, fov; } Entity;
    typedef struct { int v1, v2, v3; float r, g, b; } Triangle;
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
-- 3. SOA KERNEL & SHAPES
-- ==========================================
function CreateTriObject(x, y, z, vCount, tCount)
    local obj = {
        transform = ffi.new("Entity"),
        -- SoA: Local Vertices
        vx = ffi.new("float[?]", vCount),
        vy = ffi.new("float[?]", vCount),
        vz = ffi.new("float[?]", vCount),
        -- SoA: World Space Cache
        cx = ffi.new("float[?]", vCount),
        cy = ffi.new("float[?]", vCount),
        cz = ffi.new("float[?]", vCount),
        -- SoA: Screen Space Cache
        px = ffi.new("float[?]", vCount),
        py = ffi.new("float[?]", vCount),
        pz = ffi.new("float[?]", vCount),
        pValid = ffi.new("bool[?]", vCount),

        tris = ffi.new("Triangle[?]", tCount),
        vCount = vCount, tCount = tCount
    }
    obj.transform.pos = {x=x, y=y, z=z}
    table.insert(TriObjects, obj)
    return obj
end

function CreateTorus(cx, cy, cz, mainRadius, tubeRadius, segments, sides)
    local tor = CreateTriObject(cx, cy, cz, segments * sides, segments * sides * 2)
    local vIdx, tIdx = 0, 0
    for i=0, segments-1 do
        local th = (i/segments) * math.pi * 2
        for j=0, sides-1 do
            local ph = (j/sides) * math.pi * 2
            -- Writing linearly into SoA arrays
            tor.vx[vIdx] = (mainRadius + tubeRadius * cos(ph)) * cos(th)
            tor.vy[vIdx] = tubeRadius * sin(ph)
            tor.vz[vIdx] = (mainRadius + tubeRadius * cos(ph)) * sin(th)
            vIdx = vIdx + 1
        end
    end
    -- Inside CreateTorus, where triangles are assigned:
    for i=0, segments-1 do
        local i_next = (i+1) % segments
        for j=0, sides-1 do
            local j_next = (j+1) % sides
            local a, b, c, d = i*sides+j, i_next*sides+j, i_next*sides+j_next, i*sides+j_next

            -- Define your raw colors once
            local c1, c2 = 0xFFFFCC44, 0xFFCC8822

            local function unpack(hex)
                return bit.band(bit.rshift(hex, 16), 0xFF),
                       bit.band(bit.rshift(hex, 8), 0xFF),
                       bit.band(hex, 0xFF)
            end

            local r1, g1, b1 = unpack(c1)
            local r2, g2, b2 = unpack(c2)

            tor.tris[tIdx] = {v1=a, v2=c, v3=b, r=r1, g=g1, b=b1}; tIdx = tIdx + 1
            tor.tris[tIdx] = {v1=a, v2=d, v3=c, r=r2, g=g2, b=b2}; tIdx = tIdx + 1
        end
    end
    return tor
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
-- 4. SCANLINE RASTERIZER (Raw Float Edition)
-- ==========================================
-- Optimized Rasterizer (The DDA Edition)
local function RasterizeTriangle(x1,y1,z1, x2,y2,z2, x3,y3,z3, shadedColor)
    -- 1. Sort vertices (y1 <= y2 <= y3)
    if y1 > y2 then x1,x2 = x2,x1; y1,y2 = y2,y1; z1,z2 = z2,z1 end
    if y1 > y3 then x1,x3 = x3,x1; y1,y3 = y3,y1; z1,z3 = z3,z1 end
    if y2 > y3 then x2,x3 = x3,x2; y2,y3 = y3,y2; z2,z3 = z3,z2 end

    local total_h = y3 - y1
    if total_h < 1 then return end

    -- 2. Calculate Slopes (Deltas per 1 pixel in Y)
    -- Long edge (1 -> 3)
    local inv_total = 1.0 / total_h
    local dx13 = (x3 - x1) * inv_total
    local dz13 = (z3 - z1) * inv_total

    -- Short edges (1 -> 2 and 2 -> 3)
    local upper_h = y2 - y1
    local lower_h = y3 - y2

    -- 3. Rasterize Top Half
    if upper_h > 0.00001 then -- Prevent snake gaps!
        local inv_up = 1.0 / upper_h
        local dx12 = (x2 - x1) * inv_up
        local dz12 = (z2 - z1) * inv_up

        local y_start = max(0, ceil(y1))
        local y_end   = min(CANVAS_H - 1, floor(y2))

        for y = y_start, y_end do
            local prestep = y - y1
            local ax, az = x1 + dx13 * prestep, z1 + dz13 * prestep
            local bx, bz = x1 + dx12 * prestep, z1 + dz12 * prestep

            if ax > bx then ax, bx = bx, ax; az, bz = bz, az end

            -- Inner Span Loop
            local row_idx = y * CANVAS_W
            local z_row, s_row = ZBuffer + row_idx, ScreenPtr + row_idx
            local rw = bx - ax
            if rw > 0 then
                local z_step = (bz - az) / rw
                -- Consistent rounding to prevent "Snake" gaps
                local start_x = ceil(ax)
                local end_x   = ceil(bx) - 1 -- Triangle owns the pixel its start falls in, but not its end

                -- Clamp to screen
                if start_x < 0 then start_x = 0 end
                if end_x > CANVAS_W - 1 then end_x = CANVAS_W - 1 end

                if start_x <= end_x then
                    local cur_z = az + z_step * (start_x - ax)
                    for x = start_x, end_x do
                        -- REVERSED Z-TEST: Larger 1/Z means closer to camera
                        if cur_z > z_row[x] then
                            z_row[x], s_row[x] = cur_z, shadedColor
                        end
                        cur_z = cur_z + z_step
                    end
                end
            end
        end
    end

    -- 4. Rasterize Bottom Half
    if lower_h > 0.00001 then -- Prevent snake gaps!
        local inv_low = 1.0 / lower_h
        local dx23 = (x3 - x2) * inv_low
        local dz23 = (z3 - z2) * inv_low

        local y_start = max(0, ceil(y2))
        local y_end   = min(CANVAS_H - 1, floor(y3))

        for y = y_start, y_end do
            local ax = x1 + dx13 * (y - y1)
            local az = z1 + dz13 * (y - y1)
            local bx = x2 + dx23 * (y - y2)
            local bz = z2 + dz23 * (y - y2)

            if ax > bx then ax, bx = bx, ax; az, bz = bz, az end

            local row_idx = y * CANVAS_W
            local z_row, s_row = ZBuffer + row_idx, ScreenPtr + row_idx
            local rw = bx - ax
            if rw > 0 then
                local z_step = (bz - az) / rw
                -- Consistent rounding to prevent "Snake" gaps
                local start_x = ceil(ax)
                local end_x   = ceil(bx) - 1 -- Triangle owns the pixel its start falls in, but not its end

                -- Clamp to screen
                if start_x < 0 then start_x = 0 end
                if end_x > CANVAS_W - 1 then end_x = CANVAS_W - 1 end

                if start_x <= end_x then
                    local cur_z = az + z_step * (start_x - ax)
                    for x = start_x, end_x do
                        -- REVERSED Z-TEST: Larger 1/Z means closer to camera
                        if cur_z > z_row[x] then
                            z_row[x], s_row[x] = cur_z, shadedColor
                        end
                        cur_z = cur_z + z_step
                    end
                end
            end
        end
    end
end
-- ==========================================
-- 5. LÖVE CALLBACKS
-- ==========================================
function love.load()
    local startW, startH = love.graphics.getDimensions()
    ReinitBuffers(startW, startH)
    love.window.setMode(CANVAS_W, CANVAS_H, {resizable=true})
    Cam.pos = {x=0, y=50, z=-200}

    CreateTorus(150, 50, 100, 40, 15, 128, 64)
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

    -- Lightning fast C-level fills!
    ffi.fill(ScreenPtr, CANVAS_W * CANVAS_H * 4, 0)
    ffi.fill(ZBuffer, CANVAS_W * CANVAS_H * 4, 0) -- IEEE 754 0.0 is bitwise 0

    -- Cache camera locals to avoid constant struct lookups
    local cpx, cpy, cpz = Cam.pos.x, Cam.pos.y, Cam.pos.z
    local cfw_x, cfw_y, cfw_z = Cam.fw.x, Cam.fw.y, Cam.fw.z
    local crt_x, crt_y, crt_z = Cam.rt.x, Cam.rt.y, Cam.rt.z
    local cup_x, cup_y, cup_z = Cam.up.x, Cam.up.y, Cam.up.z
    local cfov = Cam.fov

    for _, obj in ipairs(TriObjects) do
        local tr = obj.transform
        local px, py, pz = tr.pos.x, tr.pos.y, tr.pos.z
        local rx, ry, rz = tr.rt.x, tr.rt.y, tr.rt.z
        local ux, uy, uz = tr.up.x, tr.up.y, tr.up.z
        local fx, fy, fz = tr.fw.x, tr.fw.y, tr.fw.z

        -- DOD Phase 1: Batched Linear Transforms & Projection
        for i = 0, obj.vCount - 1 do
            -- Fast sequential read
            local lx, ly, lz = obj.vx[i], obj.vy[i], obj.vz[i]

            local wx = px + lx*rx + ly*ux + lz*fx
            local wy = py + lx*ry + ly*uy + lz*fy
            local wz = pz + lx*rz + ly*uz + lz*fz

            obj.cx[i], obj.cy[i], obj.cz[i] = wx, wy, wz

            local dx, dy, dz = wx - cpx, wy - cpy, wz - cpz
            local cz = dx*cfw_x + dy*cfw_y + dz*cfw_z

            if cz < 0.1 then
                obj.pValid[i] = false
            else
                local f = cfov / cz
                obj.px[i] = HALF_W + (dx*crt_x + dy*crt_y + dz*crt_z) * f
                obj.py[i] = HALF_H + (dx*cup_x + dy*cup_y + dz*cup_z) * f
                obj.pz[i] = 1.0 / cz  -- Store 1/Z for perspective-correct interpolation
                obj.pValid[i] = true
            end
        end
        -- stable color packing
        -- DOD Phase 2: Geometry Rasterization
        for i = 0, obj.tCount - 1 do
            local t = obj.tris[i]
            local i1, i2, i3 = t.v1, t.v2, t.v3

            if obj.pValid[i1] and obj.pValid[i2] and obj.pValid[i3] then
                local wx1, wy1, wz1 = obj.cx[i1], obj.cy[i1], obj.cz[i1]
                local wx2, wy2, wz2 = obj.cx[i2], obj.cy[i2], obj.cz[i2]
                local wx3, wy3, wz3 = obj.cx[i3], obj.cy[i3], obj.cz[i3]

                -- 1. Normal calculation
                local nx = (wy2-wy1)*(wz3-wz1) - (wz2-wz1)*(wy3-wy1)
                local ny = (wz2-wz1)*(wx3-wx1) - (wx2-wx1)*(wz3-wz1)
                local nz = (wx2-wx1)*(wy3-wy1) - (wy2-wy1)*(wx3-wx1)

                -- 2. Backface Culling (Dot product with view vector)
                if nx*(wx1-cpx) + ny*(wy1-cpy) + nz*(wz1-cpz) < 0 then

                    -- 3. Modern Normalization (math.sqrt is faster than the hack here!)
                    local len = sqrt(nx*nx + ny*ny + nz*nz)
                    local invLen = 1.0 / len
                    nx, ny, nz = nx * invLen, ny * invLen, nz * invLen

                    -- 4. Directional Lighting (Normalized Light Vector: 0.37, 0.9, 0.2)
                    -- Clamp between 0.2 and 1.0 to prevent color bit-shift overflow!
                    local dot = nx*0.37 + ny*0.9 + nz*0.2
                    local light = max(0.2, min(1.0, dot))

                    -- 5. JIT-Friendly Color Packing
                    -- Using floor() ensures we don't pass floats to bit.lshift
                    local r = floor(t.r * light)
                    local g = floor(t.g * light)
                    local b = floor(t.b * light)
                    local shadedColor = 0xFF000000 + bit.lshift(r, 16) + bit.lshift(g, 8) + b

                    RasterizeTriangle(
                        obj.px[i1], obj.py[i1], obj.pz[i1],
                        obj.px[i2], obj.py[i2], obj.pz[i2],
                        obj.px[i3], obj.py[i3], obj.pz[i3],
                        shadedColor
                    )
                end
            end
        end
    end

    ScreenImage:replacePixels(ScreenBuffer)
    love.graphics.setBlendMode("replace")
    love.graphics.draw(ScreenImage, 0, 0)
    love.graphics.setBlendMode("alpha")
    love.graphics.print("THEOBROMIN | DATA-ORIENTED SOA | FPS: "..love.timer.getFPS(), 10, 10)
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

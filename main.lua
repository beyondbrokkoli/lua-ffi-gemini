local ffi = require("ffi")
local bit = require("bit")

-- ==========================================
-- 1. FFI DEFINITIONS & LOCALIZATIONS
-- ==========================================
ffi.cdef[[
    typedef struct { float x, y, z; } Vec3;
    typedef struct { Vec3 pos; Vec3 fw, rt, up; float yaw, pitch, fov; } Entity;
    typedef struct { int v1, v2, v3; uint32_t color; } Triangle;
]]

local floor, ceil, max, min = math.floor, math.ceil, math.max, math.min
local sqrt, cos, sin = math.sqrt, math.cos, math.sin

-- ==========================================
-- 2. GLOBAL STATE, BUFFERS & SOA
-- ==========================================
local CANVAS_W, CANVAS_H, HALF_W, HALF_H
local ScreenBuffer, ScreenPtr, ZBuffer, ScreenImage
local Cam = ffi.new("Entity")
local TriObjects = {}
local isMouseCaptured = false
local resizeTimer = 0
local pendingResize = false

-- SoA for Global Transforms
local MAX_OBJS = 2048
local Obj_X, Obj_Y, Obj_Z = ffi.new("float[?]", MAX_OBJS), ffi.new("float[?]", MAX_OBJS), ffi.new("float[?]", MAX_OBJS)
local Obj_Yaw, Obj_Pitch = ffi.new("float[?]", MAX_OBJS), ffi.new("float[?]", MAX_OBJS)
local Obj_Radius = ffi.new("float[?]", MAX_OBJS)
local Obj_FWX, Obj_FWY, Obj_FWZ = ffi.new("float[?]", MAX_OBJS), ffi.new("float[?]", MAX_OBJS), ffi.new("float[?]", MAX_OBJS)
local Obj_RTX, Obj_RTZ = ffi.new("float[?]", MAX_OBJS), ffi.new("float[?]", MAX_OBJS)
local Obj_UPX, Obj_UPY, Obj_UPZ = ffi.new("float[?]", MAX_OBJS), ffi.new("float[?]", MAX_OBJS), ffi.new("float[?]", MAX_OBJS)
local NumObjects = 0

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
local function CreateTriObject(x, y, z, vCount, tCount, radius)
    local id = NumObjects
    Obj_X[id], Obj_Y[id], Obj_Z[id] = x, y, z
    Obj_Yaw[id], Obj_Pitch[id] = 0, 0
    Obj_Radius[id] = radius or 50

    local obj = {
        id = id,
        vx = ffi.new("float[?]", vCount), vy = ffi.new("float[?]", vCount), vz = ffi.new("float[?]", vCount),
        cx = ffi.new("float[?]", vCount), cy = ffi.new("float[?]", vCount), cz = ffi.new("float[?]", vCount),
        px = ffi.new("float[?]", vCount), py = ffi.new("float[?]", vCount), pz = ffi.new("float[?]", vCount),
        pValid = ffi.new("bool[?]", vCount),
        tris = ffi.new("Triangle[?]", tCount),
        vCount = vCount, tCount = tCount
    }
    table.insert(TriObjects, obj)
    NumObjects = NumObjects + 1
    return obj
end

local function CreateTorus(cx, cy, cz, mainRadius, tubeRadius, segments, sides)
    local bound = mainRadius + tubeRadius
    local tor = CreateTriObject(cx, cy, cz, segments * sides, segments * sides * 2, bound)
    local vIdx, tIdx = 0, 0

    for i=0, segments-1 do
        local th = (i/segments) * math.pi * 2
        for j=0, sides-1 do
            local ph = (j/sides) * math.pi * 2
            tor.vx[vIdx] = (mainRadius + tubeRadius * cos(ph)) * cos(th)
            tor.vy[vIdx] = tubeRadius * sin(ph)
            tor.vz[vIdx] = (mainRadius + tubeRadius * cos(ph)) * sin(th)
            vIdx = vIdx + 1
        end
    end

    for i=0, segments-1 do
        local i_next = (i+1) % segments
        for j=0, sides-1 do
            local j_next = (j+1) % sides
            local a, b, c, d = i*sides+j, i_next*sides+j, i_next*sides+j_next, i*sides+j_next
            tor.tris[tIdx] = {v1=a, v2=c, v3=b, color=0xFFFFCC44}; tIdx = tIdx + 1
            tor.tris[tIdx] = {v1=a, v2=d, v3=c, color=0xFFCC8822}; tIdx = tIdx + 1
        end
    end
    return tor
end

local function UpdateCameraBasis(ent)
    local cy, sy = cos(ent.yaw), sin(ent.yaw)
    local cp, sp = cos(ent.pitch), sin(ent.pitch)
    ent.fw.x, ent.fw.y, ent.fw.z = sy * cp, sp, cy * cp
    ent.rt.x, ent.rt.z = cy, -sy
    ent.up.x = ent.fw.y * ent.rt.z
    ent.up.y = ent.fw.z * ent.rt.x - ent.fw.x * ent.rt.z
    ent.up.z = -ent.fw.y * ent.rt.x
end

local function BatchUpdateTransforms(dt)
    for i = 0, NumObjects - 1 do
        Obj_Yaw[i] = Obj_Yaw[i] + dt
        Obj_Pitch[i] = Obj_Pitch[i] + dt * 0.5

        local cy, sy = cos(Obj_Yaw[i]), sin(Obj_Yaw[i])
        local cp, sp = cos(Obj_Pitch[i]), sin(Obj_Pitch[i])

        local fwx, fwy, fwz = sy * cp, sp, cy * cp
        local rtx, rtz = cy, -sy

        Obj_FWX[i], Obj_FWY[i], Obj_FWZ[i] = fwx, fwy, fwz
        Obj_RTX[i], Obj_RTZ[i] = rtx, rtz

        Obj_UPX[i] = fwy * rtz
        Obj_UPY[i] = fwz * rtx - fwx * rtz
        Obj_UPZ[i] = -fwy * rtx
    end
end

-- ==========================================
-- 4. SCANLINE RASTERIZER
-- ==========================================
local function RasterizeTriangle(x1,y1,z1, x2,y2,z2, x3,y3,z3, shadedColor)
    if y1 > y2 then x1,x2 = x2,x1; y1,y2 = y2,y1; z1,z2 = z2,z1 end
    if y1 > y3 then x1,x3 = x3,x1; y1,y3 = y3,y1; z1,z3 = z3,z1 end
    if y2 > y3 then x2,x3 = x3,x2; y2,y3 = y3,y2; z2,z3 = z3,z2 end

    local total_height = y3 - y1
    if total_height <= 0 then return end

    local inv_total = 1.0 / total_height
    local y_start = max(0, ceil(y1))
    local y_end   = min(CANVAS_H - 1, floor(y3))

    local dy_upper = y2 - y1
    if dy_upper > 0 then
        local inv_upper = 1.0 / dy_upper
        local limit_y = min(y_end, floor(y2))

        for y = y_start, limit_y do
            local t_total = (y - y1) * inv_total
            local t_half  = (y - y1) * inv_upper

            local ax, az = x1 + (x3 - x1) * t_total, z1 + (z3 - z1) * t_total
            local bx, bz = x1 + (x2 - x1) * t_half,  z1 + (z2 - z1) * t_half

            if ax > bx then ax, bx = bx, ax; az, bz = bz, az end

            local row_width = bx - ax
            if row_width > 0 then
                local z_step = (bz - az) / row_width
                local start_x = max(0, ceil(ax))
                local end_x   = min(CANVAS_W - 1, floor(bx))
                local current_z = az + z_step * (start_x - ax)

                local row_ptr = ScreenPtr + (y * CANVAS_W)
                local z_ptr   = ZBuffer   + (y * CANVAS_W)

                for x = start_x, end_x do
                    if current_z < z_ptr[x] - 0.001 then
                        z_ptr[x] = current_z
                        row_ptr[x] = shadedColor
                    end
                    current_z = current_z + z_step
                end
            end
        end
    end

    local dy_lower = y3 - y2
    if dy_lower > 0 then
        local inv_lower = 1.0 / dy_lower
        local start_y = max(y_start, ceil(y2))

        for y = start_y, y_end do
            local t_total = (y - y1) * inv_total
            local t_half  = (y - y2) * inv_lower

            local ax, az = x1 + (x3 - x1) * t_total, z1 + (z3 - z1) * t_total
            local bx, bz = x2 + (x3 - x2) * t_half,  z2 + (z3 - z2) * t_half

            if ax > bx then ax, bx = bx, ax; az, bz = bz, az end

            local row_width = bx - ax
            if row_width > 0 then
                local z_step = (bz - az) / row_width
                local start_x = max(0, ceil(ax))
                local end_x   = min(CANVAS_W - 1, floor(bx))
                local current_z = az + z_step * (start_x - ax)

                local row_ptr = ScreenPtr + (y * CANVAS_W)
                local z_ptr   = ZBuffer   + (y * CANVAS_W)

                for x = start_x, end_x do
                    if current_z < z_ptr[x] - 0.001 then
                        z_ptr[x] = current_z
                        row_ptr[x] = shadedColor
                    end
                    current_z = current_z + z_step
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
    love.window.setMode(CANVAS_W, CANVAS_H, {resizable=true, vsync=0})

    Cam.pos = {x=0, y=0, z=0}

    -- Spawn 500 random Toruses for benchmark
    math.randomseed(os.time())
    for i = 1, 50 do
        local x = math.random(-800, 800)
        local y = math.random(-300, 300)
        local z = math.random(100, 1500)
        CreateTorus(x, y, z, 20, 8, 32, 16)
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

    local s = 200 * dt
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
    UpdateCameraBasis(Cam)

    BatchUpdateTransforms(dt)
end

function love.draw()
    if pendingResize then
        love.graphics.clear(0.05, 0.05, 0.05)
        love.graphics.print("REBUILDING SWAPCHAIN...", 20, 20)
        return
    end

    ffi.fill(ScreenPtr, CANVAS_W * CANVAS_H * 4, 0)
    ffi.fill(ZBuffer, CANVAS_W * CANVAS_H * 4, 0x7F)

    local cpx, cpy, cpz = Cam.pos.x, Cam.pos.y, Cam.pos.z
    local cfw_x, cfw_y, cfw_z = Cam.fw.x, Cam.fw.y, Cam.fw.z
    local crt_x, crt_y, crt_z = Cam.rt.x, Cam.rt.y, Cam.rt.z
    local cup_x, cup_y, cup_z = Cam.up.x, Cam.up.y, Cam.up.z
    local cfov = Cam.fov

    local objectsCulled = 0
    local objectsDrawn = 0

    for _, obj in ipairs(TriObjects) do
        local id = obj.id

        -- Frustum Culling (Z-Plane Check)
        local dx, dy, dz = Obj_X[id] - cpx, Obj_Y[id] - cpy, Obj_Z[id] - cpz
        local cz_center = dx*cfw_x + dy*cfw_y + dz*cfw_z

        if cz_center + Obj_Radius[id] > 0.5 then
            objectsDrawn = objectsDrawn + 1

            local rx, ry, rz = Obj_RTX[id], 0, Obj_RTZ[id]
            local ux, uy, uz = Obj_UPX[id], Obj_UPY[id], Obj_UPZ[id]
            local fx, fy, fz = Obj_FWX[id], Obj_FWY[id], Obj_FWZ[id]
            local ox, oy, oz = Obj_X[id], Obj_Y[id], Obj_Z[id]

            for i = 0, obj.vCount - 1 do
                local lx, ly, lz = obj.vx[i], obj.vy[i], obj.vz[i]

                local wx = ox + lx*rx + ly*ux + lz*fx
                local wy = oy + lx*ry + ly*uy + lz*fy
                local wz = oz + lx*rz + ly*uz + lz*fz

                obj.cx[i], obj.cy[i], obj.cz[i] = wx, wy, wz

                local vdx, vdy, vdz = wx - cpx, wy - cpy, wz - cpz
                local cz = vdx*cfw_x + vdy*cfw_y + vdz*cfw_z

                if cz < 0.1 then
                    obj.pValid[i] = false
                else
                    local f = cfov / cz
                    obj.px[i] = HALF_W + (vdx*crt_x + vdy*crt_y + vdz*crt_z) * f
                    obj.py[i] = HALF_H + (vdx*cup_x + vdy*cup_y + vdz*cup_z) * f
                    obj.pz[i] = cz
                    obj.pValid[i] = true
                end
            end

            for i = 0, obj.tCount - 1 do
                local t = obj.tris[i]
                local i1, i2, i3 = t.v1, t.v2, t.v3

                if obj.pValid[i1] and obj.pValid[i2] and obj.pValid[i3] then
                    local px1, py1 = obj.px[i1], obj.py[i1]
                    local px2, py2 = obj.px[i2], obj.py[i2]
                    local px3, py3 = obj.px[i3], obj.py[i3]

                    local winding = (px2 - px1) * (py3 - py1) - (py2 - py1) * (px3 - px1)

                    if winding < 0 then
                        local wx1, wy1, wz1 = obj.cx[i1], obj.cy[i1], obj.cz[i1]
                        local wx2, wy2, wz2 = obj.cx[i2], obj.cy[i2], obj.cz[i2]
                        local wx3, wy3, wz3 = obj.cx[i3], obj.cy[i3], obj.cz[i3]

                        local nx = (wy2-wy1)*(wz3-wz1) - (wz2-wz1)*(wy3-wy1)
                        local ny = (wz2-wz1)*(wx3-wx1) - (wx2-wx1)*(wz3-wz1)
                        local nz = (wx2-wx1)*(wy3-wy1) - (wy2-wy1)*(wx3-wx1)

                        local len = sqrt(nx*nx + ny*ny + nz*nz)
                        local lightDot = max(0.2, min(1.0, (nx*0.5 + ny*1.0 + nz*0.5) / len))

                        local tc = t.color
                        local r = bit.band(bit.rshift(tc, 16), 0xFF) * lightDot
                        local g = bit.band(bit.rshift(tc, 8), 0xFF) * lightDot
                        local b = bit.band(tc, 0xFF) * lightDot
                        local shadedColor = 0xFF000000 + bit.lshift(r, 16) + bit.lshift(g, 8) + b

                        RasterizeTriangle(
                            px1, py1, obj.pz[i1],
                            px2, py2, obj.pz[i2],
                            px3, py3, obj.pz[i3],
                            shadedColor
                        )
                    end
                end
            end
        else
            objectsCulled = objectsCulled + 1
        end
    end

    ScreenImage:replacePixels(ScreenBuffer)
    love.graphics.setBlendMode("replace")
    love.graphics.draw(ScreenImage, 0, 0)
    love.graphics.setBlendMode("alpha")

    love.graphics.print("ULTIMA PLATIN | FPS: "..love.timer.getFPS(), 10, 10)
    love.graphics.print(string.format("Drawn: %d | Culled: %d", objectsDrawn, objectsCulled), 10, 30)
    local status = isMouseCaptured and "MOUSE LOCKED (J to unlock)" or "MOUSE FREE (J to lock)"
    love.graphics.print(status, 10, 50)
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

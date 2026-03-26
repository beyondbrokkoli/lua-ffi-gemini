-- main.lua
local ffi = require("ffi")
local bit = require("bit")
local function lerp(a, b, t) return a + (b - a) * t end
local function lerpAngle(a, b, t)
    local diff = (b - a + math.pi) % (math.pi * 2) - math.pi
    return a + diff * t
end

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
local isFullscreen = false
-- SoA for Global Transforms
local MAX_OBJS = 2048
local Obj_X, Obj_Y, Obj_Z = ffi.new("float[?]", MAX_OBJS), ffi.new("float[?]", MAX_OBJS), ffi.new("float[?]", MAX_OBJS)
local Obj_Yaw, Obj_Pitch = ffi.new("float[?]", MAX_OBJS), ffi.new("float[?]", MAX_OBJS)
local Obj_Radius = ffi.new("float[?]", MAX_OBJS)
local Obj_FWX, Obj_FWY, Obj_FWZ = ffi.new("float[?]", MAX_OBJS), ffi.new("float[?]", MAX_OBJS), ffi.new("float[?]", MAX_OBJS)
local Obj_RTX, Obj_RTZ = ffi.new("float[?]", MAX_OBJS), ffi.new("float[?]", MAX_OBJS)
local Obj_UPX, Obj_UPY, Obj_UPZ = ffi.new("float[?]", MAX_OBJS), ffi.new("float[?]", MAX_OBJS), ffi.new("float[?]", MAX_OBJS)
local NumObjects = 0
-- SoA for unique speeds
local Obj_VelX, Obj_VelY, Obj_VelZ = ffi.new("float[?]", MAX_OBJS), ffi.new("float[?]", MAX_OBJS), ffi.new("float[?]", MAX_OBJS)
local Obj_RotSpeedYaw, Obj_RotSpeedPitch = ffi.new("float[?]", MAX_OBJS), ffi.new("float[?]", MAX_OBJS)
-- Presentation State
local MAX_SLIDES = 100
local TargetSlide, NumSlides = 0, 0
local presentationMode = true
local isSettled = false

local Slide_X = ffi.new("float[?]", MAX_SLIDES)
local Slide_Y = ffi.new("float[?]", MAX_SLIDES)
local Slide_Z = ffi.new("float[?]", MAX_SLIDES)
-- Active transition targets
local tX, tY, tZ, tYaw, tPitch = 0, 0, 0, 0, 0

local Way_X = ffi.new("float[?]", MAX_SLIDES)
local Way_Y = ffi.new("float[?]", MAX_SLIDES)
local Way_Z = ffi.new("float[?]", MAX_SLIDES)
local Way_Yaw = ffi.new("float[?]", MAX_SLIDES)
local Way_Pitch = ffi.new("float[?]", MAX_SLIDES)

local lerpT, arrivalTimer = 0, 0
local startX, startY, startZ = 0, 0, 0
local startYaw, startPitch = 0, 0
local lastFreeX, lastFreeY, lastFreeZ = 0, 0, 0
local lastFreeYaw, lastFreePitch = 0, 0
local contentAlpha, notificationAlpha = 0, 0

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

local function updateTargetSide()
    local fx, fy, fz = Way_X[TargetSlide], Way_Y[TargetSlide], Way_Z[TargetSlide]
    local sx, sy, sz = Slide_X[TargetSlide], Slide_Y[TargetSlide], Slide_Z[TargetSlide]

    -- Full 3D reflection: b = s - (f - s) => 2s - f
    local bx, by, bz = 2*sx - fx, 2*sy - fy, 2*sz - fz

    local dF = (fx - Cam.pos.x)^2 + (fy - Cam.pos.y)^2 + (fz - Cam.pos.z)^2
    local dB = (bx - Cam.pos.x)^2 + (by - Cam.pos.y)^2 + (bz - Cam.pos.z)^2

    if dF <= dB then
        tX, tY, tZ, tYaw = fx, fy, fz, Way_Yaw[TargetSlide]
        tPitch = Way_Pitch[TargetSlide]
    else
        tX, tY, tZ, tYaw = bx, by, bz, Way_Yaw[TargetSlide] + math.pi
        -- Usually pitch remains same for 'back' view unless you want to flip upside down
        tPitch = Way_Pitch[TargetSlide]
    end
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
        -- 1. Apply individual movement
        Obj_X[i] = Obj_X[i] + Obj_VelX[i] * dt
        Obj_Y[i] = Obj_Y[i] + Obj_VelY[i] * dt
        Obj_Z[i] = Obj_Z[i] + Obj_VelZ[i] * dt

        -- 2. Apply individual rotation
        Obj_Yaw[i] = Obj_Yaw[i] + Obj_RotSpeedYaw[i] * dt
        Obj_Pitch[i] = Obj_Pitch[i] + Obj_RotSpeedPitch[i] * dt

        -- 3. Calculate transformation matrix components
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
    -- local w, h = love.window.getDesktopDimensions(1)
    local w, h = 800, 800
    love.window.setMode(w, h, {fullscreen=false, vsync=1, resizable=true})
    ReinitBuffers(w, h)
    love.mouse.setRelativeMode(isMouseCaptured)
    Cam.pos = {x=0, y=0, z=0}

    -- Bundle API for slides.lua
    local slideAPI = {
        CreateTriObject = CreateTriObject,
        Obj_Yaw = Obj_Yaw,
        Way_X = Way_X, Way_Y = Way_Y, Way_Z = Way_Z,
        Way_Yaw = Way_Yaw, Way_Pitch = Way_Pitch,
        Cam = Cam, CANVAS_W = CANVAS_W, CANVAS_H = CANVAS_H,

        Slide_X = Slide_X, Slide_Y = Slide_Y, Slide_Z = Slide_Z
    }

    NumSlides = require("slides").build(slideAPI, NumSlides)
    updateTargetSide()
end

function love.update(dt)
    if pendingResize then
        resizeTimer = resizeTimer - dt
        if resizeTimer <= 0 then ReinitBuffers(love.graphics.getWidth(), love.graphics.getHeight()); pendingResize = false end
        return
    end

    if presentationMode and NumSlides > 0 then
        lerpT = min(1.0, lerpT + dt * 2)
        local easeT = 1 - (1 - lerpT) * (1 - lerpT)

        if lerpT < 1.0 then
            arrivalTimer = 0
            isSettled = false
            contentAlpha = max(0, 1 - (lerpT / 0.1))
            notificationAlpha = (lerpT > 0.9) and ((lerpT - 0.9) / 0.1) or 0

            Cam.pos.x = lerp(startX, tX, easeT)
            Cam.pos.y = lerp(startY, tY, easeT)
            Cam.pos.z = lerp(startZ, tZ, easeT)
            Cam.yaw   = lerpAngle(startYaw, tYaw, easeT)
            Cam.pitch = lerpAngle(startPitch, tPitch, easeT)
        else
            Cam.pos.x, Cam.pos.y, Cam.pos.z = tX, tY, tZ
            Cam.yaw, Cam.pitch = tYaw, tPitch

            isSettled = true
            arrivalTimer = arrivalTimer + dt
            notificationAlpha = (arrivalTimer < 1.0) and 1 or max(0, 1 - (arrivalTimer - 1.0) / 0.5)
            contentAlpha = min(1, arrivalTimer / 0.5)
        end
    else
        local s = 2000 * dt
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
    end

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

        -- Frustum Culling (Sphere vs 5 Camera Planes)
        local dx, dy, dz = Obj_X[id] - cpx, Obj_Y[id] - cpy, Obj_Z[id] - cpz
        local cz_center = dx*cfw_x + dy*cfw_y + dz*cfw_z
        local radius = Obj_Radius[id]

        -- 1. Near Plane Check
        if cz_center + radius > 0.1 then

            -- Transform center to Camera X and Y space
            local cx_center = dx*crt_x + dy*crt_y + dz*crt_z
            local cy_center = dx*cup_x + dy*cup_y + dz*cup_z

            -- Calculate dynamic bounds based on depth and FOV
            local depth = max(0.1, cz_center)
            local boundX = (HALF_W * depth / cfov) + radius
            local boundY = (HALF_H * depth / cfov) + radius

            -- 2. Left/Right & Top/Bottom Plane Checks
            if math.abs(cx_center) <= boundX and math.abs(cy_center) <= boundY then
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
    if key == "p" then
        if not presentationMode then
            lastFreeX, lastFreeY, lastFreeZ = Cam.pos.x, Cam.pos.y, Cam.pos.z
            lastFreeYaw, lastFreePitch = Cam.yaw, Cam.pitch
            startX, startY, startZ = Cam.pos.x, Cam.pos.y, Cam.pos.z
            startYaw, startPitch = Cam.yaw, Cam.pitch
            lerpT, arrivalTimer, contentAlpha, notificationAlpha = 0, 0, 0, 0
            updateTargetSide()
            presentationMode = true
        end
    elseif key == "i" then
        presentationMode = false
    elseif key == "u" then
        presentationMode = false
        Cam.pos.x, Cam.pos.y, Cam.pos.z = lastFreeX, lastFreeY, lastFreeZ
        Cam.yaw, Cam.pitch = lastFreeYaw, lastFreePitch
    elseif presentationMode and (key == "space" or key == "backspace") then
        startX, startY, startZ = Cam.pos.x, Cam.pos.y, Cam.pos.z
        startYaw, startPitch = Cam.yaw, Cam.pitch
        lerpT, arrivalTimer, contentAlpha = 0, 0, 0
        TargetSlide = (key == "space") and ((TargetSlide + 1) % NumSlides) or ((TargetSlide - 1 + NumSlides) % NumSlides)
         updateTargetSide()
    elseif key == "j" and not presentationMode then
        isMouseCaptured = not isMouseCaptured
        love.mouse.setRelativeMode(isMouseCaptured)
    elseif key == "escape" then
        love.event.quit()
    elseif key == "f" then
        isFullscreen = not isFullscreen
        love.window.setFullscreen(isFullscreen)
        pendingResize = true
    end
end

function love.mousemoved(x, y, dx, dy)
    if isMouseCaptured then
        local sensitivity = 0.002
        Cam.yaw = Cam.yaw + (dx * sensitivity)
        Cam.pitch = Cam.pitch + (dy * sensitivity)
    end
end

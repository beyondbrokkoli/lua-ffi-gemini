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
local SlidesInternal = {
    build = function(api, startSlideCount)
        local NumSlides = startSlideCount
        local manifest = {}

        local function BuildHalf(w, h, thickness, color, offX, offY)
            local slide = api.CreateTriObject(0, 0, 0, 8, 12, max(w, h))
            local hw, hh, ht = w/2, h/2, thickness/2
            local verts = {
                {-hw+offX, -hh+offY, -ht}, {hw+offX, -hh+offY, -ht},
                {hw+offX, hh+offY, -ht}, {-hw+offX, hh+offY, -ht},
                {-hw+offX, -hh+offY, ht}, {hw+offX, -hh+offY, ht},
                {hw+offX, hh+offY, ht}, {-hw+offX, hh+offY, ht}
            }
            for i, v in ipairs(verts) do slide.vx[i-1], slide.vy[i-1], slide.vz[i-1] = v[1], v[2], v[3] end
            local indices = { 0,2,1, 0,3,2, 4,5,6, 4,6,7, 0,1,5, 0,5,4, 1,2,6, 1,6,5, 2,3,7, 2,7,6, 3,0,4, 3,4,7 }
            for i=0, 11 do slide.tris[i] = {v1=indices[i*3+1], v2=indices[i*3+2], v3=indices[i*3+3], color=color} end
            return slide
        end

        -- Helper to unify manifest storage and math
        local function RegisterSlide(sIdx, x, y, z, w, h, angle)
            api.Slide_X[sIdx], api.Slide_Y[sIdx], api.Slide_Z[sIdx] = x, y, z
            -- Pre-calculate the Normal Vector (Forward direction of the slide)
            -- This ensures the camera knows exactly which way is 'out'
            manifest[sIdx] = {
                x = x, y = y, z = z,
                w = w, h = h,
                angle = angle,
                nx = math.sin(angle),
                nz = math.cos(angle)
            }
        end

        local function CreateAutoSlide(w, h, thickness, color)
            local sIdx = NumSlides
            local angle = sIdx * (math.pi / 2)
            local radius = 1500
            local x, y, z = math.cos(angle) * radius, math.sin(angle) * radius, sIdx * 3000

            local slide = BuildHalf(w, h, thickness, color, 0, 0)
            api.Obj_X[slide.id], api.Obj_Y[slide.id], api.Obj_Z[slide.id] = x, y, z
            api.Obj_Yaw[slide.id] = angle

            RegisterSlide(sIdx, x, y, z, w, h, angle)
            NumSlides = NumSlides + 1
        end

        local function CreateAutoSlideHorizontalSplit(w, h, thickness, color1, color2)
            local sIdx = NumSlides
            local angle = sIdx * (math.pi / 2)
            local x, y, z = math.cos(angle) * 1500, math.sin(angle) * 1500, sIdx * 3000

            local top = BuildHalf(w, h/2 - 10, thickness, color1, 0, -h/4)
            local bot = BuildHalf(w, h/2 - 10, thickness, color2, 0, h/4)
            api.Obj_X[top.id], api.Obj_Y[top.id], api.Obj_Z[top.id] = x, y, z
            api.Obj_X[bot.id], api.Obj_Y[bot.id], api.Obj_Z[bot.id] = x, y, z
            api.Obj_Yaw[top.id], api.Obj_Yaw[bot.id] = angle, angle

            RegisterSlide(sIdx, x, y, z, w, h, angle)
            NumSlides = NumSlides + 1
        end

        local function CreateAutoSlideQuad(w, h, thickness, c1, c2, c3, c4)
            local sIdx = NumSlides
            local angle = sIdx * (math.pi / 2)
            local x, y, z = math.cos(angle) * 1500, math.sin(angle) * 1500, sIdx * 3000

            local qw, qh = w/2 - 10, h/2 - 10
            local slides = {
                BuildHalf(qw, qh, thickness, c1, -w/4, -h/4),
                BuildHalf(qw, qh, thickness, c2,  w/4, -h/4),
                BuildHalf(qw, qh, thickness, c3, -w/4,  h/4),
                BuildHalf(qw, qh, thickness, c4,  w/4,  h/4)
            }
            for _, s in ipairs(slides) do
                api.Obj_X[s.id], api.Obj_Y[s.id], api.Obj_Z[s.id] = x, y, z
                api.Obj_Yaw[s.id] = angle
            end

            RegisterSlide(sIdx, x, y, z, w, h, angle)
            NumSlides = NumSlides + 1
        end

        -- Build the sequence
        CreateAutoSlide(1600, 900, 40, 0xFFFFD700)
        CreateAutoSlideHorizontalSplit(1600, 900, 20, 0xFF44CCFF, 0xFFCC44FF)
        CreateAutoSlideQuad(1800, 1000, 60, 0xFF2E8B57, 0xFF8B0000, 0xFFDAA520, 0xFFFFFFFF)
        CreateAutoSlide(3200, 1800, 10, 0xFFFFFFFF)

        return NumSlides, manifest
    end,

    CrystalCompanion = function(api, manifest, numSlides, crystalsPerSlide)
        local colors = {0xFFFFCC44, 0xFF44CCFF, 0xFFCC44FF, 0xFFFFFFFF}
        for i = 0, numSlides - 1 do
            local s = manifest[i]

            -- Pre-calculate basis vectors for the slide's rotation
            -- nx is sin(angle), nz is cos(angle)
            local rightX, rightZ = s.nz, -s.nx
            local fwdX, fwdZ = s.nx, s.nz

            for j = 1, crystalsPerSlide do
                -- 1. Generate LOCAL offsets (relative to the slide face)
                local localX = (math.random() - 0.5) * (s.w * 1.5)
                local localY = (math.random() - 0.5) * (s.h * 1.5)
                local localZ = (math.random() - 0.5) * 800

                -- 2. Transform Local -> World using the slide's orientation
                -- World = Center + (Right * localX) + (Up * localY) + (Forward * localZ)
                local x = s.x + (rightX * localX) + (fwdX * localZ)
                local y = s.y + localY
                local z = s.z + (rightZ * localX) + (fwdZ * localZ)

                local id = api.NumObjects()
                local chosenColor = colors[math.random(#colors)]

                api.CreateTorus(x, y, z, 25, 10, 8, 3, chosenColor)

                -- Lively rotation distribution
                api.Obj_Yaw[id] = math.random() * math.pi * 2
                api.Obj_Pitch[id] = math.random() * math.pi * 2

                -- Movement and tumble
                api.Obj_VelX[id] = (math.random() - 0.5) * 60
                api.Obj_VelY[id] = (math.random() - 0.5) * 60
                api.Obj_VelZ[id] = (math.random() - 0.5) * 60
                api.Obj_RotSpeedYaw[id] = (math.random() - 0.5) * 5
                api.Obj_RotSpeedPitch[id] = (math.random() - 0.5) * 5
            end
        end
    end
}

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

local SlideTitles = {} -- Stores {ptr, w, h} for each slide
local TargetSlide, NumSlides = 0, 0
local DisplaySlide = 0 -- Add this to track what we actually see

local function ReinitBuffers(w, h)
    CANVAS_W, CANVAS_H = w, h
    HALF_W, HALF_H = w * 0.5, h * 0.5
    ScreenBuffer = love.image.newImageData(CANVAS_W, CANVAS_H)
    ScreenImage = love.graphics.newImage(ScreenBuffer)
    ScreenPtr = ffi.cast("uint32_t*", ScreenBuffer:getPointer())
    ZBuffer = ffi.new("float[?]", CANVAS_W * CANVAS_H)
    Cam.fov = (CANVAS_W / 800) * 600
end
local function ReinitFontCache()
    -- Cache Slide Titles
    local font = love.graphics.getFont()
    SlideTitles = {}
    for i = 0, NumSlides - 1 do
        local text = "SLIDE " .. (i + 1)
        local tw, th = font:getWidth(text), font:getHeight()

        -- Draw to temporary canvas
        local canvas = love.graphics.newCanvas(tw, th)
        love.graphics.setCanvas(canvas)
        love.graphics.clear(0,0,0,0)
        love.graphics.print(text, 0, 0)
        love.graphics.setCanvas()

        -- Store the FFI pointer and dimensions
        local imgData = canvas:newImageData()
        SlideTitles[i] = {
            ptr = ffi.cast("uint32_t*", imgData:getPointer()),
            w = tw,
            h = th,
            _keepAlive = imgData -- Prevent GC
        }
    end
end
local function BlitUI(titleObj, targetX, targetY, alpha)
    if not titleObj or alpha <= 0 then return end
    local ptr = titleObj.ptr
    local tw, th = titleObj.w, titleObj.h
    local opacity = math.floor(alpha * 255)

    for y = 0, th - 1 do
        local sy = targetY + y
        if sy >= 0 and sy < CANVAS_H then
            local screenOffset = sy * CANVAS_W
            local bufferOffset = y * tw
            for x = 0, tw - 1 do
                local sx = targetX + x
                if sx >= 0 and sx < CANVAS_W then
                    local px = ptr[bufferOffset + x]
                    -- Simple alpha check (check the high byte)
                    if bit.rshift(px, 24) > 0 then
                        -- Optional: Apply global alpha to the pixel here if needed
                        ScreenPtr[screenOffset + sx] = px
                    end
                end
            end
        end
    end
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
local function GetViewDistance(w, h)
    local distScale = math.max(h, w * (CANVAS_H / CANVAS_W))
    return (distScale * Cam.fov) / CANVAS_H + 200
end

local function updateTargetSide()
    local s = manifest[TargetSlide]
    if not s then return end

    -- View distance based on slide size
    local dist = GetViewDistance(s.w, s.h) * 1.5
    -- Change this in updateTargetSide for a test:
    -- local dist = (math.max(s.w, s.h) * 0.8) + 500
    -- Calculate Front (F) and Back (B) positions using the stored normals
    local fx, fy, fz = s.x + s.nx * dist, s.y, s.z + s.nz * dist
    local bx, by, bz = s.x - s.nx * dist, s.y, s.z - s.nz * dist

    -- Determine which side the camera is currently closer to
    local dF = (fx - Cam.pos.x)^2 + (fy - Cam.pos.y)^2 + (fz - Cam.pos.z)^2
    local dB = (bx - Cam.pos.x)^2 + (by - Cam.pos.y)^2 + (bz - Cam.pos.z)^2

    if dF <= dB then
        tX, tY, tZ = fx, fy, fz
        -- Face the slide center from the front
        tYaw = math.atan2(s.x - fx, s.z - fz)
    else
        tX, tY, tZ = bx, by, bz
        -- Face the slide center from the back
        tYaw = math.atan2(s.x - bx, s.z - bz)
    end

    tPitch = s.pitch or 0
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
local globalTimer = 0
local function CreateTorus(cx, cy, cz, mainRadius, tubeRadius, segments, sides, baseColor)
    baseColor = baseColor or 0xFFFFCC44 -- Default Gold
    local bound = mainRadius + tubeRadius
    local tor = CreateTriObject(cx, cy, cz, segments * sides, segments * sides * 2, bound)

    -- Calculate a "Shadow" version of the color (roughly 60% brightness)
    local r = bit.band(bit.rshift(baseColor, 16), 0xFF)
    local g = bit.band(bit.rshift(baseColor, 8), 0xFF)
    local b = bit.band(baseColor, 0xFF)
    local altColor = 0xFF000000
                   + bit.lshift(floor(r * 0.6), 16)
                   + bit.lshift(floor(g * 0.6), 8)
                   + floor(b * 0.6)

    local vIdx, tIdx = 0, 0
    -- Keeping the existing vertex loop
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

            -- Use the grid index to alternate colors
            local useAlt = (i + j) % 2 == 0
            local col = useAlt and baseColor or altColor

            tor.tris[tIdx] = {v1=a, v2=c, v3=b, color=col}; tIdx = tIdx + 1
            tor.tris[tIdx] = {v1=a, v2=d, v3=c, color=col}; tIdx = tIdx + 1
        end
    end
    return tor
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
    love.window.setMode(800, 800, {
        fullscreen = true,
        vsync = 1
    })
    local windowW, windowH = love.graphics.getDimensions()
    -- Your existing buffer initialization
    ReinitBuffers(windowW, windowH)

    love.mouse.setRelativeMode(isMouseCaptured)

    -- Define the slideAPI
    local slideAPI = {
        CreateTriObject = CreateTriObject,
        CreateTorus = CreateTorus,
        Obj_Yaw = Obj_Yaw,
        Obj_Pitch = Obj_Pitch,
        Obj_X = Obj_X, Obj_Y = Obj_Y, Obj_Z = Obj_Z,
        Obj_VelX = Obj_VelX, Obj_VelY = Obj_VelY, Obj_VelZ = Obj_VelZ,
        Obj_RotSpeedYaw = Obj_RotSpeedYaw,
        Obj_RotSpeedPitch = Obj_RotSpeedPitch,
        Slide_X = Slide_X, Slide_Y = Slide_Y, Slide_Z = Slide_Z,
        NumObjects = function() return NumObjects end
    }

    NumSlides, manifest = SlidesInternal.build(slideAPI, 0)
    SlidesInternal.CrystalCompanion(slideAPI, manifest, NumSlides, 125)
    -- 1. Initialize State
    TargetSlide = 0
    DisplaySlide = 0
    lerpT = 1.0       -- Start at 1.0 so we don't lerp on frame 1
    arrivalTimer = 0
    isSettled = true

    -- 2. Force Cam to Origin briefly to ensure updateTargetSide picks a side
    Cam.pos.x, Cam.pos.y, Cam.pos.z = 0, 0, 0
    updateTargetSide()

    -- 3. Snap Camera and Lerp-Anchors to the result
    Cam.pos.x, Cam.pos.y, Cam.pos.z = tX, tY, tZ
    Cam.yaw, Cam.pitch = tYaw, tPitch
    startX, startY, startZ = tX, tY, tZ
    startYaw, startPitch = tYaw, tPitch

    -- 4. Final Sync
    UpdateCameraBasis(Cam)
    ReinitFontCache()
end

function love.update(dt)
    if pendingResize then
        resizeTimer = resizeTimer - dt
        if resizeTimer <= 0 then ReinitBuffers(love.graphics.getWidth(), love.graphics.getHeight()); pendingResize = false; ReinitFontCache() end
        return
    end

    if presentationMode and NumSlides > 0 then
        lerpT = min(1.0, lerpT + dt * 1) -- 2 was fast mode
        local easeT = 1 - (1 - lerpT) * (1 - lerpT)
        if lerpT < 1.0 then
            arrivalTimer = 0
            isSettled = false
            contentAlpha = max(0, 1 - (lerpT / 0.1)) -- Fades out in first 10% of flight

            -- SWAP INDEX HERE: When alpha hits 0, switch the text
            if contentAlpha <= 0 then
                DisplaySlide = TargetSlide
            end

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
    -- Basic Frame Limiter
    local min_dt = 1 / 90
    if dt < min_dt then
        love.timer.sleep(min_dt - dt)
    end
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
    -- ... inside love.draw after the TriObjects loop ...
    if presentationMode then
        local title = SlideTitles[DisplaySlide]
        -- Center it at the bottom
        local tx = math.floor(HALF_W - title.w / 2)
        local ty = math.floor(CANVAS_H - 100)
        BlitUI(title, tx, ty, contentAlpha)
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
    if not presentationMode and (key == "p" or key == "space") then
        lastFreeX, lastFreeY, lastFreeZ = Cam.pos.x, Cam.pos.y, Cam.pos.z
        lastFreeYaw, lastFreePitch = Cam.yaw, Cam.pitch
        startX, startY, startZ = Cam.pos.x, Cam.pos.y, Cam.pos.z
        startYaw, startPitch = Cam.yaw, Cam.pitch
        lerpT, arrivalTimer, contentAlpha, notificationAlpha = 0, 0, 0, 0
        updateTargetSide()
        presentationMode = true
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

        -- Change TargetSlide, but DON'T change DisplaySlide yet!
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

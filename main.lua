require("sys_memory")
local ffi = require("ffi")
local Engine = require("engine")
local SlidesInternal = require("slides_internal")
local Physics = require("sys_physics")
local Renderer = require("sys_renderer")
local Factory = require("sys_factory")
local SysText = require("sys_text")
-- The new Bolwark
local floor, ceil, max, min, abs = math.floor, math.ceil, math.max, math.min, math.abs
local random, sqrt, cos, sin, pi, atan2 = math.random, math.sqrt, math.cos, math.sin, math.pi, math.atan2

isFullscreen = true
isMouseCaptured = false
snapshotBaked = false
local PRESENTATION_ZOOM = 1.0
local scanlineCanvas = nil

local function GetScanlines()
    if not scanlineCanvas then
        scanlineCanvas = love.graphics.newCanvas(love.graphics.getWidth(), love.graphics.getHeight())
        love.graphics.setCanvas(scanlineCanvas)
        love.graphics.setColor(0, 0, 0, 0.3)
        for y = 0, love.graphics.getHeight(), 3 do
            love.graphics.rectangle("fill", 0, y, love.graphics.getWidth(), 1)
        end
        love.graphics.setCanvas()
    end
    return scanlineCanvas
end
local function lerp(a, b, t) return a + (b - a) * t end
local function lerpAngle(a, b, t)
    local diff = (b - a + pi) % (pi * 2) - pi
    return a + diff * t
end
local slideAPI = {
    CreateTriObject = Factory.CreateTriObject, CreateTorus = Factory.CreateTorus,
    Obj_VertStart = Obj_VertStart, Obj_VertCount = Obj_VertCount,
    Obj_TriStart = Obj_TriStart, Obj_TriCount = Obj_TriCount,
    Vert_LX = Vert_LX, Vert_LY = Vert_LY, Vert_LZ = Vert_LZ,
    Tri_V1 = Tri_V1, Tri_V2 = Tri_V2, Tri_V3 = Tri_V3, Tri_Color = Tri_Color,
    Obj_X = Obj_X, Obj_Y = Obj_Y, Obj_Z = Obj_Z,
    Obj_Yaw = Obj_Yaw, Obj_Pitch = Obj_Pitch, Obj_Radius = Obj_Radius,
    Obj_VelX = Obj_VelX, Obj_VelY = Obj_VelY, Obj_VelZ = Obj_VelZ,
    Obj_RotSpeedYaw = Obj_RotSpeedYaw, Obj_RotSpeedPitch = Obj_RotSpeedPitch,
    Obj_HomeIdx = Obj_HomeIdx,
    Box_X = Box_X, Box_Y = Box_Y, Box_Z = Box_Z,
    Box_HW = Box_HW, Box_HH = Box_HH, Box_HT = Box_HT,
    Box_CosA = Box_CosA, Box_SinA = Box_SinA,
    Box_NX = Box_NX, Box_NY = Box_NY, Box_NZ = Box_NZ,
    Box_FWX = Box_FWX, Box_FWY = Box_FWY, Box_FWZ = Box_FWZ,
    Box_RTX = Box_RTX, Box_RTY = Box_RTY, Box_RTZ = Box_RTZ,
    Box_UPX = Box_UPX, Box_UPY = Box_UPY, Box_UPZ = Box_UPZ,
    Sphere_X = Sphere_X, Sphere_Y = Sphere_Y, Sphere_Z = Sphere_Z, Sphere_RSq = Sphere_RSq,
    Obj_FWX = Obj_FWX, Obj_FWY = Obj_FWY, Obj_FWZ = Obj_FWZ,
    Obj_RTX = Obj_RTX, Obj_RTY = Obj_RTY, Obj_RTZ = Obj_RTZ,
    Obj_UPX = Obj_UPX, Obj_UPY = Obj_UPY, Obj_UPZ = Obj_UPZ,
    NumObjects = function() return NumObjects end
}
local function UpdateCameraBasis()
    local cy, sy = cos(Cam_Yaw), sin(Cam_Yaw)
    local cp, sp = cos(Cam_Pitch), sin(Cam_Pitch)
    Cam_FWX, Cam_FWY, Cam_FWZ = sy * cp, sp, cy * cp
    Cam_RTX, Cam_RTZ = cy, -sy
    Cam_UPX = Cam_FWY * Cam_RTZ
    Cam_UPY = Cam_FWZ * Cam_RTX - Cam_FWX * Cam_RTZ
    Cam_UPZ = -Cam_FWY * Cam_RTX
end
local function BuildCollisionPools()
    Pool_SlideCollider_Count = 0
    Pool_DeepSpace_Count = 0
    for i = 0, Pool_Collider_Count - 1 do
        local id = Pool_Collider[i]
        if Obj_HomeIdx[id] >= 0 then
            Pool_SlideCollider[Pool_SlideCollider_Count] = id
            Pool_SlideCollider_Count = Pool_SlideCollider_Count + 1
        else
            Pool_DeepSpace[Pool_DeepSpace_Count] = id
            Pool_DeepSpace_Count = Pool_DeepSpace_Count + 1
        end
    end
end
local function updateTargetSide()
    local s = manifest[TargetSlide]
    if not s then return end
    local nx = Box_NX[TargetSlide] or 0
    local ny = Box_NY[TargetSlide] or 0
    local nz = Box_NZ[TargetSlide] or 1
    local distScale = math.max(s.h, s.w * (CANVAS_H / CANVAS_W))
    -- Padding depends purely on TargetState
    local pad = (TargetState == STATE_ZEN) and 0 or 200
    local dist = (distScale * Cam_FOV) / CANVAS_H * PRESENTATION_ZOOM + pad

    local fx, fy, fz = s.x + nx * dist, s.y + ny * dist, s.z + nz * dist
    local bx, by, bz = s.x - nx * dist, s.y - ny * dist, s.z - nz * dist
    local dF = (fx - Cam_X)^2 + (fy - Cam_Y)^2 + (fz - Cam_Z)^2
    local dB = (bx - Cam_X)^2 + (by - Cam_Y)^2 + (bz - Cam_Z)^2
    local dx, dy, dz
    if dF <= dB then
        tX, tY, tZ = fx, fy, fz
        dx, dy, dz = s.x - fx, s.y - fy, s.z - fz
    else
        tX, tY, tZ = bx, by, bz
        dx, dy, dz = s.x - bx, s.y - by, s.z - bz
    end
    tYaw = math.atan2(dx, dz)
    tPitch = math.atan2(dy, math.sqrt(dx*dx + dz*dz))
end

local function TriggerContinuousFlight()
    updateTargetSide()
    startX, startY, startZ = Cam_X, Cam_Y, Cam_Z
    startYaw, startPitch = Cam_Yaw, Cam_Pitch
    lerpT = 0
    EngineState = STATE_CINEMATIC
    snapshotBaked = false
end

function love.load()
    -- Demand High-DPI (Retina/4K) pixels from the OS, and use Desktop Fullscreen
    -- love.window.setMode(0, 0, {
        -- fullscreen = true,
        -- fullscreentype = "desktop",
        -- highdpi = true,
        -- vsync = 1
    -- })
    ReinitBuffers()
    love.mouse.setRelativeMode(isMouseCaptured)
    Font_UI = love.graphics.newFont(14)

    local sceneState = Engine.Boot(slideAPI, "scene.json")
    if sceneState then
        manifest, NumSlides = sceneState.manifest, sceneState.NumSlides
        local b = sceneState.bounds
        B_MinX, B_MinY, B_MinZ, B_MaxX, B_MaxY, B_MaxZ = b.minX, b.minY, b.minZ, b.maxX, b.maxY, b.maxZ
        TargetSlide = 0
        updateTargetSide()
        Cam_X, Cam_Y, Cam_Z, Cam_Yaw, Cam_Pitch = tX, tY, tZ, tYaw, tPitch
        startX, startY, startZ, startYaw, startPitch = tX, tY, tZ, tYaw, tPitch
        lastFreeX, lastFreeY, lastFreeZ, lastFreeYaw, lastFreePitch = Cam_X, Cam_Y, Cam_Z, Cam_Yaw, Cam_Pitch

        SysText.InitSlideTextCache()
        -- Boot the new Bolwark
        -- SlidesInternal.SpawnDeepSpaceAsteroids(slideAPI, 60)
        SlidesInternal.SpawnSpaceAsteroids(slideAPI, 856)
        -- SlidesInternal.SpawnHeroDonut(slideAPI, 0)
        -- SlidesInternal.SpawnSatelliteRing(slideAPI, 1, 16)
        -- SlidesInternal.CrystalCompanion(slideAPI, 3, 30)
        -- SlidesInternal.SpawnGeometricStorm(slideAPI, 3, 45)
        -- SlidesInternal.SpawnParticleAccelerator(slideAPI, 4, 80)
        -- SlidesInternal.SpawnSatelliteRing(slideAPI, 8, 24)
        -- SlidesInternal.SpawnChaosCluster(slideAPI, 9, 50)
        BuildCollisionPools()
        UpdateCameraBasis()
        Renderer.BakeStaticLighting()
    end
    scanlineCanvas = GetScanlines()
end
local function ExecuteSlideTransition()
    if EngineState == STATE_ZEN or EngineState == STATE_HIBERNATED then
        updateTargetSide()
        Cam_X, Cam_Y, Cam_Z, Cam_Yaw, Cam_Pitch = tX, tY, tZ, tYaw, tPitch
        EngineState = STATE_ZEN
        TargetState = STATE_ZEN
        SysText.Alpha = 1.0
        snapshotBaked = false
    else
        TargetState = STATE_PRESENT
        TriggerContinuousFlight()
    end
end

function love.keypressed(key)
    if EngineState == STATE_FREEFLY and (key == "p" or key == "space") then
        lastFreeX, lastFreeY, lastFreeZ, lastFreeYaw, lastFreePitch = Cam_X, Cam_Y, Cam_Z, Cam_Yaw, Cam_Pitch
        TargetState = STATE_PRESENT
        TriggerContinuousFlight()
    elseif EngineState ~= STATE_FREEFLY and (key == "left" or key == "right" or key == "up" or key == "down") then
        local COLS = 16; local row = math.floor(TargetSlide / COLS); local col = TargetSlide % COLS; local row_start = row * COLS; local oldTarget = TargetSlide
        if key == "right" then
            if col + 1 < COLS then TargetSlide = math.min(row_start + col + 1, NumSlides - 1) else TargetSlide = row_start end
        elseif key == "left" then
            if col - 1 >= 0 then TargetSlide = math.min(row_start + col - 1, NumSlides - 1) else TargetSlide = math.min(row_start + COLS - 1, NumSlides - 1) end
        elseif key == "up" then
            if TargetSlide - COLS >= 0 then TargetSlide = TargetSlide - COLS end
        elseif key == "down" then
            if TargetSlide + COLS < NumSlides then TargetSlide = TargetSlide + COLS end
        end
        if TargetSlide ~= oldTarget then
            ExecuteSlideTransition()
        end
    elseif key == "i" or key == "u" then
        EngineState = STATE_FREEFLY; TargetState = STATE_FREEFLY
        if key == "u" then Cam_X, Cam_Y, Cam_Z, Cam_Yaw, Cam_Pitch = lastFreeX, lastFreeY, lastFreeZ, lastFreeYaw, lastFreePitch end
    elseif EngineState ~= STATE_FREEFLY and (key == "space" or key == "backspace") then
        TargetSlide = (key == "space") and ((TargetSlide + 1) % NumSlides) or ((TargetSlide - 1 + NumSlides) % NumSlides)
        ExecuteSlideTransition()
    elseif key == "j" and EngineState == STATE_FREEFLY then
        isMouseCaptured = not isMouseCaptured; love.mouse.setRelativeMode(isMouseCaptured)
    elseif key == "c" then Physics.TriggerChaosField()
    elseif key == "v" then Physics.TriggerVortex()
    elseif key == "g" then Physics.TriggerGravity()
    elseif key == "z" then
        if EngineState == STATE_FREEFLY then return end
        if EngineState == STATE_PRESENT then TargetState = STATE_ZEN; else TargetState = STATE_PRESENT end
        TriggerContinuousFlight()
    elseif key == "escape" then love.event.quit() end
end
function love.update(dt)
    dt = math.min(dt, 0.033)

    if pendingResize then
        resizeTimer = resizeTimer - dt
        if resizeTimer <= 0 then
            ReinitBuffers()
            updateTargetSide()
            if EngineState ~= STATE_CINEMATIC and EngineState ~= STATE_FREEFLY then
                Cam_X, Cam_Y, Cam_Z, Cam_Yaw, Cam_Pitch = tX, tY, tZ, tYaw, tPitch
            end
            SysText.InitSlideTextCache()
            pendingResize = false
        end
        return
    end

    -- 1. HANDLE CAMERA FLIGHT AND STATE TRANSITIONS FIRST!
    if EngineState == STATE_CINEMATIC then
        lerpT = math.min(1.0, lerpT + dt * 1.5)
        local easeT = 1 - (1 - lerpT) * (1 - lerpT)

        Cam_X = lerp(startX, tX, easeT)
        Cam_Y = lerp(startY, tY, easeT)
        Cam_Z = lerp(startZ, tZ, easeT)
        Cam_Yaw = lerpAngle(startYaw, tYaw, easeT)
        Cam_Pitch = lerpAngle(startPitch, tPitch, easeT)

        if lerpT >= 1.0 then
            Cam_X, Cam_Y, Cam_Z, Cam_Yaw, Cam_Pitch = tX, tY, tZ, tYaw, tPitch
            EngineState = TargetState -- Safely transition to ZEN or PRESENT
        end

    elseif EngineState == STATE_FREEFLY then
        local s = 2000 * dt
        if love.keyboard.isDown("w") then Cam_X, Cam_Y, Cam_Z = Cam_X + Cam_FWX * s, Cam_Y + Cam_FWY * s, Cam_Z + Cam_FWZ * s end
        if love.keyboard.isDown("s") then Cam_X, Cam_Y, Cam_Z = Cam_X - Cam_FWX * s, Cam_Y - Cam_FWY * s, Cam_Z - Cam_FWZ * s end
        if love.keyboard.isDown("a") then Cam_X, Cam_Z = Cam_X - Cam_RTX * s, Cam_Z - Cam_RTZ * s end
        if love.keyboard.isDown("d") then Cam_X, Cam_Z = Cam_X + Cam_RTX * s, Cam_Z + Cam_RTZ * s end
        if love.keyboard.isDown("e") then Cam_Y = Cam_Y - s end
        if love.keyboard.isDown("q") then Cam_Y = Cam_Y + s end
        local rotSpeed = 2 * dt
        if love.keyboard.isDown("left") then Cam_Yaw = Cam_Yaw - rotSpeed end
        if love.keyboard.isDown("right") then Cam_Yaw = Cam_Yaw + rotSpeed end
        if love.keyboard.isDown("up") then Cam_Pitch = Cam_Pitch - rotSpeed end
        if love.keyboard.isDown("down") then Cam_Pitch = Cam_Pitch + rotSpeed end
        Cam_Pitch = max(-1.56, min(1.56, Cam_Pitch))
    end

    UpdateCameraBasis()

    -- 2. DECOUPLED TEXT ALPHA (Evaluates against the NEW state!)
    local isTextReady = SysText.Update(EngineState, dt)

    -- 3. HIBERNATION LOGIC
    if EngineState == STATE_HIBERNATED then
        if snapshotBaked then love.timer.sleep(0.25) end
    else
        snapshotBaked = false
    end

    -- If we just arrived in ZEN, isTextReady is FALSE (because alpha is 0.0)
    -- This prevents premature hibernation!
    if EngineState == STATE_ZEN and isTextReady then
        EngineState = STATE_HIBERNATED
    end

    -- 4. PHYSICS LOGIC
    if EngineState ~= STATE_ZEN and EngineState ~= STATE_HIBERNATED then
        Physics.IntegrateKinematics(dt)
        Physics.ResolveCollisions()
    end
end

function love.draw()
    if pendingResize then
        love.graphics.clear(0.05, 0.05, 0.05)
        love.graphics.print("REBUILDING SWAPCHAIN...", 20, 20)
        return
    end

    Renderer.DrawFrame()

    love.graphics.setBlendMode("alpha")
    if EngineState ~= STATE_ZEN and EngineState ~= STATE_HIBERNATED then
        love.graphics.draw(scanlineCanvas, 0, 0)
    end

    love.graphics.setFont(Font_UI)
    love.graphics.setColor(0, 1, 0.5, 1)
    love.graphics.print("ULTIMA PLATIN | FPS: "..love.timer.getFPS(), 10, 10)

    local modeText = "MODE: "
    if EngineState == STATE_ZEN or EngineState == STATE_HIBERNATED then modeText = modeText .. "ZEN (CPU HIBERNATION)" else modeText = modeText .. "ACTIVE (PHYSICS ON)" end
    love.graphics.print(modeText, 10, 30)

    if EngineState == STATE_ZEN or EngineState == STATE_HIBERNATED then
        snapshotBaked = true
    end
end

function love.resize(w, h)
    pendingResize = true
    resizeTimer = 0.2
end

function love.mousemoved(x, y, dx, dy)
    if isMouseCaptured and EngineState == STATE_FREEFLY then
        local sensitivity = 0.002
        Cam_Yaw = Cam_Yaw + (dx * sensitivity)
        Cam_Pitch = Cam_Pitch + (dy * sensitivity)
    end
end

require("sys_memory")
local ffi = require("ffi")
local Engine = require("engine")
-- removed slides_internal
local Physics = require("sys_physics")
local Renderer = require("sys_renderer") -- we will figure this out after we integrated some functionality from main.lua into the 4 modules
local Factory = require("sys_factory")
local SysText = require("sys_text") -- same here, also sys_renderer will need adjustments but this one must stay stable until after the presentation, font rendering really is something else
local BGB = {}

local floor, ceil, max, min, abs = math.floor, math.ceil, math.max, math.min, math.abs
local random, sqrt, cos, sin, pi, atan2 = math.random, math.sqrt, math.cos, math.sin, math.pi, math.atan2

isFullscreen = true
isMouseCaptured = false
snapshotBaked = false
SlideExposure = 1.0

local PRESENTATION_ZOOM = 1.0

local function lerp(a, b, t) return a + (b - a) * t end
local function lerpAngle(a, b, t)
    local diff = (b - a + pi) % (pi * 2) - pi
    return a + diff * t
end
local function LayoutHUD()
    if not HUD.open or NumSlides == 0 then return end
    local ts = TargetSlide
    local sx, sy, sz = Box_X[ts], Box_Y[ts], Box_Z[ts]
    local nx, ny, nz = Box_NX[ts], Box_NY[ts], Box_NZ[ts]
    
    -- 1. Match the exact "Front/Back" side logic of the camera
    local w, h = Box_HW[ts] * 2, Box_HH[ts] * 2
    local distScale = math.max(h, w * (CANVAS_H / CANVAS_W))
    local dist = (distScale * Cam_FOV) / CANVAS_H * PRESENTATION_ZOOM
    local fx, fy, fz = sx + nx * dist, sy + ny * dist, sz + nz * dist
    local bx, by, bz = sx - nx * dist, sy - ny * dist, sz - nz * dist
    local dF = (fx - Cam_X)^2 + (fy - Cam_Y)^2 + (fz - Cam_Z)^2
    local dB = (bx - Cam_X)^2 + (by - Cam_Y)^2 + (bz - Cam_Z)^2
    local sideMultiplier = (dF <= dB) and 1 or -1

    -- 2. DYNAMIC MESH RESHAPING: Match the slide geometry exactly! (95% scale)
    local hw, hh, ht = Box_HW[ts] * 0.95, Box_HH[ts] * 0.95, 5
    local vStart = Obj_VertStart[HUD_Mesh_ID]
    Vert_LX[vStart+0], Vert_LY[vStart+0], Vert_LZ[vStart+0] = -hw, -hh, -ht
    Vert_LX[vStart+1], Vert_LY[vStart+1], Vert_LZ[vStart+1] =  hw, -hh, -ht
    Vert_LX[vStart+2], Vert_LY[vStart+2], Vert_LZ[vStart+2] =  hw,  hh, -ht
    Vert_LX[vStart+3], Vert_LY[vStart+3], Vert_LZ[vStart+3] = -hw,  hh, -ht
    Vert_LX[vStart+4], Vert_LY[vStart+4], Vert_LZ[vStart+4] = -hw, -hh,  ht
    Vert_LX[vStart+5], Vert_LY[vStart+5], Vert_LZ[vStart+5] =  hw, -hh,  ht
    Vert_LX[vStart+6], Vert_LY[vStart+6], Vert_LZ[vStart+6] =  hw,  hh,  ht
    Vert_LX[vStart+7], Vert_LY[vStart+7], Vert_LZ[vStart+7] = -hw,  hh,  ht

    -- 3. Snap it 2 units in front of the active face
    local offset = (Box_HT[ts] + 2) * sideMultiplier
    Obj_X[HUD_Mesh_ID] = sx + nx * offset
    Obj_Y[HUD_Mesh_ID] = sy + ny * offset
    Obj_Z[HUD_Mesh_ID] = sz + nz * offset
    Obj_FWX[HUD_Mesh_ID], Obj_FWY[HUD_Mesh_ID], Obj_FWZ[HUD_Mesh_ID] = nx * sideMultiplier, ny * sideMultiplier, nz * sideMultiplier
    Obj_RTX[HUD_Mesh_ID], Obj_RTY[HUD_Mesh_ID], Obj_RTZ[HUD_Mesh_ID] = Box_RTX[ts] * sideMultiplier, 0, Box_RTZ[ts] * sideMultiplier
    Obj_UPX[HUD_Mesh_ID], Obj_UPY[HUD_Mesh_ID], Obj_UPZ[HUD_Mesh_ID] = Box_UPX[ts], Box_UPY[ts], Box_UPZ[ts]

    Renderer.BakeStaticLighting()
end
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
    local id = TargetSlide
    -- If we have no slides, abort safely
    if NumSlides == 0 or id >= NumSlides then return end

    -- Pull completely from FFI Arrays (No Lua table needed!)
    local nx, ny, nz = Box_NX[id], Box_NY[id], Box_NZ[id]
    local sx, sy, sz = Box_X[id], Box_Y[id], Box_Z[id]

    -- Reconstruct full width/height from our Half-Width/Half-Height FFI buffers
    local w = Box_HW[id] * 2
    local h = Box_HH[id] * 2

    local distScale = math.max(h, w * (CANVAS_H / CANVAS_W))

    local pad = 200
    if TargetState == STATE_ZEN then pad = 0
    elseif TargetState == STATE_OVERVIEW then pad = 6000 end

    local dist = (distScale * Cam_FOV) / CANVAS_H * PRESENTATION_ZOOM + pad

    local fx, fy, fz = sx + nx * dist, sy + ny * dist, sz + nz * dist
    local bx, by, bz = sx - nx * dist, sy - ny * dist, sz - nz * dist

    local dF = (fx - Cam_X)^2 + (fy - Cam_Y)^2 + (fz - Cam_Z)^2
    local dB = (bx - Cam_X)^2 + (by - Cam_Y)^2 + (bz - Cam_Z)^2

    local dx, dy, dz
    if dF <= dB then
        tX, tY, tZ = fx, fy, fz
        dx, dy, dz = sx - fx, sy - fy, sz - fz
    else
        tX, tY, tZ = bx, by, bz
        dx, dy, dz = sx - bx, sy - by, sz - bz
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


-- Demand High-DPI (Retina/4K) pixels from the OS, and use Desktop Fullscreen
-- love.window.setMode(0, 0, {
-- fullscreen = true,
-- fullscreentype = "desktop",
-- highdpi = true,
-- vsync = 1
-- })
function love.load()
    ReinitBuffers()
    love.mouse.setRelativeMode(isMouseCaptured)
    Font_UI = love.graphics.newFont(14)
    Font_Terminal = love.graphics.newFont(16)
    local sceneState = Engine.Boot()
    if sceneState then
        -- NO MORE MANIFEST GLOBAL!
        NumSlides = sceneState.NumSlides
        local b = sceneState.bounds
        B_MinX, B_MinY, B_MinZ, B_MaxX, B_MaxY, B_MaxZ = b.minX, b.minY, b.minZ, b.maxX, b.maxY, b.maxZ

        TargetSlide = 0
        updateTargetSide()

        Cam_X, Cam_Y, Cam_Z, Cam_Yaw, Cam_Pitch = tX, tY, tZ, tYaw, tPitch
        startX, startY, startZ, startYaw, startPitch = tX, tY, tZ, tYaw, tPitch
        lastFreeX, lastFreeY, lastFreeZ, lastFreeYaw, lastFreePitch = Cam_X, Cam_Y, Cam_Z, Cam_Yaw, Cam_Pitch

        -- Pass the payload locally!
        SysText.InitSlideTextCache(sceneState.textPayload)

        BuildCollisionPools()
        UpdateCameraBasis()
        Renderer.BakeStaticLighting()

        HUD_DIST = 500
        -- Replace the HUD_Mesh_ID line with this:
        HUD_Mesh_ID = Factory.CreateSlideMesh(0, 0, 0, 1600, 900, 10, C_LATTE)
        local tStart = Obj_TriStart[HUD_Mesh_ID]
        for t = 0, Obj_TriCount[HUD_Mesh_ID] - 1 do
            Tri_BaseLight[tStart + t] = 1.0
        end
    end
    BGB = require("bgb") -- i will do it here
end
local function ExecuteSlideTransition()
    if EngineState == STATE_ZEN or EngineState == STATE_HIBERNATED then
        updateTargetSide()
        Cam_X, Cam_Y, Cam_Z, Cam_Yaw, Cam_Pitch = tX, tY, tZ, tYaw, tPitch
        EngineState = STATE_ZEN
        TargetState = STATE_ZEN

        -- THE FIX: Instantly sync the active slide for Zen Mode
        activeSlide = TargetSlide

        SysText.Alpha = 1.0
        snapshotBaked = false
    else
        -- THE FIX: Respect the Overview state!
        if EngineState == STATE_OVERVIEW or TargetState == STATE_OVERVIEW then
            TargetState = STATE_OVERVIEW
        else
            TargetState = STATE_PRESENT
        end

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
            if HUD.open then LayoutHUD() end
        end
    elseif key == "i" or key == "u" then
        EngineState = STATE_FREEFLY; TargetState = STATE_FREEFLY
        if key == "u" then Cam_X, Cam_Y, Cam_Z, Cam_Yaw, Cam_Pitch = lastFreeX, lastFreeY, lastFreeZ, lastFreeYaw, lastFreePitch end
    elseif EngineState ~= STATE_FREEFLY and (key == "space" or key == "backspace") then
        -- NEW LOGIC: If we are in Overview, Space toggles us back to the slide.
        if key == "space" and TargetState == STATE_OVERVIEW then
            TargetState = STATE_PRESENT
            TriggerContinuousFlight()
        else
            -- Standard behavior: Move to next/prev slide
            TargetSlide = (key == "space") and ((TargetSlide + 1) % NumSlides) or ((TargetSlide - 1 + NumSlides) % NumSlides)
            ExecuteSlideTransition()
            if HUD.open then LayoutHUD() end -- ADD IT HERE!
        end
    elseif key == "j" and EngineState == STATE_FREEFLY then
        isMouseCaptured = not isMouseCaptured; love.mouse.setRelativeMode(isMouseCaptured)
    elseif key == "c" then Physics.TriggerChaosField()
    elseif key == "v" then Physics.TriggerVortex()
    elseif key == "g" then Physics.TriggerGravity()
    elseif key == "tab" then
        if EngineState == STATE_FREEFLY then return end
        if TargetState == STATE_OVERVIEW then
            TargetState = STATE_PRESENT
        else
            TargetState = STATE_OVERVIEW
        end
        TriggerContinuousFlight()
    elseif key == "z" then
        if EngineState == STATE_FREEFLY then return end
        -- Allow dropping directly into ZEN from OVERVIEW
        if EngineState == STATE_PRESENT or EngineState == STATE_OVERVIEW then TargetState = STATE_ZEN
        else TargetState = STATE_PRESENT end
        TriggerContinuousFlight()
    elseif key == "+" or key == "kp+" then
        SlideExposure = math.min(3.0, SlideExposure + 0.1)
        snapshotBaked = false -- Forces the Zen mode to re-render the frame!
    elseif key == "-" or key == "kp-" then
        SlideExposure = math.max(0.1, SlideExposure - 0.1)
        snapshotBaked = false -- Forces the Zen mode to re-render the frame!
    elseif key == "escape" then love.event.quit() end

    -- Inside love.keypressed
    if key:match("^[1-9]$") then
        local para_map = {["1"]="611", ["2"]="611a", ["3"]="620", ["4"]="622", ["5"]="623", ["6"]="626"}
        local target = para_map[key]
        if target and BGB[target] then
            HUD.open = true
            HUD.lines = { c_cyan .. "> BGB SEARCH: § " .. target .. c_reset, BGB[target].title, "---", BGB[target].text }
            SysText.BakeTerminal()
            LayoutHUD() -- Position the board!
            snapshotBaked = false
        end
    end

    if key == "t" then
        HUD.open = not HUD.open
        if HUD.open then 
            SysText.BakeTerminal()
            LayoutHUD() -- Position the board!
        end
        snapshotBaked = false
    end
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

    -- THE FIX: Swap the active slide ONLY when the old text has fully faded out!
    if SysText.Alpha <= 0.01 then
        activeSlide = TargetSlide
    end

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

    -- love.graphics.setBlendMode("alpha")
    -- if EngineState ~= STATE_ZEN and EngineState ~= STATE_HIBERNATED then
        -- placeholder for effects
    -- end

    -- love.graphics.setFont(Font_UI)
    -- love.graphics.setColor(0, 1, 0.5, 1)
    -- love.graphics.print("ULTIMA PLATIN | FPS: "..love.timer.getFPS(), 10, 10)

    local modeText = "MODE: "
    if EngineState == STATE_ZEN or EngineState == STATE_HIBERNATED then modeText = modeText .. "ZEN (CPU HIBERNATION)" else modeText = modeText .. "ACTIVE (PHYSICS ON)" end
    -- love.graphics.print(modeText, 10, 30)

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

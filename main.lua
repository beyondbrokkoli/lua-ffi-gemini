require("sys_memory")
local ffi = require("ffi")
local Engine = require("engine")
local SlidesInternal = require("slides_internal")
local Physics = require("sys_physics")
local Renderer = require("sys_renderer")
local Factory = require("sys_factory")
local floor, ceil, max, min, abs = math.floor, math.ceil, math.max, math.min, math.abs
local random, sqrt, cos, sin, pi, atan2 = math.random, math.sqrt, math.cos, math.sin, math.pi, math.atan2
pendingResize = false
resizeTimer = 0
isFullscreen = true
isMouseCaptured = false
isZenMode = false
snapshotBaked = false
local PRESENTATION_ZOOM = 1.0
local CAM_PADDING = 200
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
local function ParseSlideLine(rawText, fonts)
    local pipePos = rawText:find("|")
    if pipePos then
        local leftStr = rawText:sub(1, pipePos - 1):match("^%s*(.-)%s*$")
        local rightStr = rawText:sub(pipePos + 1):match("^%s*(.-)%s*$")
        local columns = ParseSlideLine(leftStr, fonts)
        local rightCols = ParseSlideLine(rightStr, fonts)
        for _, col in ipairs(rightCols) do table.insert(columns, col) end
        return columns
    end
    local cleanText = rawText
    local currentFont = fonts.body
    local currentAlign = "left"
    if cleanText:match("^~%s+") then
        cleanText = cleanText:gsub("^~%s+", "")
        currentAlign = "center"
    end
    if cleanText:match("^#%s+") then
        cleanText = cleanText:gsub("^#%s+", "")
        currentFont = fonts.head
    end
    return { { text = cleanText, font = currentFont, align = currentAlign } }
end
local function InitSlideTextCache()
    -- 1. CLEAN UP THE OLD CACHE FIRST
    if SlideTitles then
        for i, cache in pairs(SlideTitles) do
            if cache._keepAlive then
                -- Explicitly tell LÖVE to free the C-side memory
                cache._keepAlive:release()
            end
            -- If you store the canvas anywhere, release it too
        end
    end

    SlideTitles = {}

    for i = 0, NumSlides - 1 do
        local node = manifest[i]
        local titleText = (node and node.text) or ("SLIDE " .. tostring(i + 1))
        local w, h = Box_HW[i] * 2, Box_HH[i] * 2
        local distScale = max(h, w * (CANVAS_H / CANVAS_W))
        local optDist = (distScale * Cam_FOV) / CANVAS_H * PRESENTATION_ZOOM + CAM_PADDING
        local text_depth = optDist - (Box_HT[i] + 5)
        local optimal_scale = (Cam_FOV / text_depth)
        local fonts = {
            title = love.graphics.newFont(max(8, floor((h * 0.10) * optimal_scale))),
            head = love.graphics.newFont(max(8, floor((h * 0.08) * optimal_scale))),
            body = love.graphics.newFont(max(8, floor((h * 0.05) * optimal_scale)))
        }
        local virtW = max(1, floor(w * optimal_scale))
        local virtH = max(1, floor(h * optimal_scale))
        local giantCanvas = love.graphics.newCanvas(virtW, virtH)
        love.graphics.setCanvas(giantCanvas)
        love.graphics.clear(0, 0, 0, 0)
        love.graphics.setColor(1, 1, 1, 1)
        local currentY = floor(virtH * 0.05)
        local paddingX = floor(virtW * 0.05)
        local maxTextWidth = virtW - (paddingX * 2)
        local bottomLimit = virtH - floor(virtH * 0.12)
        love.graphics.setFont(fonts.title)
        love.graphics.printf(titleText, paddingX, currentY, maxTextWidth, "center")
        currentY = currentY + fonts.title:getHeight() + floor(virtH * 0.02)
        if node and node.content then
            for _, s in ipairs(node.content) do
                if s ~= "" then
                    local columns = ParseSlideLine(s, fonts)
                    local numCols = #columns
                    local colWidth = floor(maxTextWidth / numCols)
                    local maxRowHeight = 0
                    for colIdx, colData in ipairs(columns) do
                        love.graphics.setFont(colData.font)
                        local xOffset = paddingX + ((colIdx - 1) * colWidth)
                        local colPrintWidth = colWidth - (numCols > 1 and floor(virtW * 0.02) or 0)
                        local _, wrappedLines = colData.font:getWrap(colData.text, colPrintWidth)
                        local lineY = currentY
                        local colHeight = 0
                        for lIdx, lineStr in ipairs(wrappedLines) do
                            if (lineY + colData.font:getHeight()) > bottomLimit then
                                local chopped = lineStr:sub(1, -4) .. "..."
                                love.graphics.printf(chopped, xOffset, lineY, colPrintWidth, colData.align)
                                colHeight = colHeight + colData.font:getHeight()
                                break
                            else
                                love.graphics.printf(lineStr, xOffset, lineY, colPrintWidth, colData.align)
                                lineY = lineY + colData.font:getHeight()
                                colHeight = colHeight + colData.font:getHeight()
                            end
                        end
                        if colHeight > maxRowHeight then maxRowHeight = colHeight end
                    end
                    currentY = currentY + maxRowHeight + floor(virtH * 0.005)
                else
                    currentY = currentY + fonts.body:getHeight()
                end
            end
        end
        love.graphics.setCanvas()
        local imgData = giantCanvas:newImageData()
        SlideTitles[i] = {
            ptr = ffi.cast("uint32_t*", imgData:getPointer()),
            w = virtW, h = virtH,
            _keepAlive = imgData,
            text_z_offset = (Box_HT[i] + 5),
            opt_scale = optimal_scale
        }
        -- 2. RELEASE THE TEMPORARY CANVAS
        -- giantCanvas is no longer needed after making the ImageData
        giantCanvas:release()
    end
    -- 3. FORCE A GC CYCLE (Optional but recommended after heavy FFI churn)
    collectgarbage("collect")
end
local function OLD_InitSlideTextCache()
    SlideTitles = {}
    for i = 0, NumSlides - 1 do
        local node = manifest[i]
        local titleText = (node and node.text) or ("SLIDE " .. tostring(i + 1))
        local w, h = Box_HW[i] * 2, Box_HH[i] * 2
        local distScale = max(h, w * (CANVAS_H / CANVAS_W))
        local optDist = (distScale * Cam_FOV) / CANVAS_H * PRESENTATION_ZOOM + CAM_PADDING
        local text_depth = optDist - (Box_HT[i] + 5)
        local optimal_scale = (Cam_FOV / text_depth)
        local fonts = {
            title = love.graphics.newFont(max(8, floor((h * 0.10) * optimal_scale))),
            head = love.graphics.newFont(max(8, floor((h * 0.08) * optimal_scale))),
            body = love.graphics.newFont(max(8, floor((h * 0.05) * optimal_scale)))
        }
        local virtW = max(1, floor(w * optimal_scale))
        local virtH = max(1, floor(h * optimal_scale))
        local giantCanvas = love.graphics.newCanvas(virtW, virtH)
        love.graphics.setCanvas(giantCanvas)
        love.graphics.clear(0, 0, 0, 0)
        love.graphics.setColor(1, 1, 1, 1)
        local currentY = floor(virtH * 0.05)
        local paddingX = floor(virtW * 0.05)
        local maxTextWidth = virtW - (paddingX * 2)
        local bottomLimit = virtH - floor(virtH * 0.12)
        love.graphics.setFont(fonts.title)
        love.graphics.printf(titleText, paddingX, currentY, maxTextWidth, "center")
        currentY = currentY + fonts.title:getHeight() + floor(virtH * 0.02)
        if node and node.content then
            for _, s in ipairs(node.content) do
                if s ~= "" then
                    local columns = ParseSlideLine(s, fonts)
                    local numCols = #columns
                    local colWidth = floor(maxTextWidth / numCols)
                    local maxRowHeight = 0
                    for colIdx, colData in ipairs(columns) do
                        love.graphics.setFont(colData.font)
                        local xOffset = paddingX + ((colIdx - 1) * colWidth)
                        local colPrintWidth = colWidth - (numCols > 1 and floor(virtW * 0.02) or 0)
                        local _, wrappedLines = colData.font:getWrap(colData.text, colPrintWidth)
                        local lineY = currentY
                        local colHeight = 0
                        for lIdx, lineStr in ipairs(wrappedLines) do
                            if (lineY + colData.font:getHeight()) > bottomLimit then
                                local chopped = lineStr:sub(1, -4) .. "..."
                                love.graphics.printf(chopped, xOffset, lineY, colPrintWidth, colData.align)
                                colHeight = colHeight + colData.font:getHeight()
                                break
                            else
                                love.graphics.printf(lineStr, xOffset, lineY, colPrintWidth, colData.align)
                                lineY = lineY + colData.font:getHeight()
                                colHeight = colHeight + colData.font:getHeight()
                            end
                        end
                        if colHeight > maxRowHeight then maxRowHeight = colHeight end
                    end
                    currentY = currentY + maxRowHeight + floor(virtH * 0.005)
                else
                    currentY = currentY + fonts.body:getHeight()
                end
            end
        end
        love.graphics.setCanvas()
        local imgData = giantCanvas:newImageData()
        SlideTitles[i] = {
            ptr = ffi.cast("uint32_t*", imgData:getPointer()),
            w = virtW, h = virtH,
            _keepAlive = imgData,
            text_z_offset = (Box_HT[i] + 5),
            opt_scale = optimal_scale
        }
    end
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
local function GetViewDistance(w, h)
    local distScale = max(h, w * (CANVAS_H / CANVAS_W))
    return (distScale * Cam_FOV) / CANVAS_H + 200
end
local function updateTargetSide()
    local s = manifest[TargetSlide]
    if not s then return end
    local nx = Box_NX[TargetSlide] or 0
    local ny = Box_NY[TargetSlide] or 0
    local nz = Box_NZ[TargetSlide] or 1
    local distScale = math.max(s.h, s.w * (CANVAS_H / CANVAS_W))
    local dist = (distScale * Cam_FOV) / CANVAS_H * PRESENTATION_ZOOM + CAM_PADDING
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
    local distXZ = math.sqrt(dx*dx + dz*dz)
    tPitch = math.atan2(dy, distXZ)
end
local function TriggerChaosField()
    for i = 0, Pool_Kinematic_Count - 1 do
        local id = Pool_Kinematic[i]
        Obj_VelX[id] = Obj_VelX[id] + (random() - 0.5) * 2000
        Obj_VelY[id] = Obj_VelY[id] + (random() - 0.5) * 2000
        Obj_VelZ[id] = Obj_VelZ[id] + (random() - 0.5) * 2000
        Obj_RotSpeedYaw[id] = Obj_RotSpeedYaw[id] + (random() - 0.5) * 30
        Obj_RotSpeedPitch[id] = Obj_RotSpeedPitch[id] + (random() - 0.5) * 30
    end
end
local function TriggerVortex()
    for i = 0, Pool_Kinematic_Count - 1 do
        local id = Pool_Kinematic[i]
        Obj_RotSpeedYaw[id] = Obj_RotSpeedYaw[id] + (math.random() - 0.5) * 50
        Obj_RotSpeedPitch[id] = Obj_RotSpeedPitch[id] + (math.random() - 0.5) * 50
    end
end
local function TriggerGravity()
    for i = 0, Pool_Kinematic_Count - 1 do
        local id = Pool_Kinematic[i]
        local homeIdx = Obj_HomeIdx[id]
        if homeIdx >= 0 then
            local dx = Sphere_X[homeIdx] - Obj_X[id]
            local dy = Sphere_Y[homeIdx] - Obj_Y[id]
            local dz = Sphere_Z[homeIdx] - Obj_Z[id]
            local dist = math.sqrt(dx*dx + dy*dy + dz*dz)
            if dist > 0.1 then
                Obj_VelX[id] = Obj_VelX[id] + (dx/dist) * 800
                Obj_VelY[id] = Obj_VelY[id] + (dy/dist) * 800
                Obj_VelZ[id] = Obj_VelZ[id] + (dz/dist) * 800
            end
        end
    end
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
function love.load()
    -- Demand High-DPI (Retina/4K) pixels from the OS, and use Desktop Fullscreen
    -- love.window.setMode(0, 0, {
        -- fullscreen = true,
        -- fullscreentype = "desktop",
        -- highdpi = true,
        -- vsync = 1
    -- })

    -- Call ReinitBuffers without passing w/h, because it will fetch the real pixels itself
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
        InitSlideTextCache()
        SlidesInternal.SpawnDeepSpaceAsteroids(slideAPI, 60)
        SlidesInternal.SpawnSpaceAsteroids(slideAPI, 400)
        SlidesInternal.SpawnHeroDonut(slideAPI, 0)
        SlidesInternal.SpawnSatelliteRing(slideAPI, 1, 16)
        SlidesInternal.CrystalCompanion(slideAPI, 3, 30)
        SlidesInternal.SpawnGeometricStorm(slideAPI, 3, 45)
        SlidesInternal.SpawnParticleAccelerator(slideAPI, 4, 80)
        SlidesInternal.SpawnSatelliteRing(slideAPI, 8, 24)
        SlidesInternal.SpawnChaosCluster(slideAPI, 9, 50)
        BuildCollisionPools()
        UpdateCameraBasis()
        Renderer.BakeStaticLighting()
    end
    scanlineCanvas = GetScanlines()
end
function love.keypressed(key)
    if not presentationMode and (key == "p" or key == "space") then
        lastFreeX, lastFreeY, lastFreeZ, lastFreeYaw, lastFreePitch = Cam_X, Cam_Y, Cam_Z, Cam_Yaw, Cam_Pitch
        startX, startY, startZ, startYaw, startPitch = Cam_X, Cam_Y, Cam_Z, Cam_Yaw, Cam_Pitch
        lerpT, arrivalTimer = 0, 0
        updateTargetSide()
        presentationMode = true
    elseif presentationMode and (key == "left" or key == "right" or key == "up" or key == "down") then
        local COLS = 8
        local row = math.floor(TargetSlide / COLS)
        local col = TargetSlide % COLS
        local row_start = row * COLS
        local oldTarget = TargetSlide
        if key == "right" then
            if col + 1 < COLS then
                local target = row_start + col + 1
                if target < NumSlides then TargetSlide = target end
            else
                TargetSlide = row_start
            end
        elseif key == "left" then
            if col - 1 >= 0 then
                local target = row_start + col - 1
                if target < NumSlides then TargetSlide = target end
            else
                local target = row_start + COLS - 1
                if target < NumSlides then TargetSlide = target end
            end
        elseif key == "up" then
            if TargetSlide - COLS >= 0 then TargetSlide = TargetSlide - COLS end
        elseif key == "down" then
            local target = TargetSlide + COLS
            if target < NumSlides then TargetSlide = target end
        end
        if TargetSlide ~= oldTarget then
            startX, startY, startZ, startYaw, startPitch = Cam_X, Cam_Y, Cam_Z, Cam_Yaw, Cam_Pitch
            lerpT = isZenMode and 1.0 or 0
            arrivalTimer = isZenMode and 0.3 or 0
            snapshotBaked = false
            updateTargetSide()
        end
    elseif key == "i" or key == "u" then
        presentationMode = false
        isZenMode = false
        CAM_PADDING = 200
        if key == "u" then Cam_X, Cam_Y, Cam_Z, Cam_Yaw, Cam_Pitch = lastFreeX, lastFreeY, lastFreeZ, lastFreeYaw, lastFreePitch end
    elseif presentationMode and (key == "space" or key == "backspace") then
        startX, startY, startZ, startYaw, startPitch = Cam_X, Cam_Y, Cam_Z, Cam_Yaw, Cam_Pitch
        lerpT = isZenMode and 1.0 or 0
        arrivalTimer = isZenMode and 0.3 or 0
        snapshotBaked = false
        TargetSlide = (key == "space") and ((TargetSlide + 1) % NumSlides) or ((TargetSlide - 1 + NumSlides) % NumSlides)
        updateTargetSide()
    elseif key == "j" and not presentationMode then
        isMouseCaptured = not isMouseCaptured
        love.mouse.setRelativeMode(isMouseCaptured)
    elseif key == "c" then TriggerChaosField()
    elseif key == "v" then TriggerVortex()
    elseif key == "g" then TriggerGravity()
    elseif key == "z" then
        if not presentationMode then return end
        isZenMode = not isZenMode
        CAM_PADDING = isZenMode and 0 or 200
        updateTargetSide()
        if isSettled then
            Cam_X, Cam_Y, Cam_Z = tX, tY, tZ
            Cam_Yaw, Cam_Pitch = tYaw, tPitch
            snapshotBaked = false
        else
            startX, startY, startZ = Cam_X, Cam_Y, Cam_Z
            startYaw, startPitch = Cam_Yaw, Cam_Pitch
        end
        InitSlideTextCache()
    elseif key == "escape" then love.event.quit()
    end
end
function love.update(dt)
    dt = math.min(dt, 0.033)
    if pendingResize then
        resizeTimer = resizeTimer - dt
        if resizeTimer <= 0 then
            ReinitBuffers() -- No arguments needed!
            updateTargetSide()
            if presentationMode and isSettled then
                Cam_X, Cam_Y, Cam_Z = tX, tY, tZ
                Cam_Yaw, Cam_Pitch = tYaw, tPitch
            end
            InitSlideTextCache()
            pendingResize = false
        end
        return
    end
    if presentationMode and NumSlides > 0 then
        lerpT = math.min(1.0, lerpT + dt * 1)
        local easeT = 1 - (1 - lerpT) * (1 - lerpT)
        if lerpT < 1.0 then
            arrivalTimer = 0
            isSettled = false
            Cam_X = lerp(startX, tX, easeT)
            Cam_Y = lerp(startY, tY, easeT)
            Cam_Z = lerp(startZ, tZ, easeT)
            Cam_Yaw = lerpAngle(startYaw, tYaw, easeT)
            Cam_Pitch = lerpAngle(startPitch, tPitch, easeT)
        else
            Cam_X, Cam_Y, Cam_Z = tX, tY, tZ
            Cam_Yaw, Cam_Pitch = tYaw, tPitch
            isSettled = true
            arrivalTimer = arrivalTimer + dt
        end
    else
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
    if presentationMode and isSettled and isZenMode then
        if arrivalTimer >= 0.3 then
            if snapshotBaked then
                love.timer.sleep(0.25)
            end
        else
            snapshotBaked = false
        end
    else
        snapshotBaked = false
    end
    if not isZenMode then
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
    if not isZenMode then
        love.graphics.draw(scanlineCanvas, 0, 0)
    end
    love.graphics.setFont(Font_UI)
    love.graphics.setColor(0, 1, 0.5, 1)
    love.graphics.print("ULTIMA PLATIN | FPS: "..love.timer.getFPS(), 10, 10)
    local modeText = "MODE: "
    if isZenMode then modeText = modeText .. "ZEN (CPU HIBERNATION)" else modeText = modeText .. "ACTIVE (PHYSICS ON)" end
    if presentationMode and isSettled and isZenMode and arrivalTimer >= 0.3 then
        snapshotBaked = true
    end
end
function love.resize(w, h)
    pendingResize = true
    resizeTimer = 0.2
end
function love.mousemoved(x, y, dx, dy)
    if isMouseCaptured then
        local sensitivity = 0.002
        Cam_Yaw = Cam_Yaw + (dx * sensitivity)
        Cam_Pitch = Cam_Pitch + (dy * sensitivity)
    end
end

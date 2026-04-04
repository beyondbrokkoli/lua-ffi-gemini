require("sys_memory")
local ffi = require("ffi")
local Engine = require("engine")
local SlidesInternal = require("slides_internal")
local Physics = require("sys_physics")
local Renderer = require("sys_renderer")
local floor, ceil, max, min, abs = math.floor, math.ceil, math.max, math.min, math.abs
local random, sqrt, cos, sin, pi, atan2 = math.random, math.sqrt, math.cos, math.sin, math.pi, math.atan2
pendingResize = false
resizeTimer = 0
isFullscreen = true
isMouseCaptured = false
isZenMode = false
local PRESENTATION_ZOOM = 1.0
local CAM_PADDING = 200
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
local function CreateTriObject(x, y, z, vCount, tCount, radius, isKinematic, hasCollision)
local id = NumObjects
NumObjects = NumObjects + 1
Obj_X[id], Obj_Y[id], Obj_Z[id] = x, y, z
Obj_Yaw[id], Obj_Pitch[id] = 0, 0
Obj_Radius[id] = radius or 50
Obj_VertStart[id] = NumTotalVerts; Obj_VertCount[id] = vCount
Obj_TriStart[id] = NumTotalTris; Obj_TriCount[id] = tCount
NumTotalVerts = NumTotalVerts + vCount
NumTotalTris = NumTotalTris + tCount
if isKinematic then
Pool_Kinematic[Pool_Kinematic_Count] = id
Pool_Kinematic_Count = Pool_Kinematic_Count + 1
end
if hasCollision then
Pool_Collider[Pool_Collider_Count] = id
Pool_Collider_Count = Pool_Collider_Count + 1
end
Pool_Solid[Pool_Solid_Count] = id
Pool_Solid_Count = Pool_Solid_Count + 1
return id
end
local function CreateTorus(cx, cy, cz, mainRadius, tubeRadius, segments, sides, baseColor, hasCollision)
baseColor = baseColor or 0xFFFFCC44
local bound = mainRadius + tubeRadius
local vCount = segments * sides
local tCount = segments * sides * 2
local id = CreateTriObject(cx, cy, cz, vCount, tCount, bound, true, hasCollision)
local vStart = Obj_VertStart[id]
local tStart = Obj_TriStart[id]
local r = bit.band(bit.rshift(baseColor, 16), 0xFF)
local g = bit.band(bit.rshift(baseColor, 8), 0xFF)
local b = bit.band(baseColor, 0xFF)
local altColor = 0xFF000000 + bit.lshift(floor(r * 0.6), 16) + bit.lshift(floor(g * 0.6), 8) + floor(b * 0.6)
local vIdx = vStart
for i=0, segments-1 do
local th = (i/segments) * pi * 2
for j=0, sides-1 do
local ph = (j/sides) * pi * 2
Vert_LX[vIdx] = (mainRadius + tubeRadius * cos(ph)) * cos(th)
Vert_LY[vIdx] = tubeRadius * sin(ph)
Vert_LZ[vIdx] = (mainRadius + tubeRadius * cos(ph)) * sin(th)
vIdx = vIdx + 1
end
end
local tIdx = tStart
for i=0, segments-1 do
local i_next = (i+1) % segments
for j=0, sides-1 do
local j_next = (j+1) % sides
local a = (i*sides+j) + vStart
local b_idx = (i_next*sides+j) + vStart
local c = (i_next*sides+j_next) + vStart
local d = (i*sides+j_next) + vStart
local useAlt = (i + j) % 2 == 0
local col = useAlt and baseColor or altColor
Tri_V1[tIdx], Tri_V2[tIdx], Tri_V3[tIdx] = a, c, b_idx
Tri_Color[tIdx] = col
tIdx = tIdx + 1
Tri_V1[tIdx], Tri_V2[tIdx], Tri_V3[tIdx] = a, d, c
Tri_Color[tIdx] = col
tIdx = tIdx + 1
end
end
return id
end
local slideAPI = {
CreateTriObject = CreateTriObject, CreateTorus = CreateTorus,
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
Box_CosA = Box_CosA, Box_SinA = Box_SinA, Box_NX = Box_NX, Box_NZ = Box_NZ,
Sphere_X = Sphere_X, Sphere_Y = Sphere_Y, Sphere_Z = Sphere_Z, Sphere_RSq = Sphere_RSq,
Obj_FWX = Obj_FWX, Obj_FWY = Obj_FWY, Obj_FWZ = Obj_FWZ,
Obj_RTX = Obj_RTX, Obj_RTZ = Obj_RTZ, Obj_UPX = Obj_UPX, Obj_UPY = Obj_UPY, Obj_UPZ = Obj_UPZ,
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
local nx, nz = Box_NX[TargetSlide], Box_NZ[TargetSlide]
local distScale = max(s.h, s.w * (CANVAS_H / CANVAS_W));
local dist = (distScale * Cam_FOV) / CANVAS_H * PRESENTATION_ZOOM + CAM_PADDING
local fx, fy, fz = s.x + nx * dist, s.y, s.z + nz * dist
local bx, by, bz = s.x - nx * dist, s.y, s.z - nz * dist
local dF = (fx - Cam_X)^2 + (fy - Cam_Y)^2 + (fz - Cam_Z)^2
local dB = (bx - Cam_X)^2 + (by - Cam_Y)^2 + (bz - Cam_Z)^2
if dF <= dB then
tX, tY, tZ = fx, fy, fz
tYaw = atan2(s.x - fx, s.z - fz)
else
tX, tY, tZ = bx, by, bz
tYaw = atan2(s.x - bx, s.z - bz)
end
tPitch = s.pitch or 0
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
local displayCount = love.window.getDisplayCount()
local primaryIndex = 1
for i = 1, displayCount do
local x, y = love.window.getPosition(i)
if x == 0 and y == 0 then
primaryIndex = i
break
end
end
local modes = love.window.getFullscreenModes(primaryIndex)
local windowW, windowH = love.window.getDesktopDimensions(primaryIndex)
if #modes > 0 then
windowW = modes[1].width
windowH = modes[1].height
end
local targetOS = love.system.getOS()
local fsType = (targetOS == "Windows") and "exclusive" or "desktop"
love.window.setMode(windowW, windowH, {
fullscreen = true,
fullscreentype = fsType,
display = primaryIndex,
vsync = 0,
centered = true
})
ReinitBuffers(windowW, windowH)
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
SlidesInternal.SpawnDeepSpaceAsteroids(slideAPI, 50)
SlidesInternal.SpawnSpaceAsteroids(slideAPI, 625)
SlidesInternal.CrystalCompanion(slideAPI, NumSlides, 25)
SlidesInternal.SpawnHeroDonut(slideAPI, 1)
SlidesInternal.SpawnChaosCluster(slideAPI, 2, 75)
SlidesInternal.SpawnParticleAccelerator(slideAPI, 3, 75)
SlidesInternal.SpawnChaosCluster(slideAPI, 4, 45)
SlidesInternal.SpawnParticleAccelerator(slideAPI, 5, 45)
SlidesInternal.SpawnHeroDonut(slideAPI, 6)
SlidesInternal.SpawnChaosCluster(slideAPI, 7, 20)
SlidesInternal.SpawnDataSpikes(slideAPI, 300)
BuildCollisionPools()
UpdateCameraBasis()
end
end
function love.keypressed(key)
if not presentationMode and (key == "p" or key == "space") then
lastFreeX, lastFreeY, lastFreeZ, lastFreeYaw, lastFreePitch = Cam_X, Cam_Y, Cam_Z, Cam_Yaw, Cam_Pitch
startX, startY, startZ, startYaw, startPitch = Cam_X, Cam_Y, Cam_Z, Cam_Yaw, Cam_Pitch
lerpT, arrivalTimer = 0, 0
updateTargetSide()
presentationMode = true
elseif key == "i" or key == "u" then
presentationMode = false
if key == "u" then Cam_X, Cam_Y, Cam_Z, Cam_Yaw, Cam_Pitch = lastFreeX, lastFreeY, lastFreeZ, lastFreeYaw, lastFreePitch end
elseif presentationMode and (key == "space" or key == "backspace") then
startX, startY, startZ, startYaw, startPitch = Cam_X, Cam_Y, Cam_Z, Cam_Yaw, Cam_Pitch
lerpT, arrivalTimer = 0, 0
TargetSlide = (key == "space") and ((TargetSlide + 1) % NumSlides) or ((TargetSlide - 1 + NumSlides) % NumSlides)
updateTargetSide()
elseif key == "j" and not presentationMode then
isMouseCaptured = not isMouseCaptured
love.mouse.setRelativeMode(isMouseCaptured)
elseif key == "c" then TriggerChaosField()
elseif key == "v" then TriggerVortex()
elseif key == "g" then TriggerGravity()
elseif key == "z" then
isZenMode = not isZenMode
if presentationMode then
startX, startY, startZ = Cam_X, Cam_Y, Cam_Z
startYaw, startPitch = Cam_Yaw, Cam_Pitch
CAM_PADDING = isZenMode and 0 or 200
lerpT, arrivalTimer = 0, 0
isSettled = false
updateTargetSide()
InitSlideTextCache()
end
elseif key == "escape" then love.event.quit()
end
end
function love.update(dt)
if pendingResize then
resizeTimer = resizeTimer - dt
if resizeTimer <= 0 then
ReinitBuffers(love.graphics.getWidth(), love.graphics.getHeight())
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
lerpT = min(1.0, lerpT + dt * 1)
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
Physics.IntegrateKinematics(dt)
Physics.ResolveCollisions()
local min_dt = 1 / 90
if dt < min_dt then love.timer.sleep(min_dt - dt) end
end
function love.draw()
if pendingResize then
love.graphics.clear(0.05, 0.05, 0.05)
love.graphics.print("REBUILDING SWAPCHAIN...", 20, 20)
return
end
Renderer.DrawFrame()
end
function love.resize(w, h)
pendingResize = true; resizeTimer = 0.2
end
function love.mousemoved(x, y, dx, dy)
if isMouseCaptured then
local sensitivity = 0.002
Cam_Yaw = Cam_Yaw + (dx * sensitivity)
Cam_Pitch = Cam_Pitch + (dy * sensitivity)
end
end

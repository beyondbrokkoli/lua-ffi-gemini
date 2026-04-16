require("sys_memory")
local ffi = require("ffi")
local Engine = require("engine")
local Physics = require("sys_physics")
local Renderer = require("sys_renderer")
local Factory = require("sys_factory")
local SysText = require("sys_text")
local BGB = {}
local floor, ceil, max, min, abs = math.floor, math.ceil, math.max, math.min, math.abs
local random, sqrt, cos, sin, pi, atan2 = math.random, math.sqrt, math.cos, math.sin, math.pi, math.atan2
isFullscreen = true
isMouseCaptured = false
snapshotBaked = false
SlideExposure = 1.0
TERMINAL_W = 1600
TERMINAL_H = 900
TERMINAL_THICKNESS = 40
PRESENTATION_ZOOM = 1.0
local function DiagnoseBGBGaps(bgbData)
print("\n[AUDIT-INFO]: --- BGB GAP DIAGNOSTIC START ---")
local max_num = 0
local num_map = {}
for k, _ in pairs(bgbData) do
local baseNum = tonumber(k:match("^%d+"))
if baseNum then
num_map[baseNum] = true
if baseNum > max_num then
max_num = baseNum
end
end
end
print(string.format("[AUDIT-INFO]: Scanned %d unique keys. Highest paragraph found: § %d", #BGB_Keys, max_num))
local missing_ranges = {}
local current_start = nil
for i = 1, max_num do
if not num_map[i] then
if not current_start then
current_start = i
end
else
if current_start then
if current_start == (i - 1) then
table.insert(missing_ranges, tostring(current_start))
else
table.insert(missing_ranges, current_start .. "-" .. (i - 1))
end
current_start = nil
end
end
end
if current_start then
if current_start == max_num then
table.insert(missing_ranges, tostring(current_start))
else
table.insert(missing_ranges, current_start .. "-" .. max_num)
end
end
print("[AUDIT-INFO]: Missing Base Paragraphs:")
local outStr = table.concat(missing_ranges, ", ")
for line in outStr:gmatch(".{1,80}") do
print("  " .. line)
end
print("[AUDIT-INFO]: --- BGB GAP DIAGNOSTIC END ---\n")
end
local function lerp(a, b, t) return a + (b - a) * t end
local function lerpAngle(a, b, t)
local diff = (b - a + pi) % (pi * 2) - pi
return a + diff * t
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
local sx, sy, sz, nx, ny, nz, w, h
if HUD.open then
local id = HUD_Mesh_ID
sx, sy, sz = Obj_X[id], Obj_Y[id], Obj_Z[id]
nx, ny, nz = Obj_FWX[id], Obj_FWY[id], Obj_FWZ[id]
w, h = TERMINAL_W, TERMINAL_H
else
local id = TargetSlide
if NumSlides == 0 or id >= NumSlides then return end
sx, sy, sz = Box_X[id], Box_Y[id], Box_Z[id]
nx, ny, nz = Box_NX[id], Box_NY[id], Box_NZ[id]
w, h = Box_HW[id] * 2, Box_HH[id] * 2
end
local distScale = math.max(h, w * (CANVAS_H / CANVAS_W))
local pad = 200
if TargetState == STATE_ZEN then pad = 0
elseif TargetState == STATE_OVERVIEW then pad = 6000 end
if HUD.open then pad = 0 end
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
if HUD.open then
SysText.BakeTerminal()
end
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
ReinitBuffers()
love.mouse.setRelativeMode(isMouseCaptured)
Font_UI = love.graphics.newFont(14)
Font_Terminal = love.graphics.newFont(16)
local sceneState = Engine.Boot()
if sceneState then
NumSlides = sceneState.NumSlides
local b = sceneState.bounds
B_MinX, B_MinY, B_MinZ, B_MaxX, B_MaxY, B_MaxZ = b.minX, b.minY, b.minZ, b.maxX, b.maxY, b.maxZ
TargetSlide = 0
updateTargetSide()
Cam_X, Cam_Y, Cam_Z, Cam_Yaw, Cam_Pitch = tX, tY, tZ, tYaw, tPitch
startX, startY, startZ, startYaw, startPitch = tX, tY, tZ, tYaw, tPitch
lastFreeX, lastFreeY, lastFreeZ, lastFreeYaw, lastFreePitch = Cam_X, Cam_Y, Cam_Z, Cam_Yaw, Cam_Pitch
SysText.InitSlideTextCache(sceneState.textPayload)
BuildCollisionPools()
UpdateCameraBasis()
SysText.BakeTerminal()
Renderer.BakeStaticLighting()
HUD_Mesh_ID = Factory.CreateTerminalSlide(0, 8000, 0, TERMINAL_W, TERMINAL_H, TERMINAL_THICKNESS, C_LATTE)
local tStart = Obj_TriStart[HUD_Mesh_ID]
for t = 0, Obj_TriCount[HUD_Mesh_ID] - 1 do
Tri_BaseLight[tStart + t] = 0.36
end
end
BGB = require("bgb")
BGB_Keys = {}
for k in pairs(BGB) do table.insert(BGB_Keys, k) end
table.sort(BGB_Keys, function(a, b)
local numA = tonumber(a:match("%d+")) or 0
local numB = tonumber(b:match("%d+")) or 0
if numA == numB then
return a < b
end
return numA < numB
end)
CurrentBGBIndex = 1
DiagnoseBGBGaps(BGB)
end
local function ExecuteSlideTransition()
if EngineState == STATE_ZEN or EngineState == STATE_HIBERNATED then
updateTargetSide()
Cam_X, Cam_Y, Cam_Z, Cam_Yaw, Cam_Pitch = tX, tY, tZ, tYaw, tPitch
EngineState = STATE_ZEN
TargetState = STATE_ZEN
activeSlide = TargetSlide
SysText.Alpha = 1.0
snapshotBaked = false
else
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
if HUD.open then
if key == "up" or key == "down" then
local dir = (key == "up") and -1 or 1
HUD.scroll = math.max(0, (HUD.scroll or 0) + (dir * 150))
if HUD.max_scroll then
HUD.scroll = math.min(HUD.scroll, HUD.max_scroll)
end
SysText.BakeTerminal()
snapshotBaked = false
elseif key == "left" or key == "right" then
if #BGB_Keys > 0 then
local dir = (key == "left") and -1 or 1
CurrentBGBIndex = math.max(1, math.min(#BGB_Keys, CurrentBGBIndex + dir))
local target = BGB_Keys[CurrentBGBIndex]
HUD.scroll = 0;
HUD.lines = { c_cyan .. "> BGB SEARCH: § " .. target .. c_reset, BGB[target].title, "---", BGB[target].text }
SysText.BakeTerminal()
snapshotBaked = false
end
end
else
local COLS = 16
local row = math.floor(TargetSlide / COLS)
local col = TargetSlide % COLS
local row_start = row * COLS
local oldTarget = TargetSlide
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
end
elseif key == "i" or key == "u" then
EngineState = STATE_FREEFLY; TargetState = STATE_FREEFLY
if key == "u" then Cam_X, Cam_Y, Cam_Z, Cam_Yaw, Cam_Pitch = lastFreeX, lastFreeY, lastFreeZ, lastFreeYaw, lastFreePitch end
elseif EngineState ~= STATE_FREEFLY and (key == "space" or key == "backspace") then
if key == "space" and TargetState == STATE_OVERVIEW then
TargetState = STATE_PRESENT; TriggerContinuousFlight()
else
TargetSlide = (key == "space") and ((TargetSlide + 1) % NumSlides) or ((TargetSlide - 1 + NumSlides) % NumSlides)
ExecuteSlideTransition()
end
elseif key == "j" and EngineState == STATE_FREEFLY then
isMouseCaptured = not isMouseCaptured
love.mouse.setRelativeMode(isMouseCaptured)
elseif key == "c" then Physics.TriggerChaosField()
elseif key == "v" then Physics.TriggerVortex()
elseif key == "g" then Physics.TriggerGravity()
elseif key == "tab" then
HUD.open = not HUD.open
if HUD.open then HUD.scroll = 0 end
ExecuteSlideTransition()
elseif key == "z" then
if EngineState == STATE_FREEFLY then return end
if EngineState == STATE_PRESENT or EngineState == STATE_OVERVIEW then TargetState = STATE_ZEN; else TargetState = STATE_PRESENT end
TriggerContinuousFlight()
elseif key == "+" or key == "kp+" then
SlideExposure = math.min(3.0, SlideExposure + 0.1); snapshotBaked = false
elseif key == "-" or key == "kp-" then
SlideExposure = math.max(0.1, SlideExposure - 0.1); snapshotBaked = false
elseif key == "escape" then love.event.quit() end
if key:match("^[1-9]$") then
local para_map = {["1"]="611", ["2"]="611a", ["3"]="620", ["4"]="622", ["5"]="623", ["6"]="626"}
local target = para_map[key]
if target and BGB[target] then
if BGB_Keys then
for i, k in ipairs(BGB_Keys) do
if k == target then CurrentBGBIndex = i; break; end
end
end
HUD.open = true
HUD.scroll = 0
HUD.lines = { c_cyan .. "> BGB SEARCH: § " .. target .. c_reset, BGB[target].title, "---", BGB[target].text }
ExecuteSlideTransition()
end
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
SysText.BakeTerminal()
pendingResize = false
end
return
end
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
EngineState = TargetState
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
local isTextReady = SysText.Update(EngineState, dt)
if SysText.Alpha <= 0.01 then
activeSlide = TargetSlide
end
if EngineState == STATE_HIBERNATED then
if snapshotBaked then love.timer.sleep(0.25) end
else
snapshotBaked = false
end
if EngineState == STATE_ZEN and isTextReady then
EngineState = STATE_HIBERNATED
end
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
function love.wheelmoved(x, y)
if HUD.open then
HUD.scroll = math.max(0, (HUD.scroll or 0) - (y * 100))
if HUD.max_scroll then
HUD.scroll = math.min(HUD.scroll, HUD.max_scroll)
end
SysText.BakeTerminal()
snapshotBaked = false
end
end

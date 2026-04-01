local ffi = require("ffi")
local bit = require("bit")
local floor, ceil, max, min, abs = math.floor, math.ceil, math.max, math.min, math.abs
local random, sqrt, cos, sin = math.random, math.sqrt, math.cos, math.sin
local Physics = {}
function Physics.IntegrateKinematics(dt)
for i = 0, Pool_Kinematic_Count - 1 do
local id = Pool_Kinematic[i]
Obj_X[id] = Obj_X[id] + Obj_VelX[id] * dt
Obj_Y[id] = Obj_Y[id] + Obj_VelY[id] * dt
Obj_Z[id] = Obj_Z[id] + Obj_VelZ[id] * dt
local yaw = Obj_Yaw[id] + Obj_RotSpeedYaw[id] * dt
local pitch = Obj_Pitch[id] + Obj_RotSpeedPitch[id] * dt
Obj_Yaw[id], Obj_Pitch[id] = yaw, pitch
local cy, sy = cos(yaw), sin(yaw)
local cp, sp = cos(pitch), sin(pitch)
local fwx, fwy, fwz = sy * cp, sp, cy * cp
local rtx, rtz = cy, -sy
Obj_FWX[id], Obj_FWY[id], Obj_FWZ[id] = fwx, fwy, fwz
Obj_RTX[id], Obj_RTZ[id] = rtx, rtz
Obj_UPX[id] = fwy * rtz
Obj_UPY[id] = fwz * rtx - fwx * rtz
Obj_UPZ[id] = -fwy * rtx
end
end
function Physics.ResolveCollisions()
for i = 0, Pool_SlideCollider_Count - 1 do
local id = Pool_SlideCollider[i]
local px, py, pz = Obj_X[id], Obj_Y[id], Obj_Z[id]
local vx, vy, vz = Obj_VelX[id] * 0.999, Obj_VelY[id] * 0.999, Obj_VelZ[id] * 0.999
Obj_RotSpeedYaw[id] = Obj_RotSpeedYaw[id] * 0.998
Obj_RotSpeedPitch[id] = Obj_RotSpeedPitch[id] * 0.998
if px < B_MinX then px = B_MinX; vx = abs(vx) end
if px > B_MaxX then px = B_MaxX; vx = -abs(vx) end
if py < B_MinY then py = B_MinY; vy = abs(vy) end
if py > B_MaxY then py = B_MaxY; vy = -abs(vy) end
if pz < B_MinZ then pz = B_MinZ; vz = abs(vz) end
if pz > B_MaxZ then pz = B_MaxZ; vz = -abs(vz) end
local homeIdx = Obj_HomeIdx[id]
local sdx, sdy, sdz = px - Sphere_X[homeIdx], py - Sphere_Y[homeIdx], pz - Sphere_Z[homeIdx]
local srSq = Sphere_RSq[homeIdx]
local distSq = sdx*sdx + sdy*sdy + sdz*sdz
if distSq > srSq then
local dist = sqrt(distSq)
local snx, sny, snz = sdx/dist, sdy/dist, sdz/dist
local dot = vx*snx + vy*sny + vz*snz
if dot > 0 then
local impulse = 1.75 * dot
vx, vy, vz = vx - impulse * snx, vy - impulse * sny, vz - impulse * snz
Obj_RotSpeedYaw[id] = Obj_RotSpeedYaw[id] * 0.99 + (random() - 0.5) * 2
Obj_RotSpeedPitch[id] = Obj_RotSpeedPitch[id] * 0.99 + (random() - 0.5) * 2
end
local pen = dist - sqrt(srSq) + 2
px, py, pz = px - snx * pen, py - sny * pen, pz - snz * pen
end
local bx, by, bz = Box_X[homeIdx], Box_Y[homeIdx], Box_Z[homeIdx]
local bnx, bnz = Box_NX[homeIdx], Box_NZ[homeIdx]
local localX = (px - bx) * bnz - (pz - bz) * bnx
local localZ = (px - bx) * bnx + (pz - bz) * bnz
local dy = py - by
if abs(localX) < Box_HW[homeIdx] + 35 and abs(dy) < Box_HH[homeIdx] + 35 and abs(localZ) < Box_HT[homeIdx] + 35 then
local sign = localZ > 0 and 1 or -1
localZ = (Box_HT[homeIdx] + 40) * sign
px = bx + (localX * bnz + localZ * bnx)
pz = bz + (localX * -bnx + localZ * bnz)
py = by + dy
local vDotN = vx * bnx + vz * bnz
if (vDotN * sign) < 0 then
local impulse = 1.5 * vDotN
vx, vz = vx - impulse * bnx, vz - impulse * bnz
Obj_RotSpeedYaw[id] = Obj_RotSpeedYaw[id] * 0.99
end
end
Obj_VelX[id], Obj_VelY[id], Obj_VelZ[id] = max(-2000, min(2000, vx)), max(-2000, min(2000, vy)), max(-2000, min(2000, vz))
Obj_X[id], Obj_Y[id], Obj_Z[id] = px, py, pz
end
for i = 0, Pool_DeepSpace_Count - 1 do
local id = Pool_DeepSpace[i]
local px, py, pz = Obj_X[id], Obj_Y[id], Obj_Z[id]
local vx, vy, vz = Obj_VelX[id] * 0.999, Obj_VelY[id] * 0.999, Obj_VelZ[id] * 0.999
Obj_RotSpeedYaw[id] = Obj_RotSpeedYaw[id] * 0.998
Obj_RotSpeedPitch[id] = Obj_RotSpeedPitch[id] * 0.998
if px < B_MinX then px = B_MinX; vx = abs(vx) end
if px > B_MaxX then px = B_MaxX; vx = -abs(vx) end
if py < B_MinY then py = B_MinY; vy = abs(vy) end
if py > B_MaxY then py = B_MaxY; vy = -abs(vy) end
if pz < B_MinZ then pz = B_MinZ; vz = abs(vz) end
if pz > B_MaxZ then pz = B_MaxZ; vz = -abs(vz) end
for s = 0, NumSlides - 1 do
local bx, by, bz = Box_X[s], Box_Y[s], Box_Z[s]
local bnx, bnz = Box_NX[s], Box_NZ[s]
local localX = (px - bx) * bnz - (pz - bz) * bnx
local localZ = (px - bx) * bnx + (pz - bz) * bnz
local dy = py - by
if abs(localX) < Box_HW[s] + 35 and abs(dy) < Box_HH[s] + 35 and abs(localZ) < Box_HT[s] + 35 then
local sign = localZ > 0 and 1 or -1
localZ = (Box_HT[s] + 40) * sign
px = bx + (localX * bnz + localZ * bnx)
pz = bz + (localX * -bnx + localZ * bnz)
py = by + dy
local vDotN = vx * bnx + vz * bnz
if (vDotN * sign) < 0 then
local impulse = 1.5 * vDotN
vx, vz = vx - impulse * bnx, vz - impulse * bnz
Obj_RotSpeedYaw[id] = Obj_RotSpeedYaw[id] * 0.99
end
end
end
Obj_VelX[id], Obj_VelY[id], Obj_VelZ[id] = max(-2000, min(2000, vx)), max(-2000, min(2000, vy)), max(-2000, min(2000, vz))
Obj_X[id], Obj_Y[id], Obj_Z[id] = px, py, pz
end
end
return Physics

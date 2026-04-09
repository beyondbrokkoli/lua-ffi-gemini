local ffi = require("ffi")
local Factory = require("sys_factory")
local Engine = {
terminal = { open = false, scroll = 0, lines = {} }
}
local minX, minY, minZ = 1e30, 1e30, 1e30
local maxX, maxY, maxZ = -1e30, -1e30, -1e30
local C_CREAM = 4294306522
local C_LATTE = 4292131280
local RADIUS = 7500
local templates = {
{
text = "THE DESTRUCTOR",
content = {
"~ # PERSONALKÜNDIGUNG",
"",
"~ § 611a: The Constructor. | § 620: The Destructor.",
"~ Instantiates an employment. | Defines how it ceases to exist.",
"",
"Absatz 1: The Timer Runs Out",
"If a contract has a fixed term, it self-terminates.",
"No action is required. The system cleans it up naturally."
}
},
{
text = "SHADOWED FOREST",
content = {
"~ # THE PATH THAT DOES NOT STRAY",
"",
"\"I found myself within a shadowed forest,",
"~ for I had lost the path that does not stray...\"",
"",
"§ 620 Absatz 2 BGB | The Open-Ended Loop",
"Most contracts run forever. | To break the loop, we must enter the thicket.",
"",
"~ §§ 621 to 626: The manual override protocols."
}
},
{
text = "THE TRILOGY",
content = {
"~ # THE TRILOGY OF EXITS",
"",
"Ordentlich (§ 622) | Außerordentlich (§ 626)",
"Unilateral: The Cooldown. | Unilateral: The Hard Reset.",
"",
"Aufhebungsvertrag | The Negotiated Surrender",
"Bilateral: Mutual consent.",
"Triggers a 12-week penalty block at the Arbeitsamt."
}
},
{
text = "THE COOLDOWN",
content = {
"~ # THE COOLDOWN (§ 622 BGB)",
"",
"~ The standard administrative procedure.",
"",
"Tenure Armor | Scaling Notice Periods",
"The longer you survive, | the longer the employer's cooldown.",
"",
"Max Level | 7 Months",
"After 20 years, the employer must wait 7 months to the end of a month."
}
},
{
text = "HARD RESET",
content = {
"~ # THE HARD RESET (§ 626 BGB)",
"",
"~ Fristlose Kündigung aus wichtigem Grund.",
"",
"Instant Termination | Bypasses the standard notice period.",
"Wichtiger Grund | Requires severe misconduct (e.g., theft, violence).",
"",
"~ Warning: This is an overpowered mechanic.",
"~ The system requires strict validation checks to execute."
}
},
{
text = "VALIDATION",
content = {
"~ # STRICT VALIDATION CHECKS",
"",
"§ 623: The Format Validator | Wet Ink Only",
"Digital inputs (WhatsApp, Email) throw a syntax error and are void.",
"",
"§ 626 Abs. 2: The 14-Day Timer | Strict Execution Window",
"Incident discovered? You have exactly two weeks to trigger the reset.",
"Missed the window? Fallback to standard cooldown required."
}
},
{
text = "TRUST METER",
content = {
"~ # THE TRUST METER (ABMAHNUNG)",
"",
"~ You rarely trigger a hard reset without a warning.",
"",
"The Yellow Card | Verhaltensbedingte Kündigung",
"Documents specific bugs in behavior. | Warns of system termination.",
"",
"Proportionality | Verhältnismäßigkeit",
"You cannot use maximum force on a minor error. | Escalate logically."
}
},
{
text = "DAMAGE CHECK",
content = {
"~ # THE DAMAGE CHECK",
"",
"~ SOURCE CODE: § 626 Abs. 1 BGB",
"",
"'Nicht zugemutet werden kann' | Cannot be reasonably expected.",
"",
"The Stat Check | High Difficulty",
"Employer must prove that keeping the employee for even 4 more weeks",
"causes unreasonable, catastrophic damage to the operation."
}
},
{
text = "AZUBI ARMOR",
content = {
"~ # BESONDERER SCHUTZ: AZUBIS",
"",
"~ § 113 BGB vs. § 22 BBiG",
"",
"Minor Worker (e.g., 17) | Can quit easily (Generaleinwilligung).",
"Apprentice (Azubi) | Locked in. Needs double parental signature.",
"",
"After Probation | Invincibility Frames",
"Standard employer termination is effectively disabled by the BBiG."
}
},
{
text = "BOSS FIGHT",
content = {
"~ # DER FALL 'EMMELY'",
"",
"~ BAG-Urteil (2010): 2 AZR 541/09",
"",
"The Player | 31 years of flawless service as a cashier.",
"The Incident | Redeemed two found deposit receipts worth 1.30€.",
"",
"The Employer's Play | Triggered the Hard Reset (§ 626).",
"Argument | Theft is theft. Trust is permanently destroyed."
}
},
{
text = "THE RULING",
content = {
"~ # THE SUPREME COURT RULING",
"",
"~ The Reversal (2010)",
"",
"The Trust Buffer | Decades of Loyalty",
"31 flawless years build massive trust. | 1.30€ cannot instantly one-shot it.",
"",
"The Verdict | Termination Invalid",
"Employer failed the mechanics. | An 'Abmahnung' was required."
}
},
{
text = "POST-GAME",
content = {
"~ # POST-GAME LOOT & FAZIT",
"",
"~ Memory Leaks and Garbage Collection",
"",
"§ 629: The Job Hunt Buff | Employer must grant paid time off to interview.",
"§ 630: The Final Log File | The Zeugnis (Simple or Advanced).",
"",
"~ The BGB is a highly regulated message-passing architecture.",
"~ Know your cooldowns. Read the logs. Master the system."
}
}
}
local function BuildSlideMesh(x, y, z, w, h, thickness, color)
local id = Factory.CreateTriObject(x, y, z, 8, 12, 2000, false, false, false)
local vStart = Obj_VertStart[id]
local tStart = Obj_TriStart[id]
local hw, hh, ht = w * 0.5, h * 0.5, thickness * 0.5
local verts = {
{-hw, -hh, -ht}, {hw, -hh, -ht}, {hw, hh, -ht}, {-hw, hh, -ht},
{-hw, -hh, ht}, {hw, -hh, ht}, {hw, hh, ht}, {-hw, hh, ht}
}
for i = 1, 8 do
Vert_LX[vStart + (i - 1)] = verts[i][1]
Vert_LY[vStart + (i - 1)] = verts[i][2]
Vert_LZ[vStart + (i - 1)] = verts[i][3]
end
local indices = {
0,2,1, 0,3,2, 4,5,6, 4,6,7, 0,1,5, 0,5,4,
1,2,6, 1,6,5, 2,3,7, 2,7,6, 3,0,4, 3,4,7
}
for i = 1, #indices, 3 do
local tIdx = tStart + math.floor((i - 1) / 3)
Tri_V1[tIdx] = indices[i] + vStart
Tri_V2[tIdx] = indices[i+1] + vStart
Tri_V3[tIdx] = indices[i+2] + vStart
Tri_Color[tIdx] = color
end
return id
end
local function ProcessSlideNode(id, data)
local w = data.w or 1600
local h = data.h or 900
local thickness = data.thickness or 40
local color = data.color or 0xFFFFFFFF
local hw, hh, ht = w * 0.5, h * 0.5, thickness * 0.5
local px, py, pz = data.x, data.y, data.z
minX, maxX = math.min(minX, px - hw), math.max(maxX, px + hw)
minY, maxY = math.min(minY, py - hh), math.max(maxY, py + hh)
minZ, maxZ = math.min(minZ, pz - ht), math.max(maxZ, pz + ht)
local yaw = data.yaw or 0
local pitch = math.max(-1.56, math.min(1.56, data.pitch or 0))
local cy, sy = math.cos(yaw), math.sin(yaw)
local cp, sp = math.cos(pitch), math.sin(pitch)
local fwx, fwy, fwz = sy * cp, sp, cy * cp
local rtx, rty, rtz = cy, 0, -sy
local upx = fwy * rtz
local upy = fwz * rtx - fwx * rtz
local upz = -fwy * rtx
Box_X[id], Box_Y[id], Box_Z[id] = px, py, pz
Box_HW[id], Box_HH[id], Box_HT[id] = hw, hh, ht
Box_CosA[id], Box_SinA[id] = cy, sy
Box_NX[id], Box_NY[id], Box_NZ[id] = fwx, fwy, fwz
Box_FWX[id], Box_FWY[id], Box_FWZ[id] = fwx, fwy, fwz
Box_RTX[id], Box_RTY[id], Box_RTZ[id] = rtx, 0, rtz
Box_UPX[id], Box_UPY[id], Box_UPZ[id] = upx, upy, upz
local halfDiag = math.sqrt(hw^2 + hh^2 + ht^2)
Sphere_X[id], Sphere_Y[id], Sphere_Z[id] = px, py, pz
Sphere_RSq[id] = (halfDiag + 100)^2
local mId = BuildSlideMesh(px, py, pz, w, h, thickness, color)
print(string.format("[AUDIT-INFO]: Mesh Spawner created Object %d for Slide %d", mId, id))
Obj_X[mId], Obj_Y[mId], Obj_Z[mId] = px, py, pz
Obj_Yaw[mId], Obj_Pitch[mId] = yaw, pitch
Obj_FWX[mId], Obj_FWY[mId], Obj_FWZ[mId] = fwx, fwy, fwz
Obj_RTX[mId], Obj_RTY[mId], Obj_RTZ[mId] = rtx, rty, rtz
Obj_UPX[mId], Obj_UPY[mId], Obj_UPZ[mId] = upx, upy, upz
end
function Engine.Boot()
print("[AUDIT-INFO]: Booting Self-Compiling Engine...")
local count = 0
local textPayload = {}
for i = 0, #templates - 1 do
local id = i
local template = templates[i + 1]
local yaw = i * (math.pi / 6)
local x = math.sin(yaw) * RADIUS
local y = 0
local z = math.cos(yaw) * RADIUS
local slideColor = (i % 2 == 0) and C_CREAM or C_LATTE
local node = {
w = 1600, h = 900, thickness = 40 + (i % 3) * 10,
x = x, y = y, z = z,
yaw = yaw, pitch = 0,
color = slideColor
}
ProcessSlideNode(id, node)
textPayload[id] = {
title = string.format("%02d: %s", i + 1, template.text),
content = template.content
}
count = count + 1
end
print(string.format("[AUDIT-INFO]: Assembly Line Complete. %d Slides Built.", count))
return {
textPayload = textPayload,
NumSlides = count,
bounds = {
minX = minX - 8000, minY = minY - 8000, minZ = minZ - 8000,
maxX = maxX + 8000, maxY = maxY + 8000, maxZ = maxZ + 8000
}
}
end
return Engine

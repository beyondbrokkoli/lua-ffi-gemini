local ffi = require("ffi")
local Factory = require("sys_factory")

local Engine = {
    terminal = { open = false, scroll = 0, lines = {} }
}

-- Bounding Box Tracking for the whole scene
local minX, minY, minZ = 1e30, 1e30, 1e30
local maxX, maxY, maxZ = -1e30, -1e30, -1e30

-- COFFEE PALETTE
local C_CREAM = 4294306522 -- 0xFFF5EADA
local C_LATTE = 4292131280 -- 0xFFEAE0D0
local RADIUS = 7500

-- CONTENT TEMPLATES (The 12-Slide BGB Boss Fight)
local templates = {
    { text = "THE ELEPHANT", content = {"~ # THE ELEPHANT IN THE ROOM", "", "~ I called in sick.", "~ I came back to the topic 'Personalkündigung'.", "", "A psychological debuff? | A subtle warning?", "", "~ Management thinks the BGB is a weapon.", "~ But we are going to look at the actual patch notes."} },
    { text = "THE 3 EXITS", content = {"~ # THE GAME THEORY OF TERMINATION", "", "Ordentlich (§ 622 BGB) | The Cooldown", "Standard exit strategy. | Bound by strict time limits.", "", "Außerordentlich (§ 626 BGB) | The Nuke", "Immediate termination. | Requires massive breach of trust.", "", "Aufhebungsvertrag | The Negotiated Surrender", "Mutual agreement to quit. | Warning: Triggers 'Arbeitsamt' debuff."} },
    { text = "ORDENTLICH", content = {"~ # THE COOLDOWN (§ 622 BGB)", "", "~ Playing by the standard rules.", "", "The Notice Period | Respecting the Timer", "A graceful exit. | No explicit reason required from the employee.", "", "Constitutional Right | Article 12 GG", "Berufsfreiheit. | If you can't quit gracefully, it's forced labor."} },
    { text = "THE NUKE", content = {"~ # THE NUKE (§ 626 BGB)", "", "~ Fristlose Kündigung: The Movie Moment.", "", "'Pack your desk right now.' | Bypasses the cooldown timer.", "", "The Condition | Wichtiger Grund", "Requires severe misconduct. | Violence, theft, or extreme insults."} },
    { text = "THE SURRENDER", content = {"~ # THE NEGOTIATED SURRENDER", "", "~ Aufhebungsvertrag: The Golden Handshake.", "", "Constructive Dismissal | 'Expected to quit'", "Boss creates hostile environment? | Illegal.", "", "The Abfindung | The Severance", "Get paid to leave quietly. | But beware the 12-week block."} },
    { text = "THE TRUST METER", content = {"~ # THE TRUST METER (ABMAHNUNG)", "", "~ You cannot drop the Nuke without a target lock.", "", "The Yellow Card | Documented Strikes", "Minor offenses require warnings. | Warns of contract termination.", "", "Proportionality | The Law of Balance", "You cannot nuke a fly. | Use the lowest effective force."} },
    { text = "THE DAMAGE CHECK", content = {"~ # THE DAMAGE CHECK", "", "~ SOURCE CODE: § 626 Abs. 1 BGB", "", "'...nicht zugemutet werden kann.' | Cannot be reasonably expected.", "", "The Stat Check | High Difficulty", "Must prove keeping you for 4 weeks | causes catastrophic damage."} },
    { text = "ANTI-RAGE-QUIT", content = {"~ # THE ANTI-RAGE-QUIT MECHANIC", "", "~ SOURCE CODE: § 626 Abs. 2 BGB", "", "The 14-Day Timer | Strict Window", "Boss finds out about misconduct? | They have exactly two weeks.", "", "Miss the window? | The Nuke is deactivated.", "The offense is wiped from active cache. | Must use ordinary cooldown."} },
    { text = "THE MEHMET TRAP", content = {"~ # THE MEHMET TRAP", "", "~ The Friction: § 113 BGB vs. § 22 BBiG", "", "Jasmin (17, Job) | Can quit alone (Generaleinwilligung)", "Mehmet (17, Azubi) | Locked in. Needs parents' double signature.", "", "Azubi God-Mode | Invincibility Frames", "After probation, standard firing is disabled. | You are wearing plot armor."} },
    { text = "THE BOSS FIGHT", content = {"~ # THE 1.30€ BOSS FIGHT", "", "~ Der Emmely-Fall (BAG: 2 AZR 541/09)", "", "The Player | 31 years of flawless loyalty.", "The Crime | Kept two deposit receipts worth 1.30€.", "", "The Employer's Play | Dropped the Nuke.", "Theft is theft. | Instant termination."} },
    { text = "THE RULING", content = {"~ # THE SUPREME COURT RULING", "", "~ The Reversal (2010)", "", "The Trust Buffer | Decades of Loyalty", "31 flawless years creates massive trust. | 1.30€ cannot instantly one-shot it.", "", "The Verdict | Termination Invalid", "Employer failed the mechanics. | An 'Abmahnung' was required."} },
    { text = "THE META", content = {"~ # MASTERING THE META", "", "~ Personalkündigung is not an execution.", "", "The Burden of Proof | Lies with the Employer", "The system prevents emotional firing. | Mathematical precision.", "", "The Balance Patch | BGB & BBiG", "Protects the young from rash choices. | Protects veterans from ruthless cuts.", "", "~ Know your cooldowns. Know your shields. Play the game."} }
}

-- ==========================================
-- GEOMETRY BUILDER
-- ==========================================
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

-- ==========================================
-- SELF-COMPILING BOOT SEQUENCE
-- ==========================================
function Engine.Boot()
    print("[AUDIT-INFO]: Booting Self-Compiling Engine...")
    
    local count = 0
    local textPayload = {}
    
    for i = 0, #templates - 1 do
        local id = i
        local template = templates[i + 1]
        
        -- The Dynamic Topology Math
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

local ffi = require("ffi")
local bit = require("bit")
local SlideGuard = require("slide_guard")
local json = require("dkjson")
local Engine = { manifest = {}, terminal = { open = false, scroll = 0, lines = {} }, api = nil }
local function Topology_VoidHelix(id)
    local x = math.sin(id * 0.5) * 2000
    local y = id * -800
    local z = id * -10000
    local yaw = id * 0.2
    local pitch = math.sin(id) * 0.2
    return x, y, z, yaw, pitch
end
local function Topology_Panopticon(id)
    local SLIDES_PER_RING = 8
    local yaw = (id % SLIDES_PER_RING) * (math.pi / 4)
    local row = math.floor(id / SLIDES_PER_RING)
    local pitch = row * 0.35
    local cy, sy = math.cos(yaw), math.sin(yaw)
    local cp, sp = math.cos(pitch), math.sin(pitch)
    local radius = 7000
    return (sy * cp) * radius, sp * radius, (cy * cp) * radius, yaw, pitch
end
local ActiveTopology = Topology_Panopticon
function Engine.Boot(raw_api, json_path)
    Engine.api = SlideGuard.ProtectAPI(raw_api)
    local content, sizeOrErr = love.filesystem.read(json_path)
    if content then
        local data, pos, err = json.decode(content)
        if not err then
            Engine.manifest = data
        else
            print("[FATAL] JSON Parse Error: " .. tostring(err))
        end
    else
        print("[FATAL] Could not find " .. json_path .. " in virtual filesystem!")
    end
    if SlideGuard.PreflightCheck(Engine.manifest, 100) then
        local count, bounds = Engine.SyncGeometry()
        return { manifest = Engine.manifest, NumSlides = count, bounds = bounds }
    end
    return nil
end
function Engine.SyncGeometry()
    local clean_manifest = {}
    local count = 0
    local keys = {}
    for k in pairs(Engine.manifest) do table.insert(keys, k) end
    table.sort(keys, function(a, b) return tonumber(a) < tonumber(b) end)
    local SLIDE_DEFAULTS = { color = 0xFFFFFFFF }
    for i, original_key in ipairs(keys) do
        local id = i - 1
        local raw_node = Engine.manifest[original_key]
        local node = SlideGuard.deep_merge(SLIDE_DEFAULTS, raw_node)
        local px, py, pz, pyaw, ppitch = ActiveTopology(id)
        node.x, node.y, node.z = px, py, pz
        node.yaw, node.pitch = pyaw, ppitch
        node.w, node.h, node.thickness = 1600, 900, 40
        clean_manifest[id] = node
        Engine.api.RegisterGeometry(id, node)
        count = count + 1
    end
    Engine.manifest = clean_manifest
    return count, Engine.api.GetFinalBounds(8000)
end
function Engine.RefreshTerminal()
    Engine.terminal.lines = {}
    SlideGuard.WalkSceneData(Engine.manifest, function(k, v, depth, isTable)
        local indent = string.rep(" ", depth)
        local line = isTable and (indent .. k .. ":") or (indent .. k .. ": " .. tostring(v))
        table.insert(Engine.terminal.lines, line)
    end)
end
function Engine.DrawTerminal(ScreenPtr, CANVAS_W, CANVAS_H)
    if not Engine.terminal.open then return end
    local termWidth = math.floor(CANVAS_W * 0.4)
    for y = 0, CANVAS_H - 1 do
        local offset = y * CANVAS_W
        for x = 0, termWidth do
            local p = ScreenPtr[offset + x]
            ScreenPtr[offset + x] = bit.bor(bit.band(p, 0x00FEFEFE), 0x7F000000)
        end
    end
end
return Engine

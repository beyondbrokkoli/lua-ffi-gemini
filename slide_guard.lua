local ffi = require("ffi")
local Internal = require("slides_internal")
local SlideGuard = {}
local _internal_state = { faults = 0, registrations = 0, last_audit_depth = 0 }
local function audit(level, msg) print(string.format("[AUDIT-%s]: %s", level, msg))
end
local function deep_copy(obj) if type(obj) ~= "table" then return obj end
    local res = {}
    for k, v in pairs(obj) do res[deep_copy(k)] = deep_copy(v) end
    return res
end
local function deep_merge(base, overlay) if not overlay then return deep_copy(base) end
    local res = deep_copy(base)
    for k, v in pairs(overlay) do if type(v) == "table" and type(res[k]) == "table" then res[k] = deep_merge(res[k], v)
        else res[k] = deep_copy(v)
        end end
    return res
end
function SlideGuard.WalkSceneData(data, f, depth) depth = depth or 0
    local isArray = next(data) == 1
    for k, v in (isArray and ipairs or pairs)(data) do if type(v) == "table" then f(k, nil, depth, true, isArray)
            SlideGuard.WalkSceneData(v, f, depth + 1)
        else f(k, v, depth, false, isArray) end end
end
local function safe_execute(func, ...) local success, result = xpcall(func, debug.traceback, ...)
    if not success then _internal_state.faults = _internal_state.faults + 1
        audit("CRITICAL", "Scene Logic Faulted: \n" .. tostring(result))
        return nil, result
    end
    return result
end
function SlideGuard.PreflightCheck(manifest, max_slides) audit("INFO", "Validating Scene Manifest against Geometry Constraints.")
    if type(manifest) ~= "table" then audit("FATAL", "Manifest must be a Table-based Structure.")
        return false
    end
    local verified = 0
    for id, node in pairs(manifest) do if type(id) ~= "number" or id < 0 or id >= max_slides then audit("WARN", string.format("Index [%s] out of FFI buffer bounds.", tostring(id)))
        elseif not node.x or not node.w or not node.h then audit("WARN", string.format("Node [%d] missing Transform/Scale data.", id))
        else verified = verified + 1
        end end
    audit("INFO", string.format("Preflight Complete: %d nodes verified.", verified))
    return verified > 0
end
function SlideGuard.ProtectAPI(raw_api) local guarded_api = {}
    local mesh_map = {}
    local minX, minY, minZ = 1e30, 1e30, 1e30
    local maxX, maxY, maxZ = -1e30, -1e30, -1e30
    function guarded_api.RegisterGeometry(id, data) return safe_execute(function() local hw, hh, ht = (data.w or 1600) * 0.5, (data.h or 900) * 0.5, data.thickness or 120
            minX, maxX = math.min(minX, data.x - hw), math.max(maxX, data.x + hw)
            minY, maxY = math.min(minY, data.y - hh), math.max(maxY, data.y + hh)
            minZ, maxZ = math.min(minZ, data.z - ht), math.max(maxZ, data.z + ht)
            raw_api.Box_X[id], raw_api.Box_Y[id], raw_api.Box_Z[id] = data.x, data.y, data.z
            raw_api.Box_HW[id], raw_api.Box_HH[id], raw_api.Box_HT[id] = hw, hh, ht
            local angle = data.yaw or 0
            raw_api.Box_CosA[id] = math.cos(angle)
            raw_api.Box_SinA[id] = math.sin(angle)
            raw_api.Box_NX[id] = math.sin(angle)
            raw_api.Box_NZ[id] = math.cos(angle)
            local halfDiag = math.sqrt(hw^2 + hh^2 + ht^2)
            raw_api.Sphere_X[id] = data.x
            raw_api.Sphere_Y[id] = data.y
            raw_api.Sphere_Z[id] = data.z
            raw_api.Sphere_RSq[id] = (halfDiag + 100)^2
            if not mesh_map[id] then mesh_map[id] = Internal.BuildSlideMesh(raw_api, id, data)
                audit("INFO", string.format("Mesh Spawner: Created Object for Slide %d", id))
            end
            local mId = mesh_map[id]
            raw_api.Obj_X[mId], raw_api.Obj_Y[mId], raw_api.Obj_Z[mId] = data.x, data.y, data.z
            raw_api.Obj_Yaw[mId] = angle
            raw_api.Obj_Pitch[mId] = 0
            local cy, sy = math.cos(angle), math.sin(angle)
            raw_api.Obj_FWX[mId], raw_api.Obj_FWY[mId], raw_api.Obj_FWZ[mId] = sy, 0, cy
            raw_api.Obj_RTX[mId], raw_api.Obj_RTZ[mId] = cy, -sy
            raw_api.Obj_UPX[mId], raw_api.Obj_UPY[mId], raw_api.Obj_UPZ[mId] = 0, 1, 0
            return true
        end)
    end
    function guarded_api.GetFinalBounds(padding) return { minX = minX - padding, minY = minY - padding, minZ = minZ - padding, maxX = maxX + padding, maxY = maxY + padding, maxZ = maxZ + padding }
    end
    return guarded_api
end
return SlideGuard

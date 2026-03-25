local ffi = require("ffi")
local max = math.max

return {
    build = function(api, startSlideCount)
        local NumSlides = startSlideCount

        local function CreateAutoSlide(w, h, thickness, color)
            local sIdx = NumSlides
            local angle = sIdx * (math.pi / 2)
            local radius = 1500
            local x, y, z = math.cos(angle) * radius, math.sin(angle) * radius, sIdx * 3000

            local slide = api.CreateTriObject(x, y, z, 8, 12, max(w, h))
            api.Obj_Yaw[slide.id] = angle
            
            local hw, hh, ht = w/2, h/2, thickness/2
            local verts = { {-hw, -hh, -ht}, {hw, -hh, -ht}, {hw, hh, -ht}, {-hw, hh, -ht}, {-hw, -hh, ht}, {hw, -hh, ht}, {hw, hh, ht}, {-hw, hh, ht} }
            for i, v in ipairs(verts) do slide.vx[i-1], slide.vy[i-1], slide.vz[i-1] = v[1], v[2], v[3] end

            local indices = { 0,2,1, 0,3,2, 4,5,6, 4,6,7, 0,1,5, 0,5,4, 1,2,6, 1,6,5, 2,3,7, 2,7,6, 3,0,4, 3,4,7 }
            for i=0, 11 do slide.tris[i] = {v1=indices[i*3+1], v2=indices[i*3+2], v3=indices[i*3+3], color=color or 0xFFD2B48C} end

            local dist = (h * api.Cam.fov) / api.CANVAS_H + 200
            local offsetX, offsetZ = math.sin(angle) * dist, -math.cos(angle) * dist

            api.Way_X[sIdx], api.Way_Y[sIdx], api.Way_Z[sIdx] = x + offsetX, y, z + offsetZ
            api.Way_Yaw[sIdx], api.Way_Pitch[sIdx] = math.atan2(-offsetX, -offsetZ), 0

            if sIdx == 0 then
                api.Cam.pos.x, api.Cam.pos.y, api.Cam.pos.z = api.Way_X[0], api.Way_Y[0], api.Way_Z[0]
                api.Cam.yaw, api.Cam.pitch = api.Way_Yaw[0], api.Way_Pitch[0]
            end
            NumSlides = NumSlides + 1
        end

        local function CreateAutoSlideHorizontalSplit(w, h, thickness, gap, colorL, colorR)
            local sIdx = NumSlides
            local angle = sIdx * (math.pi / 2)
            local radius = 1500
            local cx, cy, cz = math.cos(angle) * radius, math.sin(angle) * radius, sIdx * 3000
            local rtX, rtZ = math.cos(angle), -math.sin(angle)
            local hw = w / 2
            local offset = (hw / 2) + (gap / 2)

            local function BuildHalf(dir, col)
                local sx, sz = cx + rtX * offset * dir, cz + rtZ * offset * dir
                local slide = api.CreateTriObject(sx, cy, sz, 8, 12, max(hw, h))
                api.Obj_Yaw[slide.id] = angle
                local ihw, ihh, iht = hw/2, h/2, thickness/2
                local verts = { {-ihw, -ihh, -iht}, {ihw, -ihh, -iht}, {ihw, ihh, -iht}, {-ihw, ihh, -iht}, {-ihw, -ihh, iht}, {ihw, -ihh, iht}, {ihw, ihh, iht}, {-ihw, ihh, iht} }
                for i, v in ipairs(verts) do slide.vx[i-1], slide.vy[i-1], slide.vz[i-1] = v[1], v[2], v[3] end
                local indices = { 0,2,1, 0,3,2, 4,5,6, 4,6,7, 0,1,5, 0,5,4, 1,2,6, 1,6,5, 2,3,7, 2,7,6, 3,0,4, 3,4,7 }
                for i=0, 11 do slide.tris[i] = {v1=indices[i*3+1], v2=indices[i*3+2], v3=indices[i*3+3], color=col or 0xFFD2B48C} end
            end

            BuildHalf(-1, colorL)
            BuildHalf(1, colorR)

            local distScale = max(h, (w + gap) * (api.CANVAS_H / api.CANVAS_W))
            local dist = (distScale * api.Cam.fov) / api.CANVAS_H + 200
            local offsetX, offsetZ = math.sin(angle) * dist, -math.cos(angle) * dist

            api.Way_X[sIdx], api.Way_Y[sIdx], api.Way_Z[sIdx] = cx + offsetX, cy, cz + offsetZ
            api.Way_Yaw[sIdx], api.Way_Pitch[sIdx] = math.atan2(-offsetX, -offsetZ), 0
            NumSlides = NumSlides + 1
        end

        -- Generate slides
        CreateAutoSlide(1600, 900, 40, 0xFFFFD700)
        CreateAutoSlideHorizontalSplit(1600, 900, 20, 100, 0xFF44CCFF, 0xFFCC44FF)
        CreateAutoSlide(1800, 1000, 60, 0xFF2E8B57)
        CreateAutoSlide(3200, 1800, 10, 0xFFFFFFFF)

        return NumSlides
    end
}

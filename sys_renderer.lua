local ffi = require("ffi")
local bit = require("bit")
local SysText = require("sys_text")
local floor, ceil, max, min, abs = math.floor, math.ceil, math.max, math.min, math.abs
local sqrt = math.sqrt
local Renderer = {}
local function RasterizeTriangle(x1,y1,z1, x2,y2,z2, x3,y3,z3, shadedColor)
    if y1 > y2 then x1,x2 = x2,x1
        y1,y2 = y2,y1
        z1,z2 = z2,z1 end
    if y1 > y3 then x1,x3 = x3,x1
        y1,y3 = y3,y1
        z1,z3 = z3,z1 end
    if y2 > y3 then x2,x3 = x3,x2
        y2,y3 = y3,y2
        z2,z3 = z3,z2 end
    local total_height = y3 - y1
    if total_height <= 0 then return end
    local inv_total = 1.0 / total_height
    local y_start, y_end = max(0, ceil(y1)), min(CANVAS_H - 1, floor(y3))
    for y = y_start, y_end do
        local is_upper = y < y2
        local x_a, x_b, z_a, z_b
        if is_upper then
            local dy = y2 - y1
            if dy == 0 then dy = 1 end
            local t_a, t_b = (y-y1)*inv_total, (y-y1)/dy
            x_a, z_a = x1+(x3-x1)*t_a, z1+(z3-z1)*t_a
            x_b, z_b = x1+(x2-x1)*t_b, z1+(z2-z1)*t_b
        else
            local dy = y3 - y2
            if dy == 0 then dy = 1 end
            local t_a, t_b = (y-y1)*inv_total, (y-y2)/dy
            x_a, z_a = x1+(x3-x1)*t_a, z1+(z3-z1)*t_a
            x_b, z_b = x2+(x3-x2)*t_b, z2+(z3-z2)*t_b
        end
        if x_a > x_b then x_a,x_b = x_b,x_a
            z_a,z_b = z_b,z_a end
        local rw = x_b - x_a
        if rw > 0 then
            local z_step = (z_b - z_a) / rw
            local start_x, end_x = max(0, ceil(x_a)), min(CANVAS_W - 1, floor(x_b))
            local cz = z_a + z_step * (start_x - x_a)
            local off = y * CANVAS_W
            for x = start_x, end_x do
                if cz < ZBuffer[off + x] then ZBuffer[off + x] = cz
                    ScreenPtr[off + x] = shadedColor end
                cz = cz + z_step
            end
        end
    end
end

function Renderer.BakeStaticLighting()
    for i = 0, NumSlides - 1 do
        local id = Pool_Solid[i]
        local vStart = Obj_VertStart[id]
        local tStart, tCount = Obj_TriStart[id], Obj_TriCount[id]
        local rx, rz = Obj_RTX[id], Obj_RTZ[id]
        local ux, uy, uz = Obj_UPX[id], Obj_UPY[id], Obj_UPZ[id]
        local fx, fy, fz = Obj_FWX[id], Obj_FWY[id], Obj_FWZ[id]

        for t = 0, tCount - 1 do
            local idx = tStart + t
            local i1, i2, i3 = Tri_V1[idx], Tri_V2[idx], Tri_V3[idx]
            local getW = function(vi)
                local lx, ly, lz = Vert_LX[vi], Vert_LY[vi], Vert_LZ[vi]
                return lx*rx+ly*ux+lz*fx, ly*uy+lz*fy, lx*rz+ly*uz+lz*fz
            end

            -- Get global coordinates of the triangle
            local wx1, wy1, wz1 = getW(i1)
            local wx2, wy2, wz2 = getW(i2)
            local wx3, wy3, wz3 = getW(i3)

            -- Calculate normal vector of the slide surface
            local nx = (wy1-wy2)*(wz1-wz3) - (wz1-wz2)*(wy1-wy3)
            local ny = (wz1-wz2)*(wx1-wx3) - (wx1-wx2)*(wz1-wz3)
            local nz = (wx1-wx2)*(wy1-wy3) - (wy1-wy2)*(wx1-wx3)
            local len = math.sqrt(nx*nx + ny*ny + nz*nz)
            if len == 0 then len = 1 end

            -- THE DOME LIGHT (Point Light Singularity)
            -- Positioned at X=0, Z=0, and Y=-2000 (just above the top row)
            local lightX, lightY, lightZ = 0, -2000, 0

            -- Calculate the vector FROM the slide TO the light
            local lx, ly, lz = lightX - wx1, lightY - wy1, lightZ - wz1
            local l_len = math.sqrt(lx*lx + ly*ly + lz*lz)
            if l_len == 0 then l_len = 1 end

            local nx_n, ny_n, nz_n = nx/len, ny/len, nz/len
            local lx_n, ly_n, lz_n = lx/l_len, ly/l_len, lz/l_len

            -- THE FIX: Removed math.abs() so the bottom edges actually fall into shadow!
            local dot_val = math.max(0, nx_n*lx_n + ny_n*ly_n + nz_n*lz_n) * 1.2

            Tri_BaseLight[idx] = math.max(0.2, math.min(1.0, dot_val))
        end
    end
end

local function DrawSlide(id, cpx, cpy, cpz, cfw_x, cfw_y, cfw_z, crt_x, crt_z, cup_x, cup_y, cup_z)
    local dx, dy, dz = Obj_X[id] - cpx, Obj_Y[id] - cpy, Obj_Z[id] - cpz
    local cz_center = dx*cfw_x + dy*cfw_y + dz*cfw_z
    if cz_center + Obj_Radius[id] < 0.1 then return end
    local cx_center = dx*crt_x + dz*crt_z
    local cy_center = dx*cup_x + dy*cup_y + dz*cup_z
    local depth = max(0.1, cz_center)
    if abs(cx_center) > (HALF_W*depth/Cam_FOV)+Obj_Radius[id] or abs(cy_center) > (HALF_H*depth/Cam_FOV)+Obj_Radius[id] then return end
    local rx, rz = Obj_RTX[id], Obj_RTZ[id]
    local ux, uy, uz = Obj_UPX[id], Obj_UPY[id], Obj_UPZ[id]
    local fx, fy, fz = Obj_FWX[id], Obj_FWY[id], Obj_FWZ[id]
    local ox, oy, oz = Obj_X[id], Obj_Y[id], Obj_Z[id]
    local vStart, vCount = Obj_VertStart[id], Obj_VertCount[id]
    for v = 0, vCount - 1 do
        local idx = vStart + v
        local lx, ly, lz = Vert_LX[idx], Vert_LY[idx], Vert_LZ[idx]
        local wx, wy, wz = ox+lx*rx+ly*ux+lz*fx, oy+ly*uy+lz*fy, oz+lx*rz+ly*uz+lz*fz
        Vert_CX[idx], Vert_CY[idx], Vert_CZ[idx] = wx, wy, wz
        local vdx, vdy, vdz = wx-cpx, wy-cpy, wz-cpz
        local cz = vdx*cfw_x + vdy*cfw_y + vdz*cfw_z
        if cz < 0.1 then Vert_Valid[idx] = false else
            local f = Cam_FOV / cz
            Vert_PX[idx] = HALF_W + (vdx*crt_x + vdz*crt_z) * f
            Vert_PY[idx] = HALF_H + (vdx*cup_x + vdy*cup_y + vdz*cup_z) * f
            Vert_PZ[idx] = cz * 1.004
            Vert_Valid[idx] = true
        end
    end
    local tStart, tCount = Obj_TriStart[id], Obj_TriCount[id]
    for t = 0, tCount - 1 do
        local idx = tStart + t
        local i1, i2, i3 = Tri_V1[idx], Tri_V2[idx], Tri_V3[idx]
        if Vert_Valid[i1] and Vert_Valid[i2] and Vert_Valid[i3] then
            local px1, py1, pz1 = Vert_PX[i1], Vert_PY[i1], Vert_PZ[i1]
            local px2, py2, pz2 = Vert_PX[i2], Vert_PY[i2], Vert_PZ[i2]
            local px3, py3, pz3 = Vert_PX[i3], Vert_PY[i3], Vert_PZ[i3]
            local winding = (px2-px1)*(py3-py1) - (py2-py1)*(px3-px1)
            if winding < 0 then
                -- No more cross products! No more square roots!
                local wx1, wy1, wz1 = Vert_CX[i1], Vert_CY[i1], Vert_CZ[i1]

                -- 1. Read the prebaked Dome Light from RAM
                local base_light = Tri_BaseLight[idx]

                -- 2. THE POLISH: Clamp exposure to 85%
                local final_light = base_light * 0.85

                -- GHOST EXORCISED: Bind cinematic wave to EngineState
                if EngineState == STATE_CINEMATIC then
                    local wave = (math.sin(wy1 * 0.01 + love.timer.getTime() * 10) + 1) * 0.5
                    final_light = final_light * (0.5 + wave * 0.5)
                end

                local tc = Tri_Color[idx]
                local r = bit.band(bit.rshift(tc,16),0xFF) * final_light
                local g = bit.band(bit.rshift(tc,8),0xFF) * final_light
                local b = bit.band(tc,0xFF) * final_light
                RasterizeTriangle(px1,py1,pz1, px2,py2,pz2, px3,py3,pz3, 0xFF000000+bit.lshift(r,16)+bit.lshift(g,8)+b)
            end
        end
    end
end
local function DrawProp(id, cpx, cpy, cpz, cfw_x, cfw_y, cfw_z, crt_x, crt_z, cup_x, cup_y, cup_z)
    local dx, dy, dz = Obj_X[id] - cpx, Obj_Y[id] - cpy, Obj_Z[id] - cpz
    local cz_center = dx*cfw_x + dy*cfw_y + dz*cfw_z
    if cz_center + Obj_Radius[id] < 0.1 then return end
    local cx_center = dx*crt_x + dz*crt_z
    local cy_center = dx*cup_x + dy*cup_y + dz*cup_z
    local depth = max(0.1, cz_center)
    if abs(cx_center) > (HALF_W*depth/Cam_FOV)+Obj_Radius[id] or abs(cy_center) > (HALF_H*depth/Cam_FOV)+Obj_Radius[id] then return end
    local rx, rz = Obj_RTX[id], Obj_RTZ[id]
    local ux, uy, uz = Obj_UPX[id], Obj_UPY[id], Obj_UPZ[id]
    local fx, fy, fz = Obj_FWX[id], Obj_FWY[id], Obj_FWZ[id]
    local ox, oy, oz = Obj_X[id], Obj_Y[id], Obj_Z[id]
    local vStart, vCount = Obj_VertStart[id], Obj_VertCount[id]
    for v = 0, vCount - 1 do
        local idx = vStart + v
        local lx, ly, lz = Vert_LX[idx], Vert_LY[idx], Vert_LZ[idx]
        local wx, wy, wz = ox+lx*rx+ly*ux+lz*fx, oy+ly*uy+lz*fy, oz+lx*rz+ly*uz+lz*fz
        Vert_CX[idx], Vert_CY[idx], Vert_CZ[idx] = wx, wy, wz
        local vdx, vdy, vdz = wx-cpx, wy-cpy, wz-cpz
        local cz = vdx*cfw_x + vdy*cfw_y + vdz*cfw_z
        if cz < 0.1 then Vert_Valid[idx] = false else
            local f = Cam_FOV / cz
            Vert_PX[idx] = HALF_W + (vdx*crt_x + vdz*crt_z) * f
            Vert_PY[idx] = HALF_H + (vdx*cup_x + vdy*cup_y + vdz*cup_z) * f
            Vert_PZ[idx] = cz * 1.004
            Vert_Valid[idx] = true
        end
    end
    local tStart, tCount = Obj_TriStart[id], Obj_TriCount[id]
    for t = 0, tCount - 1 do
        local idx = tStart + t
        local i1, i2, i3 = Tri_V1[idx], Tri_V2[idx], Tri_V3[idx]
        if Vert_Valid[i1] and Vert_Valid[i2] and Vert_Valid[i3] then
            local px1, py1, pz1 = Vert_PX[i1], Vert_PY[i1], Vert_PZ[i1]
            local px2, py2, pz2 = Vert_PX[i2], Vert_PY[i2], Vert_PZ[i2]
            local px3, py3, pz3 = Vert_PX[i3], Vert_PY[i3], Vert_PZ[i3]

            local winding = (px2-px1)*(py3-py1) - (py2-py1)*(px3-px1)
            if winding < 0 then
                local wx1, wy1, wz1 = Vert_CX[i1], Vert_CY[i1], Vert_CZ[i1]
                local nx = (wy1-Vert_CY[i2])*(wz1-Vert_CZ[i3]) - (wz1-Vert_CZ[i2])*(wy1-Vert_CY[i3])
                local ny = (wz1-Vert_CZ[i2])*(wx1-Vert_CX[i3]) - (wx1-Vert_CX[i2])*(wz1-Vert_CZ[i3])
                local nz = (wx1-Vert_CX[i2])*(wy1-Vert_CY[i3]) - (wy1-Vert_CY[i2])*(wx1-Vert_CX[i3])
                local len = sqrt(nx*nx+ny*ny+nz*nz); if len == 0 then len = 1 end

                -- 1. Get the vector FROM the prop TO the Dome Light (0, -2000, 0)
                local lx, ly, lz = 0 - wx1, -2000 - wy1, 0 - wz1
                local l_len = sqrt(lx*lx + ly*ly + lz*lz); if l_len == 0 then l_len = 1 end

                -- 2. Calculate the normalized dot product
                local raw_dot = max(0, (nx/len)*(lx/l_len) + (ny/len)*(ly/l_len) + (nz/len)*(lz/l_len))

                -- 3. EXPONENT & MULTIPLIER: Square it for the spotlight effect, boost wattage to 1.5
                -- 4. FLOOR: Hard 5% (0.05) ambient shadow floor!
                local final_light = max(0.05, min(1.0, (raw_dot ^ 2) * 1.5))

                local tc = Tri_Color[idx]
                local r = bit.band(bit.rshift(tc,16),0xFF) * final_light
                local g = bit.band(bit.rshift(tc,8),0xFF) * final_light
                local b = bit.band(tc,0xFF) * final_light
                RasterizeTriangle(px1,py1,pz1, px2,py2,pz2, px3,py3,pz3, 0xFF000000+bit.lshift(r,16)+bit.lshift(g,8)+b)
            end
        end
    end
end
local function Render3DScene()
    ffi.fill(ScreenPtr, CANVAS_W * CANVAS_H * 4, 0)
    ffi.fill(ZBuffer, CANVAS_W * CANVAS_H * 4, 0x7F)
    local cpx, cpy, cpz = Cam_X, Cam_Y, Cam_Z
    local cfw_x, cfw_y, cfw_z = Cam_FWX, Cam_FWY, Cam_FWZ
    local crt_x, crt_z = Cam_RTX, Cam_RTZ
    local cup_x, cup_y, cup_z = Cam_UPX, Cam_UPY, Cam_UPZ
    -- GHOST EXORCISED: Scene culling correctly targets both Zen and Hibernated states
    local isZen = (EngineState == STATE_ZEN or EngineState == STATE_HIBERNATED)
    for i = 0, NumSlides - 1 do
        if isZen and i ~= TargetSlide then goto continue_slides end
        DrawSlide(Pool_Solid[i], cpx, cpy, cpz, cfw_x, cfw_y, cfw_z, crt_x, crt_z, cup_x, cup_y, cup_z)
        ::continue_slides::
    end
    if not isZen then
        for i = NumSlides, Pool_Solid_Count - 1 do
            DrawProp(Pool_Solid[i], cpx, cpy, cpz, cfw_x, cfw_y, cfw_z, crt_x, crt_z, cup_x, cup_y, cup_z)
        end
    end
end
local function BlitUI_3D(obj, cx, cy, depth, scale, alpha, z_bias)
    if not obj or alpha <= 0.01 or scale < 0.01 then return end
    local ptr, tw, th = obj.ptr, obj.w, obj.h
    local sw, sh = floor(tw * scale), floor(th * scale)
    if sw <= 0 or sh <= 0 then return end
    local startX, startY = floor(cx - sw * 0.5), floor(cy - sh * 0.5)
    local clipX, clipY = max(0, startX), max(0, startY)
    local endX, endY = min(CANVAS_W - 1, startX + sw - 1), min(CANVAS_H - 1, startY + sh - 1)
    local inv_scale = 1.0 / scale
    local z_threshold = depth - z_bias
    local global_a256 = floor(alpha * 255)
    for y = clipY, endY do
        local ty = floor((y - startY) * inv_scale)
        if ty >= 0 and ty < th then
            local screenOff = y * CANVAS_W
            local buffOff = ty * tw
            for x = clipX, endX do
                local tx = floor((x - startX) * inv_scale)
                if tx >= 0 and tx < tw then
                    local px = ptr[buffOff + tx]
                    if px >= 0x01000000 then
                        if ZBuffer[screenOff + x] >= z_threshold then
                            local pa = bit.rshift(px, 24)
                            local final_a = bit.rshift(pa * global_a256, 8)
                            if final_a > 0 then
                                local bg = ScreenPtr[screenOff + x]
                                local bg_r, bg_g, bg_b = bit.band(bit.rshift(bg, 16), 0xFF), bit.band(bit.rshift(bg, 8), 0xFF), bit.band(bg, 0xFF)
                                local inv_a = 255 - final_a
                                local r, g, b = bit.rshift(bg_r*inv_a, 8), bit.rshift(bg_g*inv_a, 8), bit.rshift(bg_b*inv_a, 8)
                                ScreenPtr[screenOff + x] = bit.bor(0xFF000000, bit.lshift(r, 16), bit.lshift(g, 8), b)
                            end
                        end
                    end
                end
            end
        end
    end
end
local function RenderText()
    -- GHOST EXORCISED: presentationMode is dead. FreeFly hides text.
    if NumSlides == 0 or EngineState == STATE_FREEFLY then return end
    local i = TargetSlide
    local sx, sy, sz = Box_X[i], Box_Y[i], Box_Z[i]
    local bnx, bny, bnz = Box_NX[i], Box_NY[i], Box_NZ[i]
    local cache = SysText.GetCache(i, EngineState)
    local camDX, camDY, camDZ = Cam_X - sx, Cam_Y - sy, Cam_Z - sz
    local dist = sqrt(camDX*camDX + camDY*camDY + camDZ*camDZ)
    local dot = (dist > 0) and ((camDX/dist)*bnx + (camDY/dist)*bny + (camDZ/dist)*bnz) or 0
    local abs_dot = abs(dot)
    if abs_dot < 0.707 then return end
    local t_off = (dot > 0 and 1 or -1) * cache.text_z_offset
    local tdx = (sx + bnx * t_off) - Cam_X
    local tdy = (sy + bny * t_off) - Cam_Y
    local tdz = (sz + bnz * t_off) - Cam_Z
    local depth = tdx*Cam_FWX + tdy*Cam_FWY + tdz*Cam_FWZ
    if depth < 10 or depth > 8000 then return end
    local alpha_close = max(0, min(1, (depth-100)/300))
    local alpha_angle = min(1, (abs_dot-0.707)*5)
    local alpha_far = max(0, min(1, (8000-depth)/2000))
    -- Bolwark controlled Alpha override
    local final_alpha = alpha_close * alpha_angle * alpha_far * SysText.Alpha
    if final_alpha <= 0.01 then return end
    local renderX, renderY = HALF_W, HALF_H
    local current_perspective = (Cam_FOV / depth)
    local draw_scale = current_perspective / cache.opt_scale
    BlitUI_3D(cache, renderX, renderY, depth, draw_scale, final_alpha, 5)
end
function Renderer.DrawFrame()
    if not snapshotBaked then
        Render3DScene()
        RenderText()
        ScreenImage:replacePixels(ScreenBuffer)
    end
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.setBlendMode("replace")
    love.graphics.draw(ScreenImage, 0, 0)
end
return Renderer

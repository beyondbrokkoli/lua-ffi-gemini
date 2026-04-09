local ffi = require("ffi")
local max, min, floor = math.max, math.min, math.floor
local SysText = { Alpha = 0.0 }
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
local function BakeSlideText(i, titleText, content, w, h, isZen)
    local distScale = max(h, w * (CANVAS_H / CANVAS_W))
    local pad = isZen and 0 or 200
    local optDist = (distScale * Cam_FOV) / CANVAS_H * 1.0 + pad
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
    love.graphics.setFont(fonts.title)
    love.graphics.printf(titleText, paddingX, currentY, maxTextWidth, "center")
    currentY = currentY + fonts.title:getHeight() + floor(virtH * 0.02)
    if content then
        for _, s in ipairs(content) do
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
                        love.graphics.printf(lineStr, xOffset, lineY, colPrintWidth, colData.align)
                        lineY = lineY + colData.font:getHeight()
                        colHeight = colHeight + colData.font:getHeight()
                    end
                    if colHeight > maxRowHeight then maxRowHeight = colHeight end
                end
                currentY = currentY + maxRowHeight + floor(virtH * 0.005)
            else
                currentY = currentY + fonts.body:getHeight()
            end
        end
    end
    local finalH = min(virtH, currentY + floor(virtH * 0.05))
    local croppedCanvas = love.graphics.newCanvas(virtW, finalH)
    love.graphics.setCanvas(croppedCanvas)
    love.graphics.clear(0, 0, 0, 0)
    love.graphics.setBlendMode("replace")
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(giantCanvas, 0, 0)
    love.graphics.setBlendMode("alpha")
    love.graphics.setCanvas()
    local imgData = croppedCanvas:newImageData()
    local cache = {
        ptr = ffi.cast("uint32_t*", imgData:getPointer()),
        w = virtW, h = finalH,
        _keepAlive = imgData,
        text_z_offset = (Box_HT[i] + 5),
        opt_scale = optimal_scale,
        orig_h = virtH
    }
    giantCanvas:release()
    croppedCanvas:release()
    return cache
end
local ansi_colors = {
    ["31"] = {1, 0, 0},   -- Red
    ["32"] = {0, 1, 0},   -- Green
    ["33"] = {1, 1, 0},   -- Yellow
    ["36"] = {0, 1, 1},   -- Cyan
    ["0"]  = {0, 0.8, 0}, -- Reset (default terminal green)
}

function SysText.BakeTerminal()
    local font = love.graphics.newFont(16)
    local w, h = floor(CANVAS_W * 0.4), CANVAS_H
    local canvas = love.graphics.newCanvas(w, h)

    love.graphics.setCanvas(canvas)
    love.graphics.clear(0, 0, 0, 0)
    love.graphics.setFont(font)

    for i, line in ipairs(Engine.terminal.lines) do
        local curX = 10
        local curY = 20 + (i * 20)
        
        -- Default color
        love.graphics.setColor(0, 0.8, 0, 1)

        -- This pattern finds ANSI sequences and the text following them
        -- Chunk 1: The ANSI code (if any), Chunk 2: The text segment
        for code, text in line:gmatch("\27%[([%d;]*)m([^\27]*)") do
            -- Update color state if a code exists
            if code and ansi_colors[code] then
                local c = ansi_colors[code]
                love.graphics.setColor(c[1], c[2], c[3], 1)
            end
            
            -- Print segment and advance X
            if text and #text > 0 then
                love.graphics.print(text, curX, curY)
                curX = curX + font:getWidth(text)
            end
        end
        
        -- Handle lines that have no ANSI codes at all
        if not line:find("\27") then
            love.graphics.setColor(0, 0.8, 0, 1)
            love.graphics.print(line, 10, curY)
        end
    end

    love.graphics.setCanvas()
    local imgData = canvas:newImageData()

    TerminalCache = {
        ptr = ffi.cast("uint32_t*", imgData:getPointer()),
        w = w, h = h,
        _keepAlive = imgData
    }
    canvas:release()
end
function SysText.InitSlideTextCache(textPayload)
    if SlideTitles then
        for i, caches in pairs(SlideTitles) do
            if caches[false] and caches[false]._keepAlive then caches[false]._keepAlive:release() end
            if caches[true] and caches[true]._keepAlive then caches[true]._keepAlive:release() end
        end
    end
    SlideTitles = {}
    for i = 0, NumSlides - 1 do
        local slideData = textPayload[i]
        local titleText = (slideData and slideData.title) or ("SLIDE " .. tostring(i + 1))
        local content = slideData and slideData.content
        local w, h = Box_HW[i] * 2, Box_HH[i] * 2
        SlideTitles[i] = {}
        SlideTitles[i][false] = BakeSlideText(i, titleText, content, w, h, false)
        SlideTitles[i][true] = BakeSlideText(i, titleText, content, w, h, true)
    end
    collectgarbage("collect")
end
function SysText.GetCache(slideIdx, currentState)
    local useZenCache = (currentState == STATE_ZEN or currentState == STATE_HIBERNATED)
    return SlideTitles[slideIdx][useZenCache]
end
function SysText.Update(currentState, dt)
    -- Target is 1.0 (visible) when landed, 0.0 (invisible) when moving
    local target = (currentState >= STATE_PRESENT) and 1.0 or 0.0

    -- THE KNOB: 50.0 means the text fades to 0% in ~0.02 seconds (1 frame).
    -- 3.3 means it fades IN smoothly over ~0.3 seconds when arriving.
    local speed = (currentState == STATE_CINEMATIC) and 50.0 or 3.3

    if SysText.Alpha < target then
        SysText.Alpha = min(target, SysText.Alpha + dt * speed)
    elseif SysText.Alpha > target then
        SysText.Alpha = max(target, SysText.Alpha - dt * speed)
    end

    return (SysText.Alpha == target)
end

return SysText

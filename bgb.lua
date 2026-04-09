-- @@@ FILE: bgb.lua @@@
local json = require("dkjson")

-- Local scope for colors (prevents nil errors if globals aren't set)
local c_red, c_green, c_yellow = "\27[31m", "\27[32m", "\27[33m"
local c_reset = "\27[0m"

local function CrawlBGBForParagraphs(data)
    local FlatBGB = {}
    if not data or not data.output or not data.output.norms then return FlatBGB end

    for _, norm in ipairs(data.output.norms) do
        local meta = norm.meta
        if meta and meta.norm_id then
            local clean_num = string.match(meta.norm_id, "§%s*([%w%a]+)")
            if clean_num then
                local full_text = ""
                if norm.paragraphs then
                    for _, para in ipairs(norm.paragraphs) do
                        if para.content then full_text = full_text .. para.content .. "\n" end
                    end
                end
                FlatBGB[clean_num] = {
                    title = meta.title or meta.norm_id,
                    text = full_text
                }
            end
        end
    end
    return FlatBGB
end

local function MountBGBDatabase(filepath)
    print(">> Mounting BGB Database from: " .. filepath)
    local f = io.open(filepath, "r")
    if not f then
        print(c_yellow .. "[WARNING] " .. filepath .. " not found." .. c_reset)
        return {}
    end

    local content = f:read("*all")
    f:close()

    local data, _, err = json.decode(content)
    if err then
        print(c_red .. "[ERROR] JSON parse failed: " .. err .. c_reset)
        return {}
    end

    local index = CrawlBGBForParagraphs(data)
    local count = 0
    for _ in pairs(index) do count = count + 1 end
    print(c_green .. "[SUCCESS] Indexed " .. count .. " paragraphs.\n" .. c_reset)
    
    return index
end

-- Return the table directly upon require
return MountBGBDatabase("bgb.json")

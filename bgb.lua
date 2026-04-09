local json = require("dkjson")

-- Our Flat Lookup Table: e.g., FlatBGB["622"] = { title = "...", text = "..." }
-- we will return it
local FlatBGB = {}
-- ==========================================
-- BGB JSON INDEXER (Tailored to BJNR001950896)
-- ==========================================
local function CrawlBGBForParagraphs(data)
    -- Verify the schema matches what we expect from the GitHub repo
    if not data or not data.output or not data.output.norms then
        print(c_red .. "[ERROR] JSON does not match the expected de_laws_to_json schema." .. c_reset)
        return
    end

    for _, norm in ipairs(data.output.norms) do
        local meta = norm.meta
        if meta and meta.norm_id then
            -- Extract "622" from "§ 622" or "611a" from "§ 611a"
            local clean_num = string.match(meta.norm_id, "§%s*([%w%a]+)")

            if clean_num then
                local full_text = ""
                -- Loop through the sub-paragraphs (Absätze) and stitch them together
                if norm.paragraphs then
                    for _, para in ipairs(norm.paragraphs) do
                        if para.content then
                            full_text = full_text .. para.content .. "\n"
                        end
                    end
                end

                -- Burn it into flat O(1) memory
                FlatBGB[clean_num] = {
                    title = meta.title or meta.norm_id,
                    text = full_text
                }
            end
        end
    end
end

local function MountBGBDatabase(filepath)
    print(">> Mounting BGB Database from: " .. filepath)
    local f = io.open(filepath, "r")
    if not f then
        print(c_yellow .. "[WARNING] Could not find " .. filepath .. ". Live query feature disabled." .. c_reset)
        return false
    end

    local content = f:read("*all")
    f:close()

    local data, pos, err = json.decode(content)
    if err then
        print(c_red .. "[ERROR] JSON parse failed: " .. err .. c_reset)
        return false
    end

    print(">> Indexing JSON tree into flat memory space...")
    CrawlBGBForParagraphs(data)

    local count = 0
    for _ in pairs(FlatBGB) do count = count + 1 end

    print(c_green .. "[SUCCESS] BGB Database mounted. Indexed " .. count .. " paragraphs.\n" .. c_reset)
    return FlatBGB
end

-- ==========================================
-- THE LOOKUP FUNCTION (Hook this into your Menu)
-- ==========================================
local function LookupParagraph()
    print(c_cyan .. "\n--- BGB DATABASE QUERY ---" .. c_reset)
    io.write("Enter Paragraph Number (e.g., 622, 611a): ")
    local query = io.read()

    local p_data = FlatBGB[query]

    if not p_data then
        print(c_red .. "[404] Paragraph § " .. query .. " not found in index." .. c_reset)
        print("Press ENTER to return...")
        io.read()
        return
    end

    ClearScreen()
    print(c_cyan .. "==================================================")
    print(" § " .. query .. " - " .. p_data.title)
    print("==================================================" .. c_reset)
    print(p_data.text)
    print(c_cyan .. "==================================================" .. c_reset)
    print("Press ENTER to return...")
    io.read()
end

-- At the bottom of your script, right before the MAIN LOOP starts, add:
return MountBGBDatabase("bgb.json")

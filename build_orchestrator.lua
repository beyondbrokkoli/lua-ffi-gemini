local function minify_lua(content)
    local lines = {}
    local d = "\45" .. "\45"
    for line in content:gmatch("[^\r\n]+") do
        local s = line:find(d, 1, true)
        local clean_line = line
        if s then
            local prefix = line:sub(1, s - 1)
            local _, quote_count = prefix:gsub('"', '"')
            if quote_count % 2 == 0 then
                clean_line = prefix
            end
        end
        clean_line = clean_line:gsub("[ \t]+", " ")
        clean_line = clean_line:match("^%s*(.-)%s*$")
        if clean_line ~= "" then
            table.insert(lines, clean_line)
        end
    end
    if #lines == 0 then return "-- [EMPTY OR ALL COMMENTS] --" end
    return table.concat(lines, "; ")
end
local function strip_to_target(input_path, output_path)
    local infile = io.open(input_path, "r")
    if not infile then return false end
    local lines = {}
    local d = "\45" .. "\45"
    for line in infile:lines() do
        local s = line:find(d, 1, true)
        local clean_line = line
        if s then
            local prefix = line:sub(1, s - 1)
            local _, quote_count = prefix:gsub('"', '"')
            if quote_count % 2 == 0 then
               clean_line = prefix
            end
        end
        clean_line = clean_line:match("^%s*(.-)%s*$")
        if clean_line ~= "" then
            table.insert(lines, clean_line)
        end
    end
    infile:close()
    local outfile = io.open(output_path, "w")
    if outfile then
        outfile:write(table.concat(lines, "\n") .. "\n")
        outfile:close()
        return true
    end
    return false
end
local function copy_file(src, dest)
    local f_in = io.open(src, "rb")
    if not f_in then return false end
    local content = f_in:read("*all")
    f_in:close()
    local f_out = io.open(dest, "wb")
    if not f_out then return false end
    f_out:write(content)
    f_out:close()
    return true
end

local process_manifest = {
    ["sys_memory.lua"] = "BUILD/sys_memory.lua",
    ["sys_physics.lua"] = "BUILD/sys_physics.lua",
    ["sys_renderer.lua"] = "BUILD/sys_renderer.lua",
    ["main.lua"] = "BUILD/main.lua",
    ["engine.lua"] = "BUILD/engine.lua",
    ["build_orchestrator.lua"] = "BUILD/build_orchestrator.lua",
--    ["rebuild_orchestrator.lua"] = "BUILD/rebuild_orchestrator.lua",
    ["sys_text.lua"] = "BUILD/sys_text.lua",
    ["sys_factory.lua"] = "BUILD/sys_factory.lua",
    ["conf.lua"] = "BUILD/conf.lua",
    ["bgb.lua"] = "BUILD/bgb.lua"

}
local raw_manifest = {} -- now empty because we broke free from json chains
local function setup_build_dir(dir)
    local ok = os.execute("test -d " .. dir)
    if ok == 0 or ok == true then
        print("!!! Found existing " .. dir .. " directory. Press ENTER to purge and rebuild.")
        io.read()
        os.execute("rm -rf " .. dir)
    end
    return os.execute("mkdir -p " .. dir)
end
local function get_sorted_files()
    local sorted = {}
    local visited = {}
    local function visit(file)
        if visited[file] then return end
        visited[file] = true
        local f = io.open(file, "r")
        if f then
            local content = f:read("*all")
            f:close()
            for dep_match in content:gmatch('require%s*%(?%s*["\'](.-)["\']%s*%)?') do
                local dep_name = dep_match
                if not dep_name:find("%.lua$") then
                    dep_name = dep_name .. ".lua"
                end
                if process_manifest[dep_name] then
                    visit(dep_name)
                end
            end
        end
        table.insert(sorted, file)
    end
    for file in pairs(process_manifest) do visit(file) end
    return sorted
end
if not setup_build_dir("BUILD") then os.exit(1) end
print("--- MOUNTING TO BUILD/ ---")
for src, dest in pairs(process_manifest) do
    if strip_to_target(src, dest) then print("  |- (Stripped) " .. src) end
end
for src, dest in pairs(raw_manifest) do
    if copy_file(src, dest) then print("  |- (Raw)      " .. src) end
end
print("\n--- AI SNAPSHOT ---")
local order = get_sorted_files()
for _, src in ipairs(order) do
    local f = io.open(src, "r")
    if f then
        print("@@@ FILE: " .. src .. " @@@\n" .. minify_lua(f:read("*all")))
        f:close()
    end
end

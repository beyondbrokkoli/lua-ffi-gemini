-- comments.lua
local function strip_comments(input_file, output_file)
    local infile = io.open(input_file, "r")
    if not infile then 
        print("Error: Could not open " .. input_file)
        return 
    end

    local outfile = io.open(output_file, "w")

    for line in infile:lines() do
        -- Find the first occurrence of a Lua comment
        local s = line:find("%-%-")
        local clean_line = line

        if s then
            -- Slice the string up to the comment's start index
            clean_line = line:sub(1, s - 1)
        end

        -- Trim trailing and leading whitespace
        clean_line = clean_line:match("^%s*(.-)%s*$")

        -- Only write the line if it actually contains code
        if clean_line ~= "" then
            outfile:write(clean_line .. "\n")
        end
    end

    infile:close()
    outfile:close()
    print("Successfully stripped comments from " .. input_file .. " -> " .. output_file)
end

-- Run the function on your main file
strip_comments("with_comments_main.lua", "main.lua")

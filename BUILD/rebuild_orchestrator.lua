local input_file = arg[1] or "snapshot.txt"
local function split_statements(minified)
local stmts = {}
local current = ""
local in_string = false
local in_comment = false
local quote_char = ""
local i = 1
while i <= #minified do
local c = minified:sub(i, i)
local next_c = minified:sub(i+1, i+1)
if in_comment then
if c == "\n" then
in_comment = false
table.insert(stmts, current)
current = ""
else
current = current .. c
end
elseif in_string then
if c == "\\" then
current = current .. c
i = i + 1
if i <= #minified then current = current .. minified:sub(i, i) end
elseif c == quote_char then
in_string = false
current = current .. c
else
current = current .. c
end
else
if c == "-" and next_c == "-" then
if current:match("%S") then table.insert(stmts, current) end
in_comment = true
current = "--"
i = i + 1
elseif c == '"' or c == "'" then
in_string = true
quote_char = c
current = current .. c
elseif c == ";" then
table.insert(stmts, current)
current = ""
if minified:sub(i+1, i+1) == " " then i = i + 1 end
else
current = current .. c
end
end
i = i + 1
end
if current:match("%S") then table.insert(stmts, current) end
return stmts
end
local function count_word(str, word)
local count = 0
for w in str:gmatch("[%w_]+") do
if w == word then count = count + 1 end
end
return count
end
local function format_lua(stmts)
local out = {}
local indent = 0
for _, stmt in ipairs(stmts) do
stmt = stmt:match("^%s*(.-)%s*$")
if stmt == "" then goto continue end
local first_word = stmt:match("^([%w_]+)")
local first_char = stmt:sub(1,1)
local line_dec = 0
if first_word == "end" or first_word == "until" or first_word == "else" or first_word == "elseif" or first_char == "}" then
line_dec = 1
end
local current_indent = math.max(0, indent - line_dec)
table.insert(out, string.rep("    ", current_indent) .. stmt)
local clean_stmt = stmt:gsub('".-"', ''):gsub("'.-'", '')
clean_stmt = clean_stmt:gsub("%-%-.*", "")
clean_stmt = " " .. clean_stmt .. " "
local inc = count_word(clean_stmt, "function") + count_word(clean_stmt, "do") +
count_word(clean_stmt, "then") + count_word(clean_stmt, "repeat") +
count_word(clean_stmt, "else")
for _ in clean_stmt:gmatch("{") do inc = inc + 1 end
local dec = count_word(clean_stmt, "end") + count_word(clean_stmt, "until") +
count_word(clean_stmt, "else") + count_word(clean_stmt, "elseif")
for _ in clean_stmt:gmatch("}") do dec = dec + 1 end
indent = math.max(0, indent + inc - dec)
::continue::
end
return table.concat(out, "\n")
end
local function parse_and_write(filename, content)
local stmts = split_statements(content)
local formatted = format_lua(stmts)
local f = io.open("RESTORED/" .. filename, "w")
if f then
f:write(formatted .. "\n")
f:close()
print("  |- [RESTORED] " .. filename)
else
print("  |- [ERROR] Could not write " .. filename)
end
end
local f = io.open(input_file, "r")
if not f then
print("!!! ERROR: Could not find " .. input_file)
print("USAGE: lua rebuild_orchestrator.lua [snapshot_file.txt]")
os.exit(1)
end
print("--- DECOMPRESSING AI SNAPSHOT ---")
os.execute("mkdir -p RESTORED")
local current_file = nil
local current_content = {}
for line in f:lines() do
local fname = line:match("^@@@ FILE: (.-) @@@")
if fname then
if current_file then
parse_and_write(current_file, table.concat(current_content, "\n"))
end
current_file = fname
current_content = {}
else
if current_file then
table.insert(current_content, line)
end
end
end
if current_file then
parse_and_write(current_file, table.concat(current_content, "\n"))
end
f:close()
print("--- RESTORATION COMPLETE ---")

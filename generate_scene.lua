local json = require("dkjson") -- Ensure dkjson is in your path

-- CONFIGURATION
local SLIDES_PER_ROW = 16
local TOTAL_ROWS = 4
local RADIUS = 7500
local ROW_HEIGHT = 2200 -- Slightly more vertical breathing room
local FILENAME = "scene.json"

-- CONTENT TEMPLATES (Derived from your provided snippets)
local templates = {
    {
        text = "THE NEW STANDARD",
        color = 4294967295,
        content = {"~ # ULTIMA PLATIN v3.0", "", "~ Welcome to the 3D-Matrix.", "~ We have successfully escaped the pancake.", "", "~ Press Space to accelerate."}
    },
    {
        text = "PITCH PERFECT",
        color = 4294956800,
        content = {"~ # 3D ROTATION TEST", "", "Horizontal Yawing | Vertical Pitching", "Traditional slides are flat. | Ours are fully oriented.", "OBB math is now active. | Collisions follow the tilt.", "", "~ Observe the Torus satellites circling the rim."}
    },
    {
        text = "DEEP MEMORY",
        color = 4278255615,
        content = {"~ # FFI MEMORY INJECTION", "", "~ We injected the missing Y-Axis components.", "", "Basis Vectors (FW/RT/UP) | Memory Pointers", "Replaced 2D Guard logic. | Initialized FFI Buffers.", "Singularities eradicated. | Object HomeIndices synced.", "", "~ The geometry is solid and persistent."}
    },
    {
        text = "SOFTWARE RASTERIZATION",
        color = 4287273954,
        content = {"~ # PIXEL-LEVEL CONTROL", "", "~ We are not using the GPU for math.", "", "Triangle Bounding | Z-Buffer Depth Checking", "Flat Shading Logic | Barycentric Calculation", "CPU Rasterization | FFI Pointer Speed", "", "~ Hand-coded rendering pipeline."}
    },
    {
        text = "ZEN MODE REDUX",
        color = 4294928820,
        content = {"~ # ZEN MODE OPTIMIZATION", "", "Snapshot Baking | Logic Culling", "The software render sleeps. | The physics loop pauses.", "Static frame caching. | CPU usage falls to 0%.", "", "~ Hit 'Z' to witness the 4-FPS hibernation."}
    },
    {
        text = "THE CHOKEHOLD",
        color = 4278255360,
        content = {"~ # TAMING THE VIRTUALBOX GPU", "", "~ llvmpipe was consuming 3 cores.", "", "VSync: On | Timer Sleep: 0.25s", "Snapshot Baked Flag | Input Latency: Minimal", "CPU: Cold | VM Stability: Peak", "", "~ We used a 10-frame buffer to avoid freezing."}
    }
}

local scene = {}

for i = 0, (SLIDES_PER_ROW * TOTAL_ROWS) - 1 do
    local row = math.floor(i / SLIDES_PER_ROW)
    local col = i % SLIDES_PER_ROW
    
    -- Topology Math (Cylinder)
    local yaw = col * (math.pi / 8) -- 22.5 degrees
    local x = math.sin(yaw) * RADIUS
    local y = row * ROW_HEIGHT
    local z = math.cos(yaw) * RADIUS
    
    -- Select Template (cycling through)
    local tIdx = (i % #templates) + 1
    local template = templates[tIdx]
    
    local slide = {
        x = x, y = y, z = z,
        w = 1600, h = 900,
        yaw = yaw,
        pitch = 0.0,
        thickness = 40 + (i % 3) * 20, -- Varied thickness for visual grit
        color = template.color,
        text = string.format("%02d: %s", i + 1, template.text),
        content = template.content
    }
    
    table.insert(scene, slide)
end

-- Write to file
local file = io.open(FILENAME, "w")
file:write(json.encode(scene, { indent = true }))
file:close()

print(string.format("Successfully baked %d slides into %s", #scene, FILENAME))

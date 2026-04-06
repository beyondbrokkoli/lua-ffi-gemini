local ffi = require("ffi")
MAX_SLIDES = 128
MAX_OBJS = 1024
NumObjects = 0
NumTotalVerts, NumTotalTris = 0, 0
Pool_Solid = ffi.new("int[?]", MAX_OBJS)
Pool_Solid_Count = 0
Pool_Kinematic = ffi.new("int[?]", MAX_OBJS)
Pool_Kinematic_Count = 0
Pool_Collider = ffi.new("int[?]", MAX_OBJS)
Pool_Collider_Count = 0
Pool_SlideCollider = ffi.new("int[?]", MAX_OBJS)
Pool_SlideCollider_Count = 0
Pool_DeepSpace = ffi.new("int[?]", MAX_OBJS)
Pool_DeepSpace_Count = 0
Obj_HomeIdx = ffi.new("int[?]", MAX_OBJS)
Obj_X = ffi.new("float[?]", MAX_OBJS)
Obj_Y = ffi.new("float[?]", MAX_OBJS)
Obj_Z = ffi.new("float[?]", MAX_OBJS)
Obj_Yaw = ffi.new("float[?]", MAX_OBJS)
Obj_Pitch = ffi.new("float[?]", MAX_OBJS)
Obj_Radius = ffi.new("float[?]", MAX_OBJS)
Obj_FWX = ffi.new("float[?]", MAX_OBJS)
Obj_FWY = ffi.new("float[?]", MAX_OBJS)
Obj_FWZ = ffi.new("float[?]", MAX_OBJS)
Obj_RTX = ffi.new("float[?]", MAX_OBJS)

Obj_RTY = ffi.new("float[?]", MAX_OBJS) -- Welcome back to reality

Obj_RTZ = ffi.new("float[?]", MAX_OBJS)
Obj_UPX = ffi.new("float[?]", MAX_OBJS)
Obj_UPY = ffi.new("float[?]", MAX_OBJS)
Obj_UPZ = ffi.new("float[?]", MAX_OBJS)
Obj_VelX = ffi.new("float[?]", MAX_OBJS)
Obj_VelY = ffi.new("float[?]", MAX_OBJS)
Obj_VelZ = ffi.new("float[?]", MAX_OBJS)
Obj_RotSpeedYaw = ffi.new("float[?]", MAX_OBJS)
Obj_RotSpeedPitch = ffi.new("float[?]", MAX_OBJS)
MAX_TOTAL_VERTS = MAX_OBJS * 24
MAX_TOTAL_TRIS = MAX_OBJS * 36
Obj_VertStart = ffi.new("int[?]", MAX_OBJS)
Obj_VertCount = ffi.new("int[?]", MAX_OBJS)
Obj_TriStart = ffi.new("int[?]", MAX_OBJS)
Obj_TriCount = ffi.new("int[?]", MAX_OBJS)
Vert_LX = ffi.new("float[?]", MAX_TOTAL_VERTS)
Vert_LY = ffi.new("float[?]", MAX_TOTAL_VERTS)
Vert_LZ = ffi.new("float[?]", MAX_TOTAL_VERTS)
Vert_CX = ffi.new("float[?]", MAX_TOTAL_VERTS)
Vert_CY = ffi.new("float[?]", MAX_TOTAL_VERTS)
Vert_CZ = ffi.new("float[?]", MAX_TOTAL_VERTS)
Vert_PX = ffi.new("float[?]", MAX_TOTAL_VERTS)
Vert_PY = ffi.new("float[?]", MAX_TOTAL_VERTS)
Vert_PZ = ffi.new("float[?]", MAX_TOTAL_VERTS)
Vert_Valid = ffi.new("bool[?]", MAX_TOTAL_VERTS)
Tri_V1 = ffi.new("int[?]", MAX_TOTAL_TRIS)
Tri_V2 = ffi.new("int[?]", MAX_TOTAL_TRIS)
Tri_V3 = ffi.new("int[?]", MAX_TOTAL_TRIS)
Tri_Color = ffi.new("uint32_t[?]", MAX_TOTAL_TRIS)
Tri_BaseLight = ffi.new("float[?]", MAX_TOTAL_TRIS)
B_MinX, B_MinY, B_MinZ = -8000, -4000, -2000
B_MaxX, B_MaxY, B_MaxZ = 8000, 4000, 15000
Sphere_X = ffi.new("float[?]", MAX_SLIDES)
Sphere_Y = ffi.new("float[?]", MAX_SLIDES)
Sphere_Z = ffi.new("float[?]", MAX_SLIDES)
Sphere_RSq = ffi.new("float[?]", MAX_SLIDES)
Box_X = ffi.new("float[?]", MAX_SLIDES)
Box_Y = ffi.new("float[?]", MAX_SLIDES)
Box_Z = ffi.new("float[?]", MAX_SLIDES)
Box_HW = ffi.new("float[?]", MAX_SLIDES)
Box_HH = ffi.new("float[?]", MAX_SLIDES)
Box_HT = ffi.new("float[?]", MAX_SLIDES)
Box_CosA = ffi.new("float[?]", MAX_SLIDES)
Box_SinA = ffi.new("float[?]", MAX_SLIDES)
Box_NX = ffi.new("float[?]", MAX_SLIDES)
Box_NY = ffi.new("float[?]", MAX_SLIDES); -- [NEW] The missing Y normal!
Box_NZ = ffi.new("float[?]", MAX_SLIDES)

-- [NEW] The True 3D Basis Vectors for OBB Physics Collisions
Box_FWX = ffi.new("float[?]", MAX_SLIDES);
Box_FWY = ffi.new("float[?]", MAX_SLIDES);
Box_FWZ = ffi.new("float[?]", MAX_SLIDES);
Box_RTX = ffi.new("float[?]", MAX_SLIDES);
Box_RTY = ffi.new("float[?]", MAX_SLIDES);
Box_RTZ = ffi.new("float[?]", MAX_SLIDES);
Box_UPX = ffi.new("float[?]", MAX_SLIDES);
Box_UPY = ffi.new("float[?]", MAX_SLIDES);
Box_UPZ = ffi.new("float[?]", MAX_SLIDES);

Cam_X, Cam_Y, Cam_Z = 0, 0, 0
Cam_Yaw, Cam_Pitch = 0, 0
Cam_FOV = 600
Cam_FWX, Cam_FWY, Cam_FWZ = 0, 0, 1
Cam_RTX, Cam_RTY, Cam_RTZ = 1, 0, 0
Cam_UPX, Cam_UPY, Cam_UPZ = 0, 1, 0

Way_X = ffi.new("float[?]", MAX_SLIDES)
Way_Y = ffi.new("float[?]", MAX_SLIDES)
Way_Z = ffi.new("float[?]", MAX_SLIDES)
Way_Yaw = ffi.new("float[?]", MAX_SLIDES)
Way_Pitch = ffi.new("float[?]", MAX_SLIDES)
tX, tY, tZ, tYaw, tPitch = 0, 0, 0, 0, 0
startX, startY, startZ, startYaw, startPitch = 0, 0, 0, 0, 0
lastFreeX, lastFreeY, lastFreeZ, lastFreeYaw, lastFreePitch = 0, 0, 0, 0, 0
TargetSlide = 0
activeSlide = 0
NumSlides = 0
manifest = {}
isMouseCaptured = true

globalTimer = 0
Font_Slide = nil
Font_UI = nil
SlideTitles = {}
-- THE FINITE STATE MACHINE (FSM)
STATE_FREEFLY    = 0
STATE_CINEMATIC  = 1
STATE_PRESENT    = 2
STATE_ZEN        = 3
STATE_HIBERNATED = 4

EngineState = STATE_PRESENT
TargetState = STATE_PRESENT

lerpT = 0
pendingResize = false
resizeTimer = 0

function ReinitBuffers()
    -- ALWAYS query the true physical pixels, ignoring OS display scaling!
    local pixel_w, pixel_h = love.graphics.getPixelDimensions()

    CANVAS_W, CANVAS_H = pixel_w, pixel_h
    HALF_W, HALF_H = pixel_w * 0.5, pixel_h * 0.5

    ScreenBuffer = love.image.newImageData(CANVAS_W, CANVAS_H)
    ScreenImage = love.graphics.newImage(ScreenBuffer)
    ScreenPtr = ffi.cast("uint32_t*", ScreenBuffer:getPointer())
    ZBuffer = ffi.new("float[?]", CANVAS_W * CANVAS_H)
    
    Cam_FOV = (CANVAS_W / 800) * 600
end

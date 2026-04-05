lua-ffi-gemini is a high-performance 3D software renderer  
built on Data-Oriented Design (DOD) and LuaJIT FFI  
for maximum throughput.  

Uses a Structure of Arrays (SoA) layout with raw FFI buffers  
to eliminate garbage collection spikes and ensure  
cache-friendly linear memory access.  

Executes a deterministic Transform → Project → Rasterize pipeline  
stripped of branching logic to keep compiled  
LuaJIT traces pinned to bare metal.  

Features a Zero-Config Procedural Bridge where sparse JSON manifests  
are algorithmically expanded into sweeping,  
hardware-validated 3D camera waypoints.  

Employs a custom rasterizer with a depth-tested Z-buffer,  
decoupled Lambertian lighting, and baked ambient shadows  
writing directly to a 32-bit screen pointer.  

Simulates 500+ kinetic entities with local-space collision,  
overlaid with cinematic CRT post-processing  
in exclusive, zero-latency fullscreen.

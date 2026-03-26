lua-ffi-gemini is a high-performance 3D software renderer
built on Data-Oriented Design (DOD) and LuaJIT FFI
for maximum throughput.

Uses a Structure of Arrays (SoA) layout with raw FFI buffers
to eliminate garbage collection spikes and ensure
cache-friendly linear access.

A deterministic Transform → Project → Rasterize flow
that avoids branching logic to maintain
high instruction speed.

Features a decoupled architecture where a Shape Factory
provides a raw data manifest, while the engine
handles hardware-validated camera waypoints.

A custom scanline implementation with a Z-buffer
and flat shading, writing directly to a
32-bit screen pointer.

Manages 500+ dynamic entities with
Local-Space Collision and
Helix Steering gravity.

Locked 90 FPS in
exclusive fullscreen.

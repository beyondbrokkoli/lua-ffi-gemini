High-performance software renderer utilizing Data-Oriented Design and a Structure of Arrays (SoA) memory layout. The engine prioritizes feature density and execution speed through direct FFI memory management and a deterministic single-path rendering pipeline.
Core Architecture

The system uses raw FFI memory buffers instead of object-oriented tables to ensure linear memory access and eliminate garbage collection spikes during the render loop. The rendering logic follows a strict Transform-Project-Rasterize flow, intentionally avoiding branching logic like if-then-else for micro-rejections to maintain a simplified mental model and cache efficiency.
Engine and Content Decoupling

The program separates geometry generation from the layout engine. A slide manifest defines the raw data for objects (position, dimensions, and angle), while the main engine iterates through this data once to calculate camera waypoints and viewing distances based on the current field of view and canvas resolution.
Performance and Scaling

  Target Performance: 90 FPS in exclusive fullscreen mode.

  Capacity: Supports over 500 dynamic low-poly torus objects with real-time collision detection.

  Culling: Sphere-to-frustum clipping is integrated into the projection pass to minimize processed line counts.

  Physics: Includes a bounce logic system for objects interacting with slide boundaries and a helix gravity pull to keep objects within a central corridor.

Component Breakdown

  Main Engine (main.lua): Manages FFI definitions, SoA buffers, scanline rasterization, and camera basis updates.

  Layout Manifest (SlidesInternal): Acts as a shape factory to build 3D slide geometry and define their spatial orientation without accessing engine-private variables.

  Scanline Rasterizer: A custom implementation for triangle filling with depth testing via a Z-buffer and basic flat shading based on surface normals.

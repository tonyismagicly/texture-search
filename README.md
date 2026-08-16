# Texture Search

A CUDA-accelerated Minecraft texture rotation scanner based on [TextureRotations by 19MisterX98](https://github.com/19MisterX98/TextureRotations).

## Features

- CUDA GPU acceleration
- Large X/Z coordinate range searching
- Configurable Y-level range
- Custom starting Y-level
- Alternating Y-level search
  - `75 → 76 → 74 → 77 → 73 → ...`
- Top-to-bottom Y-level search
- Custom texture rotation formations
- Supports different NVIDIA GPUs
- Formation shape is fully configurable

## Requirements

### Linux

- NVIDIA GPU
- NVIDIA drivers
- CUDA Toolkit / `nvcc`
- GCC
- C++17-compatible compiler

### Windows

- NVIDIA GPU
- NVIDIA drivers
- CUDA Toolkit
- Microsoft Visual C++ (MSVC)

## Building on Linux

Set `CUDA_PATH` to your CUDA installation.

    export CUDA_PATH=/path/to/cuda

On NixOS:

    export CUDA_PATH=/nix/store/...-cuda-merged-12.9

Build:

    chmod +x build.sh
    ./build.sh

The executable will be created at:

    build/texture-search

Run it:

    ./build/texture-search

## Building on Windows

Windows builds require the CUDA Toolkit and MSVC.

Run:

    build-windows.bat

The executable will be created at:

    build-windows\texture-search.exe

## Configuration

Most configuration is in:

    src/main.cu

### X/Z Range

    constexpr int xMin = -1'000'000;
    constexpr int xMax =  1'000'000;

    constexpr int zMin = -1'000'000;
    constexpr int zMax =  1'000'000;

### Y Range

    constexpr int yMin = 55;
    constexpr int yMax = 125;

### Starting Y-Level

    constexpr int yStart = 75;

### Alternating Y-Level Search

    constexpr bool alternateFromStart = true;

With `yStart = 75`, the search order is:

    75
    76
    74
    77
    73
    78
    72
    ...

### Top-to-Bottom Search

    constexpr bool topToBottom = true;

For a Y range of 55–125:

    125
    124
    123
    ...
    55

## Texture Rotation Formation

The formation is defined in:

    src/main.cu

Example:

    const std::vector<RotationInfo> formation = {
        { 0, 0,  0, 1, false },
        {-1, 0,  0, 1, false },
        {-2, 0,  0, 2, false },
        { 0, 0, -1, 2, false },
        // ...
    };

Each entry is:

    { X offset, Y offset, Z offset, rotation, isSide }

The formation can be replaced with any set of rotation data.

## Credits

Based on:

TextureRotations by 19MisterX98

https://github.com/19MisterX98/TextureRotations

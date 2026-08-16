#pragma once

#include <cuda_runtime.h>

struct RotationInfo {
    int x;
    int y;
    int z;
    int rotation;
    bool isSide;
};

struct SearchConfig {
    int xMin;
    int xMax;
    int zMin;
    int zMax;
};

void launchSearch(
    int y,
    const SearchConfig& config,
    const RotationInfo* dFormation,
    int formationSize,
    int* dResultX,
    int* dResultZ,
    unsigned int* dResultCount,
    unsigned int maxResults,
    cudaStream_t stream
);

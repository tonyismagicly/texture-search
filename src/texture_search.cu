#include "texture_search.cuh"

#include <cuda_runtime.h>

#include <cstdint>
#include <cstddef>


namespace
{

// ============================================================================
// Java Random constants
// ============================================================================

constexpr uint64_t MULTIPLIER = 0x5DEECE66DULL;
constexpr uint64_t MASK       = (1ULL << 48) - 1ULL;


// ============================================================================
// Constant memory
// ============================================================================
//
// 1024 RotationInfo entries is well within CUDA's 64 KiB constant-memory
// limit for the normal small RotationInfo structure.
//

constexpr int MAX_CONSTANT_FORMATION = 1024;

__constant__
RotationInfo cFormation[MAX_CONSTANT_FORMATION];


// ============================================================================
// Exact Java coordinate random
// ============================================================================
//
// Original Java:
//
// private static long getCoordRandom(int x, int y, int z) {
//     long l = (long)(x * 3129871)
//            ^ (long)z * 116129781L
//            ^ (long)y;
//
//     l = l * l * 42317861L + l * 11L;
//
//     return l;
// }
//
// Important:
//
//     x * 3129871
//
// is performed as a Java int BEFORE being converted to long.
//
// Java long arithmetic wraps at 64 bits.
//

__device__ __forceinline__
uint64_t coordinateRandom(
    int x,
    int y,
    int z
)
{
    // Reproduce Java's signed 32-bit overflow for:
    //
    // x * 3129871
    //
    const uint32_t xProductBits =
        static_cast<uint32_t>(
            static_cast<int64_t>(x) * 3129871LL
        );

    const int32_t xProduct =
        static_cast<int32_t>(xProductBits);


    uint64_t l =
        static_cast<uint64_t>(
            static_cast<int64_t>(xProduct)
        );


    l ^=
        static_cast<uint64_t>(
            static_cast<int64_t>(z) * 116129781LL
        );


    l ^=
        static_cast<uint64_t>(
            static_cast<int64_t>(y)
        );


    // Java long overflow is modulo 2^64.
    l =
        l * l * 42317861ULL
        +
        l * 11ULL;


    return l;
}


// ============================================================================
// Exact Java getCoordinateRandom()
// ============================================================================
//
// Java:
//
// static long getCoordinateRandom(int x, int y, int z) {
//     return getCoordRandom(x, y, z) >> 16;
// }
//
// The Java >> is an arithmetic signed shift.
//

__device__ __forceinline__
uint64_t getCoordinateRandom(
    int x,
    int y,
    int z
)
{
    const int64_t value =
        static_cast<int64_t>(
            coordinateRandom(x, y, z)
        );

    return static_cast<uint64_t>(
        value >> 16
    );
}


// ============================================================================
// Exact vanilla texture calculation
// ============================================================================
//
// Original Java:
//
// long seed = TextureProvider.getCoordinateRandom(x, y, z);
// seed = (seed ^ multiplier);
// seed = seed * multiplier + 11L & mask;
//
// int next = (int)(seed >> 48 - 31);
//
// return (int)((4 * (long)next) >> 31) % mod;
//
//
//
// Since:
//
//     48 - 31 = 17
//
// next is:
//
//     seed >> 17
//
// And:
//
//     (4 * next) >> 31
//
// is:
//
//     next >> 29
//
// because next is a non-negative 31-bit value.
//

__device__ __forceinline__
int textureVariant(
    int x,
    int y,
    int z
)
{
    uint64_t seed =
        getCoordinateRandom(
            x,
            y,
            z
        );


    seed ^=
        MULTIPLIER;


    seed =
        (
            seed * MULTIPLIER
            +
            11ULL
        )
        &
        MASK;


    const int next =
        static_cast<int>(
            seed >> 17
        );


    // Equivalent to:
    //
    // (4L * next) >> 31
    //
    // from the Java implementation.

    return next >> 29;
}


// ============================================================================
// Formation matching
// ============================================================================
//
// We do all non-side/mod-4 checks first.
//
// A mismatch normally happens very early, so this dramatically reduces
// the number of texture calculations that reach the side checks.
//
// No assumptions are made about:
//   - formation size
//   - X/Z/Y offsets
//   - shape
//   - rotation values
//   - number of side entries
//

__device__ __forceinline__
bool matchesConstant(
    int x,
    int y,
    int z,
    int formationSize
)
{
    // ------------------------------------------------------------------------
    // Top / non-side checks
    // ------------------------------------------------------------------------

    for (int i = 0; i < formationSize; ++i) {

        const RotationInfo info =
            cFormation[i];


        if (info.isSide) {
            continue;
        }


        const int actual =
            textureVariant(
                x + info.x,
                y + info.y,
                z + info.z
            );


        if (actual != info.rotation) {
            return false;
        }
    }


    // ------------------------------------------------------------------------
    // Side checks
    //
    // Original code calls getTexture(..., 2).
    //
    // Since textureVariant() gives 0..3:
    //
    //     variant % 2
    //
    // is simply:
    //
    //     variant & 1
    // ------------------------------------------------------------------------

    for (int i = 0; i < formationSize; ++i) {

        const RotationInfo info =
            cFormation[i];


        if (!info.isSide) {
            continue;
        }


        const int actual =
            textureVariant(
                x + info.x,
                y + info.y,
                z + info.z
            )
            &
            1;


        if (actual != info.rotation) {
            return false;
        }
    }


    return true;
}


// ============================================================================
// Generic global-memory matcher
// ============================================================================
//
// Used when the formation is too large for constant memory.
//

__device__ __forceinline__
bool matchesGlobal(
    int x,
    int y,
    int z,

    const RotationInfo* __restrict__ formation,
    int formationSize
)
{
    // Non-side checks first.

    for (int i = 0; i < formationSize; ++i) {

        const RotationInfo info =
            formation[i];


        if (info.isSide) {
            continue;
        }


        const int actual =
            textureVariant(
                x + info.x,
                y + info.y,
                z + info.z
            );


        if (actual != info.rotation) {
            return false;
        }
    }


    // Side checks.

    for (int i = 0; i < formationSize; ++i) {

        const RotationInfo info =
            formation[i];


        if (!info.isSide) {
            continue;
        }


        const int actual =
            textureVariant(
                x + info.x,
                y + info.y,
                z + info.z
            )
            &
            1;


        if (actual != info.rotation) {
            return false;
        }
    }


    return true;
}


// ============================================================================
// Kernel configuration
// ============================================================================
//
// 32 x 8 = 256 threads.
//
// This is deliberately not specialized for your current formation shape.
//

constexpr int BLOCK_X = 32;
constexpr int BLOCK_Z = 8;


// ============================================================================
// Constant-memory kernel
// ============================================================================

__global__
void searchKernelConstant(
    int y,

    int xMin,
    int xMax,

    int zMin,
    int zMax,

    int formationSize,

    int* __restrict__ resultX,
    int* __restrict__ resultZ,

    unsigned int* __restrict__ resultCount,
    unsigned int maxResults
)
{
    const int localX =
        static_cast<int>(
            blockIdx.x * blockDim.x
            +
            threadIdx.x
        );


    const int localZ =
        static_cast<int>(
            blockIdx.y * blockDim.y
            +
            threadIdx.y
        );


    const int xStride =
        static_cast<int>(
            gridDim.x * blockDim.x
        );


    const int zStride =
        static_cast<int>(
            gridDim.y * blockDim.y
        );


    // ------------------------------------------------------------------------
    // Stride through Z.
    // ------------------------------------------------------------------------

    for (
        int z = zMin + localZ;
        z <= zMax;
        z += zStride
    ) {

        // --------------------------------------------------------------------
        // Stride through X.
        // --------------------------------------------------------------------

        for (
            int x = xMin + localX;
            x <= xMax;
            x += xStride
        ) {

            if (!matchesConstant(
                    x,
                    y,
                    z,
                    formationSize
                )) {

                continue;
            }


            const unsigned int slot =
                atomicAdd(
                    resultCount,
                    1U
                );


            if (slot < maxResults) {

                resultX[slot] = x;
                resultZ[slot] = z;
            }
        }
    }
}


// ============================================================================
// Global-memory kernel
// ============================================================================

__global__
void searchKernelGlobal(
    int y,

    int xMin,
    int xMax,

    int zMin,
    int zMax,

    const RotationInfo* __restrict__ formation,
    int formationSize,

    int* __restrict__ resultX,
    int* __restrict__ resultZ,

    unsigned int* __restrict__ resultCount,
    unsigned int maxResults
)
{
    const int localX =
        static_cast<int>(
            blockIdx.x * blockDim.x
            +
            threadIdx.x
        );


    const int localZ =
        static_cast<int>(
            blockIdx.y * blockDim.y
            +
            threadIdx.y
        );


    const int xStride =
        static_cast<int>(
            gridDim.x * blockDim.x
        );


    const int zStride =
        static_cast<int>(
            gridDim.y * blockDim.y
        );


    for (
        int z = zMin + localZ;
        z <= zMax;
        z += zStride
    ) {

        for (
            int x = xMin + localX;
            x <= xMax;
            x += xStride
        ) {

            if (!matchesGlobal(
                    x,
                    y,
                    z,
                    formation,
                    formationSize
                )) {

                continue;
            }


            const unsigned int slot =
                atomicAdd(
                    resultCount,
                    1U
                );


            if (slot < maxResults) {

                resultX[slot] = x;
                resultZ[slot] = z;
            }
        }
    }
}


// ============================================================================
// Grid selection
// ============================================================================
//
// We intentionally launch a relatively small number of blocks and have each
// block stride through the entire search space.
//
// This avoids enormous grids for ranges such as:
//
//     -1,000,000 .. +1,000,000
//
// while still keeping enough blocks resident to saturate the GPU.
//
// No assumption is made about the shape of the search range.
//

static dim3 makeGrid(
    const SearchConfig& config,
    const cudaDeviceProp& props
)
{
    const uint64_t width =
        static_cast<uint64_t>(
            static_cast<int64_t>(config.xMax)
            -
            static_cast<int64_t>(config.xMin)
        )
        +
        1ULL;


    const uint64_t height =
        static_cast<uint64_t>(
            static_cast<int64_t>(config.zMax)
            -
            static_cast<int64_t>(config.zMin)
        )
        +
        1ULL;


    const uint64_t blocksXNeeded =
        (
            width
            +
            static_cast<uint64_t>(BLOCK_X)
            -
            1ULL
        )
        /
        static_cast<uint64_t>(BLOCK_X);


    const uint64_t blocksZNeeded =
        (
            height
            +
            static_cast<uint64_t>(BLOCK_Z)
            -
            1ULL
        )
        /
        static_cast<uint64_t>(BLOCK_Z);


    // About 8 blocks per SM.

    uint64_t targetBlocks =
        static_cast<uint64_t>(
            props.multiProcessorCount
        )
        *
        8ULL;


    if (targetBlocks == 0) {
        targetBlocks = 1;
    }


    // Keep X reasonably wide.

    uint64_t gridX =
        targetBlocks;


    if (gridX > 256ULL) {
        gridX = 256ULL;
    }


    if (gridX > blocksXNeeded) {
        gridX = blocksXNeeded;
    }


    if (gridX == 0) {
        gridX = 1;
    }


    // Divide desired blocks across Z.

    uint64_t gridZ =
        (
            targetBlocks
            +
            gridX
            -
            1ULL
        )
        /
        gridX;


    if (gridZ == 0) {
        gridZ = 1;
    }


    if (gridZ > blocksZNeeded) {
        gridZ = blocksZNeeded;
    }


    if (gridZ == 0) {
        gridZ = 1;
    }


    return dim3(
        static_cast<unsigned int>(gridX),
        static_cast<unsigned int>(gridZ),
        1
    );
}

} // namespace


// ============================================================================
// Public launch function
// ============================================================================

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
)
{
    int device = 0;

    cudaGetDevice(&device);


    cudaDeviceProp props{};

    cudaGetDeviceProperties(
        &props,
        device
    );


    const dim3 grid =
        makeGrid(
            config,
            props
        );


    const dim3 block(
        BLOCK_X,
        BLOCK_Z,
        1
    );


    // ========================================================================
    // Constant-memory path
    // ========================================================================

    if (formationSize <= MAX_CONSTANT_FORMATION) {

        /*
         * Copy the formation into constant memory.
         *
         * We intentionally perform this every launch rather than relying on
         * static host-side cache state. This keeps launchSearch() correct if
         * the caller changes the formation between searches.
         *
         * The formation is tiny compared with the actual GPU search, so this
         * transfer is negligible.
         */

        cudaMemcpyToSymbol(
            cFormation,
            dFormation,
            static_cast<size_t>(formationSize)
            *
            sizeof(RotationInfo),
            0,
            cudaMemcpyDeviceToDevice
        );


        searchKernelConstant<<<
            grid,
            block,
            0,
            stream
        >>>(
            y,

            config.xMin,
            config.xMax,

            config.zMin,
            config.zMax,

            formationSize,

            dResultX,
            dResultZ,

            dResultCount,
            maxResults
        );


        return;
    }


    // ========================================================================
    // Large-formation fallback
    // ========================================================================

    searchKernelGlobal<<<
        grid,
        block,
        0,
        stream
    >>>(
        y,

        config.xMin,
        config.xMax,

        config.zMin,
        config.zMax,

        dFormation,
        formationSize,

        dResultX,
        dResultZ,

        dResultCount,
        maxResults
    );
}

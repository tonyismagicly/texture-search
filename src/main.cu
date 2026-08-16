#include "texture_search.cuh"

#include <cuda_runtime.h>

#include <algorithm>
#include <chrono>
#include <cstdlib>
#include <iostream>
#include <vector>

static void checkCuda(
    cudaError_t error,
    const char* operation
)
{
    if (error != cudaSuccess) {

        std::cerr
            << "CUDA error during "
            << operation
            << ": "
            << cudaGetErrorString(error)
            << '\n';

        std::exit(EXIT_FAILURE);
    }
}

static std::vector<int> makeYOrder(
    int yMin,
    int yMax,
    int yStart,
    bool alternateFromStart,
    bool topToBottom
)
{
    std::vector<int> result;

    if (yMin > yMax) {
        return result;
    }

    // Top -> bottom.
    if (topToBottom) {

        result.reserve(
            static_cast<size_t>(yMax - yMin + 1)
        );

        for (int y = yMax; y >= yMin; --y) {
            result.push_back(y);
        }

        return result;
    }

    // Normal bottom -> top.
    if (!alternateFromStart) {

        result.reserve(
            static_cast<size_t>(yMax - yMin + 1)
        );

        for (int y = yMin; y <= yMax; ++y) {
            result.push_back(y);
        }

        return result;
    }

    // Clamp starting point into the search range.
    yStart = std::max(yMin, std::min(yStart, yMax));

    result.reserve(
        static_cast<size_t>(yMax - yMin + 1)
    );

    // Start at yStart.
    result.push_back(yStart);

    for (int offset = 1; ; ++offset) {

        bool added = false;

        // Above the starting Y.
        const int above = yStart + offset;

        if (above <= yMax) {
            result.push_back(above);
            added = true;
        }

        // Below the starting Y.
        const int below = yStart - offset;

        if (below >= yMin) {
            result.push_back(below);
            added = true;
        }

        if (!added) {
            break;
        }
    }

    return result;
}

int main()
{
    //
    // Same search area as your Java program.
    //
    constexpr int xMin = -500'000;
    constexpr int xMax =  500'000;

    constexpr int zMin = -500'000;
    constexpr int zMax =  500'000;

    constexpr int yMin = 55;
    constexpr int yMax = 125;

    // Starting Y for alternating/outward search.
    constexpr int yStart = 75;

    // true  = yStart, yStart+1, yStart-1, yStart+2, yStart-2...
    // false = normal yMin -> yMax unless topToBottom is true.
    constexpr bool alternateFromStart = true;

    // true  = yMax -> yMin
    // false = use alternateFromStart or normal yMin -> yMax
    constexpr bool topToBottom = false;

    //
    // Your exact formation.
    //
    const std::vector<RotationInfo> formation = {
	{ 0, 0,   0, 1, false },
        {-1, 0,   0, 1, false },
        {-2, 0,   0, 2, false },
        { 0, 0,  -1, 2, false },
        {-1, 0,  -1, 3, false },
        {-2, 0,  -1, 2, false },
        { 0, 0,  -2, 3, false },
        {-1, 0,  -2, 3, false },
        {-2, 0,  -2, 2, false },
        { 0, 0,  -3, 1, false },
        {-1, 0,  -3, 1, false },
        {-2, 0,  -3, 1, false },
        {-1, 0,  -4, 1, false },
        {-2, 0,  -4, 0, false },
        {-2, 0,  -5, 0, false },
        {-1, 0,  -6, 0, false },
        {-2, 0,  -6, 1, false },
        {-1, 0,  -7, 1, false },
        {-2, 0,  -7, 1, false },
        {-2, 0,  -8, 3, false },
        {-1, 0,  -9, 2, false },
        {-2, 0,  -9, 2, false },
        { 0, 0, -10, 2, false },
        {-1, 0, -10, 2, false },
        {-2, 0, -10, 0, false },
        { 0, 0, -11, 0, false },
        {-1, 0, -11, 0, false },
        {-2, 0, -11, 1, false },
        { 0, 0, -12, 2, false },
        {-1, 0, -12, 1, false },
        {-2, 0, -12, 1, false },
        { 0, 0, -13, 3, false },
        {-1, 0, -13, 0, false },
        {-2, 0, -13, 0, false },
        { 1, 0, -14, 3, false },
        { 0, 0, -14, 1, false },
    };


    constexpr unsigned int MAX_RESULTS = 1'000'000;


    //
    // GPU information.
    //
    int deviceCount = 0;

    checkCuda(
        cudaGetDeviceCount(&deviceCount),
        "cudaGetDeviceCount"
    );

    if (deviceCount == 0) {
        std::cerr << "No CUDA GPU found.\n";
        return EXIT_FAILURE;
    }


    cudaDeviceProp props{};

    checkCuda(
        cudaGetDeviceProperties(&props, 0),
        "cudaGetDeviceProperties"
    );


    std::cout
        << "GPU: "
        << props.name
        << '\n';

    std::cout
        << "Compute capability: "
        << props.major
        << '.'
        << props.minor
        << '\n';


    //
    // Upload formation.
    //
    RotationInfo* dFormation = nullptr;

    checkCuda(
        cudaMalloc(
            reinterpret_cast<void**>(&dFormation),
            formation.size() * sizeof(RotationInfo)
        ),
        "cudaMalloc(dFormation)"
    );

    checkCuda(
        cudaMemcpy(
            dFormation,
            formation.data(),
            formation.size() * sizeof(RotationInfo),
            cudaMemcpyHostToDevice
        ),
        "cudaMemcpy(dFormation)"
    );


    //
    // Result buffers.
    //
    int* dResultX = nullptr;
    int* dResultZ = nullptr;
    unsigned int* dResultCount = nullptr;


    checkCuda(
        cudaMalloc(
            reinterpret_cast<void**>(&dResultX),
            MAX_RESULTS * sizeof(int)
        ),
        "cudaMalloc(dResultX)"
    );

    checkCuda(
        cudaMalloc(
            reinterpret_cast<void**>(&dResultZ),
            MAX_RESULTS * sizeof(int)
        ),
        "cudaMalloc(dResultZ)"
    );

    checkCuda(
        cudaMalloc(
            reinterpret_cast<void**>(&dResultCount),
            sizeof(unsigned int)
        ),
        "cudaMalloc(dResultCount)"
    );


    //
    // Host-side result buffers.
    //
    std::vector<int> resultX(MAX_RESULTS);
    std::vector<int> resultZ(MAX_RESULTS);


    SearchConfig config{
        xMin,
        xMax,
        zMin,
        zMax
    };


    //
    // Start timing.
    //
    auto totalStart =
        std::chrono::steady_clock::now();


    const std::vector<int> yOrder =
        makeYOrder(
            yMin,
            yMax,
            yStart,
            alternateFromStart,
            topToBottom
        );

    for (int y : yOrder) {

        auto yStart =
            std::chrono::steady_clock::now();


        std::cout
            << "Searching Y = "
            << y
            << " ..."
            << std::flush;


        checkCuda(
            cudaMemset(
                dResultCount,
                0,
                sizeof(unsigned int)
            ),
            "cudaMemset(dResultCount)"
        );


        //
        // Launch GPU search.
        //
        launchSearch(
            y,
            config,
            dFormation,
            static_cast<int>(formation.size()),
            dResultX,
            dResultZ,
            dResultCount,
            MAX_RESULTS,
            nullptr
        );


        checkCuda(
            cudaGetLastError(),
            "launchSearch"
        );

        checkCuda(
            cudaDeviceSynchronize(),
            "cudaDeviceSynchronize"
        );


        //
        // Get number of matches.
        //
        unsigned int count = 0;

        checkCuda(
            cudaMemcpy(
                &count,
                dResultCount,
                sizeof(count),
                cudaMemcpyDeviceToHost
            ),
            "cudaMemcpy(count)"
        );


        const bool overflow =
            count > MAX_RESULTS;

        const unsigned int stored =
            overflow
                ? MAX_RESULTS
                : count;


        //
        // Download matches.
        //
        if (stored > 0) {

            checkCuda(
                cudaMemcpy(
                    resultX.data(),
                    dResultX,
                    stored * sizeof(int),
                    cudaMemcpyDeviceToHost
                ),
                "cudaMemcpy(resultX)"
            );

            checkCuda(
                cudaMemcpy(
                    resultZ.data(),
                    dResultZ,
                    stored * sizeof(int),
                    cudaMemcpyDeviceToHost
                ),
                "cudaMemcpy(resultZ)"
            );


            for (unsigned int i = 0; i < stored; ++i) {

                std::cout
                    << '\n'
                    << "X: "
                    << resultX[i]
                    << " Y: "
                    << y
                    << " Z: "
                    << resultZ[i];
            }
        }


        auto yEnd =
            std::chrono::steady_clock::now();

        const double seconds =
            std::chrono::duration<double>(
                yEnd - yStart
            ).count();


        std::cout
            << '\n'
            << "Y = "
            << y
            << " finished in "
            << seconds
            << " seconds";


        if (count > 0) {
            std::cout
                << " ("
                << count
                << " matches)";
        }


        if (overflow) {
            std::cout
                << " [RESULT BUFFER FULL]";
        }


        std::cout << '\n';
    }


    auto totalEnd =
        std::chrono::steady_clock::now();


    const double totalSeconds =
        std::chrono::duration<double>(
            totalEnd - totalStart
        ).count();


    std::cout
        << '\n'
        << "Finished all Y levels in "
        << totalSeconds
        << " seconds.\n";


    //
    // Cleanup.
    //
    cudaFree(dFormation);
    cudaFree(dResultX);
    cudaFree(dResultZ);
    cudaFree(dResultCount);


    return EXIT_SUCCESS;
}

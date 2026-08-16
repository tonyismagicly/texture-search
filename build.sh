#!/usr/bin/env bash

set -euo pipefail

NVCC="${NVCC:-nvcc}"
GCC="${GCC:-gcc}"

if [[ -z "${CUDA_PATH:-}" ]]; then
    echo "ERROR: CUDA_PATH is not set."
    echo "Example:"
    echo '  export CUDA_PATH=/nix/store/...-cuda-merged-12.9'
    exit 1
fi

echo "Using:"
echo "  nvcc:      $(command -v "$NVCC")"
echo "  gcc:       $(command -v "$GCC")"
echo "  CUDA_PATH: $CUDA_PATH"
echo

mkdir -p build

"$NVCC" \
    -std=c++17 \
    -O3 \
    -Xcompiler=-O3 \
    -ccbin="$GCC" \
    -I"$CUDA_PATH/include" \
    -Iinclude \
    src/main.cu \
    src/texture_search.cu \
    -L"$CUDA_PATH/lib" \
    -lcudart \
    -o build/texture-search

echo
echo "Built successfully:"
echo "  build/texture-search"

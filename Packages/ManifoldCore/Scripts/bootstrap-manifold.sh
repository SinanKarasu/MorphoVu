#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
UPSTREAM_REPO="${UPSTREAM_REPO:-https://github.com/elalish/manifold.git}"
UPSTREAM_REF="${UPSTREAM_REF:-master}"
DEPLOYMENT_TARGET="${DEPLOYMENT_TARGET:-26.4}"
SRC_DIR="${ROOT_DIR}/.build/vendor/manifold-src"
BUILD_ROOT="${ROOT_DIR}/.build/vendor/manifold-build"
INCLUDE_DIR="${ROOT_DIR}/vendor/manifold-include"
XCFRAMEWORK_PATH="${ROOT_DIR}/vendor/ManifoldBinary.xcframework"

require_tool() {
    if ! command -v "$1" >/dev/null 2>&1; then
        echo "Missing required tool: $1" >&2
        exit 1
    fi
}

require_tool git
require_tool cmake
require_tool xcodebuild
require_tool lipo

mkdir -p "${ROOT_DIR}/.build/vendor"
mkdir -p "${INCLUDE_DIR}"

if [[ ! -d "${SRC_DIR}/.git" ]]; then
    git clone "${UPSTREAM_REPO}" "${SRC_DIR}"
fi

git -C "${SRC_DIR}" fetch --tags --prune origin
git -C "${SRC_DIR}" checkout "${UPSTREAM_REF}"

rm -rf "${BUILD_ROOT}" "${XCFRAMEWORK_PATH}"
mkdir -p "${BUILD_ROOT}"

build_variant() {
    local name="$1"
    local sysroot="$2"
    local system_name="$3"
    local archs="$4"
    local build_dir="${BUILD_ROOT}/${name}"
    local -a cmake_args=(
        -S "${SRC_DIR}"
        -B "${build_dir}"
        -G Xcode
        -DBUILD_SHARED_LIBS=OFF
        -DMANIFOLD_TEST=OFF
        -DMANIFOLD_CBIND=OFF
        -DCMAKE_OSX_ARCHITECTURES="${archs}"
        -DCMAKE_OSX_DEPLOYMENT_TARGET="${DEPLOYMENT_TARGET}"
    )

    if [[ -n "${system_name}" ]]; then
        cmake_args+=(-DCMAKE_SYSTEM_NAME="${system_name}")
    fi

    if [[ -n "${sysroot}" ]]; then
        cmake_args+=(-DCMAKE_OSX_SYSROOT="${sysroot}")
    fi

    cmake "${cmake_args[@]}"
    cmake --build "${build_dir}" --config Release --target manifold
}

find_built_library() {
    local build_dir="$1"
    local library_path=""
    while IFS= read -r candidate; do
        library_path="${candidate}"
        break
    done < <(find "${build_dir}" -path '*Release*' -name 'libmanifold.a' -print | sort)

    if [[ -z "${library_path}" ]]; then
        echo "Failed to locate libmanifold.a in ${build_dir}" >&2
        exit 1
    fi

    printf '%s\n' "${library_path}"
}

build_variant "macosx" "macosx" "" "arm64"
build_variant "xrsimulator-arm64" "xrsimulator" "visionOS" "arm64"
build_variant "xrsimulator-x86_64" "xrsimulator" "visionOS" "x86_64"
build_variant "xros" "xros" "visionOS" "arm64"

MACOS_LIB="$(find_built_library "${BUILD_ROOT}/macosx")"
XRSIM_ARM64_LIB="$(find_built_library "${BUILD_ROOT}/xrsimulator-arm64")"
XRSIM_X86_64_LIB="$(find_built_library "${BUILD_ROOT}/xrsimulator-x86_64")"
XROS_LIB="$(find_built_library "${BUILD_ROOT}/xros")"
UNIVERSAL_XRSIM_DIR="${BUILD_ROOT}/xrsimulator-universal"
UNIVERSAL_XRSIM_LIB="${UNIVERSAL_XRSIM_DIR}/libmanifold.a"

mkdir -p "${UNIVERSAL_XRSIM_DIR}"
lipo -create "${XRSIM_ARM64_LIB}" "${XRSIM_X86_64_LIB}" -output "${UNIVERSAL_XRSIM_LIB}"

rm -rf "${INCLUDE_DIR}/manifold"
mkdir -p "${INCLUDE_DIR}/manifold"
cp -R "${SRC_DIR}/include/manifold/." "${INCLUDE_DIR}/manifold/"
VERSION_HEADER="$(find "${BUILD_ROOT}" -path '*/include/manifold/version.h' -print | head -n 1 || true)"
if [[ -n "${VERSION_HEADER}" ]]; then
    cp "${VERSION_HEADER}" "${INCLUDE_DIR}/manifold/version.h"
fi

xcodebuild -create-xcframework \
    -library "${MACOS_LIB}" -headers "${INCLUDE_DIR}" \
    -library "${UNIVERSAL_XRSIM_LIB}" -headers "${INCLUDE_DIR}" \
    -library "${XROS_LIB}" -headers "${INCLUDE_DIR}" \
    -output "${XCFRAMEWORK_PATH}"

echo "Bootstrapped Manifold into:"
echo "  headers: ${INCLUDE_DIR}"
echo "  xcframework: ${XCFRAMEWORK_PATH}"

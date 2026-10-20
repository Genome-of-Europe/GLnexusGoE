#!/usr/bin/env bash
set -euo pipefail

PLATFORM="${PLATFORM:-linux/amd64}"
VERSION="$(git describe --tags --always --dirty 2>/dev/null || tr -d '[:space:]' < VERSION 2>/dev/null || echo 'latest')"
IMAGE_BUILDER="glnexus-builder"
IMAGE_RUNTIME="glnexus:${VERSION}"
VOL_BUILD="glnexus-build"
VOL_CCACHE="ccache"

run_in_builder() {
    docker run --platform "${PLATFORM}" --rm -it \
        -v "$(pwd)":/src \
        -v "${VOL_BUILD}":/build \
        -v "${VOL_CCACHE}":/root/.ccache \
        "${IMAGE_BUILDER}" "$@"
}

cmd="${1:-help}"
shift || true

case "${cmd}" in
    builder)
        echo "==> Building ${IMAGE_BUILDER} (${PLATFORM})..."
        docker build --platform "${PLATFORM}" --target glnexus-builder -t "${IMAGE_BUILDER}" .
        ;;
    dev|shell)
        echo "==> Entering interactive dev container..."
        run_in_builder /bin/bash
        ;;
    compile)
        echo "==> Compiling GLnexus into ${VOL_BUILD} volume..."
        run_in_builder bash -c "cmake -S /src -B /build -DCMAKE_BUILD_TYPE=Release && cmake --build /build -j\$(nproc)"
        ;;
    test)
        echo "==> Running ctest inside container..."
        run_in_builder ctest --test-dir /build -V "$@"
        ;;
    extract)
        echo "==> Extracting glnexus_cli from ${VOL_BUILD} volume to host..."
        docker run --platform "${PLATFORM}" --rm \
            -v "${VOL_BUILD}":/build \
            -v "$(pwd)":/out \
            "${IMAGE_BUILDER}" cp /build/glnexus_cli /out/
        chmod +x glnexus_cli
        echo "==> glnexus_cli extracted to $(pwd)/glnexus_cli"
        ;;
    runtime)
        "$0" extract
        echo "==> Building slim production runtime image (${IMAGE_RUNTIME} & glnexus:latest)..."
        docker build --platform "${PLATFORM}" \
            -t "${IMAGE_RUNTIME}" \
            -t "glnexus:latest" .
        ;;
    apptainer|sif)
        "$0" runtime
        SIF_OUT="${1:-glnexus_${VERSION}.sif}"
        echo "==> Building Apptainer SIF image (${SIF_OUT})..."
        if command -v apptainer >/dev/null 2>&1; then
            apptainer build --force "${SIF_OUT}" docker-daemon://"${IMAGE_RUNTIME}"
        else
            TAR_TMP="$(pwd)/.glnexus_${VERSION}.tar"
            trap 'rm -f "${TAR_TMP}"' EXIT
            echo "==> Native apptainer not found; using containerized Apptainer builder..."
            docker save "${IMAGE_RUNTIME}" -o "${TAR_TMP}"
            docker run --platform "${PLATFORM}" --privileged --rm \
                -v "$(pwd)":/work -w /work \
                -v "${TAR_TMP}":/tmp/img.tar:ro \
                ghcr.io/apptainer/apptainer:latest \
                apptainer build --force "${SIF_OUT}" docker-archive:/tmp/img.tar
            rm -f "${TAR_TMP}"
            trap - EXIT
        fi
        echo "==> Apptainer SIF created: $(pwd)/${SIF_OUT}"
        ;;
    clean)
        echo "==> Removing ${VOL_BUILD} volume..."
        docker volume rm -f "${VOL_BUILD}"
        ;;
    *)
        cat <<EOF
Usage: $0 <command>

Commands:
  builder    Build the x86 glnexus-builder image (once)
  dev        Enter interactive shell with live source, build volume, and ccache
  compile    Run non-interactive cmake configure & build inside container
  test       Run ctest suite inside container
  extract    Copy compiled glnexus_cli binary from volume to host
  runtime    Build slim production container (glnexus:latest)
  apptainer  Build standalone Apptainer SIF image (glnexus_<version>.sif)
  clean      Remove glnexus-build volume for a clean rebuild

Environment overrides:
  PLATFORM   Target platform (default: linux/amd64)
EOF
        exit 1
        ;;
esac

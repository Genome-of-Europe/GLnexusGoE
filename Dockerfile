# ==============================================================================
# Stage 1: glnexus-builder
# Reusable x86_64 Rocky Linux 9 development environment for volume-mounted workflows:
#   docker build --platform linux/amd64 --target glnexus-builder -t glnexus-builder .
#   docker run --platform linux/amd64 -it --rm \
#     -v $(pwd):/src \
#     -v glnexus-build:/build \
#     -v ccache:/root/.ccache \
#     glnexus-builder
# Inside container:
#   cmake -S /src -B /build -DCMAKE_BUILD_TYPE=Release
#   cmake --build /build -j$(nproc)
#   ctest --test-dir /build -V
# Clean rebuild (reset build volume):
#   docker volume rm glnexus-build
# ==============================================================================
FROM rockylinux:9 AS glnexus-builder
ENV LC_ALL=C.UTF-8
ENV LANG=C.UTF-8

RUN dnf install -y epel-release 'dnf-command(config-manager)' && \
    dnf config-manager --set-enabled crb && \
    dnf install -y --allowerasing \
        gcc-toolset-13-gcc gcc-toolset-13-gcc-c++ \
        cmake autoconf make file curl wget git-core \
        ccache \
        python3-pip \
        libdeflate-devel snappy-devel zlib-devel libzstd-devel jemalloc-devel \
        bcftools pv which tar bzip2 diffutils htslib-tools && \
    pip3 install --no-cache-dir PyVCF3 && \
    dnf clean all

ENV PATH="/opt/rh/gcc-toolset-13/root/usr/bin:${PATH}"

# Compiler cache config
ENV CCACHE_DIR=/root/.ccache
ENV CMAKE_C_COMPILER_LAUNCHER=ccache
ENV CMAKE_CXX_COMPILER_LAUNCHER=ccache

# Multi-arch jemalloc preload
RUN ln -sf /usr/lib64/libjemalloc.so.2 /usr/local/lib/libjemalloc.so.2 2>/dev/null || true
ENV LD_PRELOAD=/usr/local/lib/libjemalloc.so.2

# Explicit mount directories for volume workflow
RUN mkdir -p /src /build /root/.ccache
WORKDIR /src
CMD ["/bin/bash"]

# ==============================================================================
# Stage 2: Slim runtime image for deployment & Apptainer
# ==============================================================================
FROM rockylinux:9-minimal AS runtime
LABEL maintainer="DNAnexus"
ENV LC_ALL=C.UTF-8
ENV LANG=C.UTF-8

RUN microdnf install -y epel-release && \
    microdnf install -y \
        jemalloc bcftools pv htslib-tools \
        libdeflate snappy libzstd zlib && \
    microdnf clean all && \
    rm -rf /var/cache/yum /var/cache/dnf

RUN ln -sf /usr/lib64/libjemalloc.so.2 /usr/local/lib/libjemalloc.so.2 2>/dev/null || true
ENV LD_PRELOAD=/usr/local/lib/libjemalloc.so.2

COPY glnexus_cli /usr/local/bin/glnexus_cli

ENTRYPOINT ["/usr/local/bin/glnexus_cli"]
CMD ["--help"]

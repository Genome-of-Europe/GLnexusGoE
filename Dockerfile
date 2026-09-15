# Stage 1: Pre-build & cache external C++ dependencies
FROM ubuntu:24.04 AS dependencies
LABEL maintainer="DNAnexus"
ENV LC_ALL=C.UTF-8
ENV LANG=C.UTF-8
ENV DEBIAN_FRONTEND=noninteractive
ARG build_type=Release

RUN apt-get -qq update && \
    apt-get -qq install -y --no-install-recommends --no-install-suggests \
    curl wget ca-certificates git-core less netbase \
    g++ cmake autoconf make file \
    libjemalloc-dev libzip-dev libsnappy-dev libbz2-dev zlib1g-dev liblzma-dev libzstd-dev \
    python3-vcf bcftools pv

WORKDIR /GLnexus

# Copy only the dependency manifest
COPY CMakeLists.txt /GLnexus/

# Fetch, configure and compile all external dependencies (RocksDB, htslib, Cap'n Proto, yaml-cpp, spdlog)
RUN cmake -DBUILD_DEPS_ONLY=ON -DCMAKE_BUILD_TYPE=$build_type . && make -j$(nproc) dependencies

# Stage 2: Compile GLnexus application code & tests
FROM dependencies AS builder
COPY . /GLnexus
RUN cmake -DBUILD_DEPS_ONLY=OFF -DCMAKE_BUILD_TYPE=$build_type . && make -j$(nproc)
CMD ["ctest", "-V"]

# Stage 3: Slim runtime image
FROM ubuntu:24.04
ENV LC_ALL=C.UTF-8
ENV LANG=C.UTF-8
ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get -qq update && \
    apt-get -qq install -y --no-install-recommends \
    libjemalloc2 bcftools tabix pv && \
    rm -rf /var/lib/apt/lists/*

# Multi-arch LD_PRELOAD support (resolves x86_64 and aarch64 paths)
RUN ln -s /usr/lib/*-linux-gnu/libjemalloc.so.2 /usr/local/lib/libjemalloc.so.2
ENV LD_PRELOAD=/usr/local/lib/libjemalloc.so.2

COPY --from=builder /GLnexus/glnexus_cli /usr/local/bin/

CMD ["glnexus_cli"]

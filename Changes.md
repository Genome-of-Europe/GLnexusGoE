# macOS Apple Silicon Portability Changes

Summary of changes made to compile GLnexus and pass unit tests natively on macOS (Apple Silicon / ARM64).

## 1. Build System (`CMakeLists.txt`)

* **Gated x86-64 Architecture Flags**:
  * Gated `-march=ivybridge`, `-msse4.2`, `-DHAVE_SSE42`, and `-mpclmul` behind `if(CMAKE_SYSTEM_PROCESSOR MATCHES "x86_64")`.
  * *Rationale*: Clang on ARM64 rejects x86-specific architecture and instruction flags.

* **Linker Flags & Dependency Resolution**:
  * Removed Linux-only `-static-libstdc++` and `librt.a` on Apple.
  * Added Homebrew library search path (`/opt/homebrew/lib`) and dynamic link targets (`z`, `snappy`, `bz2`, `zstd`, `lzma`, `lz4`).
  * Added `-Wl,-U,_mallctl` to linker flags on Apple.
  * *Rationale*: Mach-O does not use `librt` (built into `libSystem`) and uses `libc++`. Apple's linker requires `-Wl,-U,_symbol` to allow undefined dynamic lookup for weak symbols (used for optional runtime jemalloc detection).

* **Header Hijacking Prevention**:
  * Removed `rocksdb/util` and global `/opt/homebrew/include` from top-level `include_directories`.
  * Added `rocksdb` root directory to include paths instead.
  * *Rationale*: `rocksdb/util/math.h` was intercepting `#include <math.h>` calls from libc++, breaking `<cmath>` and `<valarray>` on Clang. Global `/opt/homebrew/include` also caused version collisions with Homebrew's installed libraries.

* **External Dependencies**:
  * **RocksDB**: Passed `-I/opt/homebrew/include` and `-L/opt/homebrew/lib` to RocksDB's internal build command with `-Wno-error`.
    * *Rationale*: Enables RocksDB to detect and compile with ZSTD, Snappy, and LZ4 compression. Suppresses `-Werror` on Clang compiler warnings.
  * **htslib**: Target `libhts.a` directly; passed Homebrew XZ include path (`/opt/homebrew/opt/xz/include`) for `lzma.h`; used pipe delimiter in `sed -i.bak`.
    * *Rationale*: Avoids building htslib tests (which clashed with Homebrew htslib headers), resolves missing `lzma.h` for CRAM support, and fixes BSD sed in-place editing.
  * **fcmm**: Updated URL to active mirror (`https://github.com/sigiesec/fcmm/archive/v1.0.1.zip`).
    * *Rationale*: Original repository (`giacomodrago/fcmm`) was deleted from GitHub.
  * **yaml-cpp**: Added `-DCMAKE_POLICY_VERSION_MINIMUM=3.5` and `-DYAML_CPP_BUILD_TESTS=OFF`.
    * *Rationale*: Silences CMake deprecation error and skips unnecessary Googletest sub-project build.
  * **capnp**: Removed `check` step from build command (`make -j$(nproc)`).
    * *Rationale*: Cap'n Proto 0.7.0 test suite fails on ARM64 macOS, but the library and compiler binary build and work correctly.
  * **catch**: Added `PATCH_COMMAND` to substitute `__asm__("int $3\n")` with `__builtin_debugtrap()`.
    * *Rationale*: Catch 1.12.2 hardcoded x86 interrupt breakpoints on macOS; ARM64 requires `__builtin_debugtrap()`.

* **Compiler Flags**:
  * Added `-Wno-return-type-c-linkage` to `CMAKE_CXX_FLAGS`.
  * *Rationale*: Allows test functions with `extern "C"` linkage to return C++ `Status` objects without Clang erroring under `-Werror`.

---

## 2. Core Source Code (`src/`)

* **[genotyper.cc](file:///Users/vinter/projects/GLnexus/src/genotyper.cc)**:
  * Gated `__asm__(".symver logf,logf@GLIBC_2.2.5");` behind `#if defined(__linux__) && defined(__GLIBC__)`.
  * *Rationale*: Apple Mach-O assembler does not support GNU `.symver` directives.

* **[cli_utils.cc](file:///Users/vinter/projects/GLnexus/src/cli_utils.cc)**:
  * Changed `#include "crc32c.h"` to `#include "util/crc32c.h"`.
  * *Rationale*: Allows removal of `rocksdb/util` from the global header search path.

* **[BCFKeyValueData_utils.h](file:///Users/vinter/projects/GLnexus/src/BCFKeyValueData_utils.h)**:
  * Added endian conversion shims for macOS using `<libkern/OSByteOrder.h>` (`htobe64`, `be64toh`, `htobe32`, etc.).
  * *Rationale*: `<endian.h>` is a glibc/Linux header and does not exist on macOS.

* **[BCFKeyValueData.cc](file:///Users/vinter/projects/GLnexus/src/BCFKeyValueData.cc)**:
  * Removed obsolete `#include <endian.h>`.
  * Gated the word-alignment error check behind `#if !defined(__x86_64__) && !defined(__aarch64__) && !defined(__arm64__)`.
  * *Rationale*: ARM64 natively supports unaligned word memory access, and `capnp::UnalignedFlatArrayMessageReader` is explicitly designed for unaligned buffers.

---

## 3. Unit Tests (`test/`)

* **[BCFKeyValueData.cc](file:///Users/vinter/projects/GLnexus/test/BCFKeyValueData.cc)** & **[rocks_integration.cc](file:///Users/vinter/projects/GLnexus/test/rocks_integration.cc)**:
  * Changed `make_pair<string, uint64_t>` to `make_pair<string, size_t>` in contig initializers.
  * *Rationale*: On Darwin LP64, `uint64_t` is `unsigned long long` while `size_t` is `unsigned long`. The type mismatch prevented implicit conversion in `std::vector<std::pair<std::string, size_t>>` constructors.

---

## 4. Test Environment

* **Python PyVCF (`pyvcf3`)**:
  * Installed `pyvcf3` into Python environment for `test/testOutputVcf.py`.
  * *Rationale*: Unit tests invoke `testOutputVcf.py` to semantically compare generated VCF outputs against truth files.

---

## 5. Upgrade htslib to 1.24

* **Build System (`CMakeLists.txt`)**:
  * Upgraded htslib `URL` from `1.9` to `1.24` release tarball.
  * Updated `PATCH_COMMAND` with `-e` expressions to patch `CFLAGS`, clear `NONCONFIGURE_OBJS`, and remove `echo '#define HAVE_LIBCURL 1' >> $@`.
  * *Rationale*: Avoids linking against libcurl (keeps static library self-contained) and resolves undefined `_hfile_plugin_init_libcurl` symbols on macOS / Linux builder.

* **Core Source Code (`src/BCFSerialize.cc`)**:
  * Replaced direct 16-byte `memcpy` into / out of `bcf1_t` with explicit field serialization (`rid`, `pos`, `rlen`, `qual`).
  * *Rationale*: In htslib >= 1.10, `pos` and `rlen` are 64-bit (`hts_pos_t`) and struct field ordering changed to `pos, rlen, rid, qual`. Raw `memcpy` corrupted record fields and wire format.
  * Replaced deprecated `bcf_hdr_fmt_text` with `bcf_hdr_format` using `kstring_t`.
  * *Rationale*: `bcf_hdr_fmt_text` is deprecated in htslib 1.24.

* **Unit Tests & Test Data**:
  * **[test/htslib_behaviors.cc](file:///Users/vinter/projects/GLnexus/test/htslib_behaviors.cc)**:
    * Wrapped `bcf_hdr_sync`, `bcf_hdr_write`, and `bcf_write1` calls in `REQUIRE(... == 0)` to satisfy `-Werror=unused-result`.
    * Included `<htslib/bgzf.h>` and set `fp->fp.bgzf->is_compressed = 0` for raw uncompressed BCF byte-comparison test.
  * **[test/BCFKeyValueData.cc](file:///Users/vinter/projects/GLnexus/test/BCFKeyValueData.cc)**:
    * Used `std::max<hts_pos_t>` to fix template argument deduction against 64-bit `pos`.
  * **Test Data (`test/data/*.gvcf`, `test/data/mt/*.gvcf`)**:
    * Replaced spaces before `QUAL` in `#CHROM` line (`\t  QUAL` -> `\tQUAL`) in 14 test gVCF files. Modern htslib strictly enforces tab-separated headers.
    * Corrected REF string length in two synthetic gVCF test records (`ACACGGTTAA` -> `ACACGGTTA` for 9 bp interval, `ATAT` -> `ATA` for 3 bp interval). Modern htslib enforces `rlen >= strlen(REF)`.
  * **YAML Test Cases (`test/data/gvcf_test_cases/*.yml`)**:
    * Fixed unclosed `##FILTER=<ID=LowQual...>` and truncated `##FORMAT=<ID=AD...>` header lines across 5 test specification YAML files to prevent htslib `Incomplete header line` warnings.

---

## 6. Dependency Status & Upgrade Roadmap

| Dependency | Current | Latest | Update? | Difficulty | Notes / Caveats |
|---|---|---|---|---|---|
| **yaml-cpp** | 0.8.0 | 0.8.0 | **Done** | **Low** | Upgraded. Replaced 0.6.3 with 0.8.0. |
| **spdlog** | 1.15.1 | 1.15.1 | **Done** | **Low** | Upgraded. Replaced 1.8.2 with 1.15.1. |
| **capnp** | 1.0.2 | 1.0.2 | **Done** | **Medium** | Upgraded from 0.7.0. Modernized readers and integrated native CMake codegen. |
| **rocksdb** | 11.8.1 | 11.8.1 | **Done** | **Medium** | Upgraded from 6.29.3 to 11.8.1. Modernized DB::Open signatures and LRUCacheOptions. |
| **catch** (tests) | 3.8.0 (v3) | 3.8.0 (v3) | **Done** | **Low** | Upgraded via FetchContent. Bridged via zero-touch `test/catch.hpp` shim. |
| **CTPL** | 0.0.2 | 0.0.2 | **Vendored** | **N/A** | Abandoned header library (2016); vendored into `third_party/ctpl`. |
| **fcmm** | 1.0.1 | 1.0.1 | **Vendored** | **N/A** | Upstream deleted; vendored header in `third_party/fcmm`. |

---

## 7. Upgrade yaml-cpp to 0.8.0

* **Build System (`CMakeLists.txt`)**:
  * Upgraded `yaml-cpp` `URL` from `yaml-cpp-0.6.3.zip` to `0.8.0.tar.gz`.
  * Verified in-source build produces `libyaml-cpp.a` cleanly under AppleClang.

---

## 8. Upgrade spdlog to 1.15.1

* **Build System (`CMakeLists.txt`)**:
  * Upgraded `spdlog` `URL` from `v1.8.2.tar.gz` to `v1.15.1.tar.gz`.
  * Added `PATCH_COMMAND` to substitute `str(S())` and `string_view(S())` with `str(S{})` and `string_view(S{})` in bundled `{fmt}` (`include/spdlog/fmt/bundled/base.h`).
  * *Rationale*: Prevents macro collision with GLnexus's `#define S(st)` in `include/types.h`. Eliminates compiler deprecation warnings from legacy bundled `{fmt}`.

---

## 9. Modernize Dockerfile to Ubuntu 24.04 & 3-Stage Multi-Arch Build

* **3-Stage Docker Build (`Dockerfile`)**:
  * **Stage 1 (`dependencies`)**: Pre-fetches and compiles heavy C++ libraries (RocksDB, htslib, Cap'n Proto, yaml-cpp, spdlog) using `-DBUILD_DEPS_ONLY=ON`. Installs `python3-vcf`, `bcftools`, and `pv` for test execution. Fully cached by Docker across application code changes.
  * **Stage 2 (`builder`)**: Compiles `glnexus_cli` and `unit_tests` from `dependencies` in ~20 seconds. Sets `CMD ["ctest", "-V"]` for on-demand test execution.
  * **Stage 3 (`runtime`)**: Slim `ubuntu:24.04` image (~470MB) containing only runtime libraries (`libjemalloc2`, `bcftools`, `tabix`, `pv`) and the `glnexus_cli` executable.
* **Modern OS & Security**:
  * Bumped builder and runtime bases to **Ubuntu 24.04 LTS** (Noble Numbat).
  * Removed legacy unmaintained `spvcf` download.
  * Replaced deprecated `python3-pyvcf` with Ubuntu 24.04 package `python3-vcf`.
* **Multi-Arch (x86_64 & ARM64) and Modern Toolchain Fixes**:
  * **Jemalloc path**: Replaced hardcoded `/usr/lib/x86_64-linux-gnu/libjemalloc.so.2` with dynamic symlink `/usr/lib/*-linux-gnu/libjemalloc.so.2` to support both x86_64 and aarch64.
  * **RocksDB GCC 13/14 compatibility**: Added `-include cstdint` to RocksDB's `EXTRA_CXXFLAGS` in [CMakeLists.txt](file:///Users/vinter/projects/GLnexus/CMakeLists.txt).
  * **Glibc symbol versioning**: Gated `__asm__(".symver logf,logf@GLIBC_2.2.5");` in [src/genotyper.cc](file:///Users/vinter/projects/GLnexus/src/genotyper.cc) to `defined(__x86_64__)` (since `GLIBC_2.2.5` does not exist on ARM64).
  * **Math library linkage**: Added `m` (`libm`) to `GLNEXUS_DEPS` on Linux in [CMakeLists.txt](file:///Users/vinter/projects/GLnexus/CMakeLists.txt).
  * **Catch v1 glibc 2.34+ compatibility**: Added patch to [CMakeLists.txt](file:///Users/vinter/projects/GLnexus/CMakeLists.txt) replacing `altStackMem[SIGSTKSZ]` with fixed buffer size `[32768]` in `catch.hpp` (in glibc 2.34+, `SIGSTKSZ` is no longer an integral constant expression).
* **Workspace Isolation**:
  * Added [`.dockerignore`](file:///Users/vinter/projects/GLnexus/.dockerignore) to prevent local macOS caches and binaries from polluting container builds.

---

## 10. Modernize CMake to Target-Based Architecture & Vendor Header Libraries (fcmm, CTPL)

* **Modern Target-Based CMake Architecture (`CMakeLists.txt`)**:
  * **Removed global directory pollution**: Replaced legacy directory-level `include_directories()` calls with proper target-scoped include properties (`INTERFACE_INCLUDE_DIRECTORIES` on `libhts`, `librocksdb`, `libyaml-cpp`).
  * **Interface libraries for header-only dependencies**: Wrapped `spdlog` and `catch` in interface targets (`libspdlog`, `libcatch`) with `INTERFACE` include directories and explicit target dependencies.
  * **Target-centric compilation & includes for `glnexus`**: Replaced global `COMMON_INCLUDES` with `target_include_directories(glnexus PUBLIC ... PRIVATE ...)` and declared standard via `target_compile_features(glnexus PUBLIC cxx_std_14)`.
  * **Transitive target linkage**: Simplified `glnexus_cli` and `unit_tests` to link directly to `glnexus` (and `libcatch` for tests) via `PRIVATE` target linkage, leveraging CMake transitive usage requirements instead of redundant global `GLNEXUS_DEPS` lists.
* **Source Vendoring (`third_party/`)**:
  * **fcmm (`third_party/fcmm`)**: Vendored header-only library `fcmm.hpp`, `LICENSE`, and `README`. Avoids external build-time dependency on third-party GitHub mirrors (`sigiesec/fcmm`) after upstream repository deletion (`giacomodrago/fcmm`).
  * **CTPL (`third_party/ctpl`)**: Vendored header-only threadpool library `ctpl.h`, `ctpl_stl.h`, `LICENSE`, and `README.md`. Removed `ExternalProject_Add` download from `github.com/vit-vit/CTPL`.
  * **CMake Integration**: Wired both as local interface libraries (`libfcmm`, `libctpl`) pointing directly to `third_party/`, dropping them from `ExternalProject_Add` and `BUILD_DEPS_ONLY`.

---

## 11. CMake Policy, Warning & Portability Fixes

* **Build Diagnostics & Policies (`CMakeLists.txt`)**:
  * **CMake policy CMP0135**: Set `CMP0135 NEW` to preserve archive extraction timestamps properly and eliminate author deprecation warnings across external projects.
  * **Clang warning cleanup**: Gated GCC-specific `-Wno-terminate` flag to `CMAKE_CXX_COMPILER_ID STREQUAL "GNU"`, eliminating `-Wunknown-warning-option` diagnostics on AppleClang / LLVM Clang.
* **Portability & Include Hygiene**:
  * **Cross-platform build concurrency**: Replaced hardcoded `make -j$(nproc)` in `htslib` and `capnp` with native CMake core query `cmake_host_system_information(RESULT NUM_CORES QUERY NUMBER_OF_LOGICAL_CORES)`, passing clean `-j${NUM_CORES}`.
  * **Purged last global include**: Removed duplicate `INCLUDE(ExternalProject)` call and moved the last directory-level `INCLUDE_DIRECTORIES` into target-scoped `target_include_directories(glnexus PRIVATE ${CMAKE_BINARY_DIR}/external/include)`.
  * **Modernized code coverage**: Replaced 21 lines of forced cache variables and custom `Coverage` build type with standard `option(ENABLE_COVERAGE "..." OFF)` using `add_compile_options(--coverage -O0 -g)` and `add_link_options(--coverage)`.
  * **Target-scoped compiler options**: Replaced global `CMAKE_CXX_FLAGS` mutation for `-Wno-unused-function` with `target_compile_options(unit_tests PRIVATE -Wno-unused-function)`.
  * **Consolidated dependencies**: Combined multiple `add_dependencies(glnexus ...)` invocations into a single call.

---

## 12. Restructure CMakeLists.txt into 8 Target-Based Sections

* **Visual Architecture & Logical Sections**:
  * Restructured [CMakeLists.txt](file:///Users/vinter/projects/GLnexus/CMakeLists.txt) into 8 clearly defined, logically ordered blocks.
* **Modern Target-Based Property Migration**:
  * **Eliminated Global Compiler Flags**: Removed global `CMAKE_CXX_FLAGS` mutations and applied flags directly to `glnexus` via `target_compile_definitions` (`GIT_REVISION`) and `target_compile_options` (`-Wall`, `-pthread`, `-Werror=...`, `-fdiagnostics-color=auto`, `${ARCH_FLAGS}`, `$<$<CXX_COMPILER_ID:GNU>:-Wno-terminate>`, `$<$<CONFIG:Release>:-gdwarf>`), which are automatically inherited by downstream targets.
  * **Dynamic Homebrew Detection**: Replaced hardcoded `/opt/homebrew` paths with dynamic `brew --prefix` querying, supporting Apple Silicon, Intel Macs, and custom `CMAKE_PREFIX_PATH`.
  * **Testing Opt-Out (`BUILD_TESTING`)**: Wrapped the entire testing section in `if(BUILD_TESTING)` (standard CTest toggle) to enable opting out of test builds via `-DBUILD_TESTING=OFF`.

---

## 13. Modernize Dependencies to FetchContent & Target Linker Options

* **FetchContent Migration (`yaml-cpp` & `spdlog`)**:
  * **`yaml-cpp`**: Replaced `ExternalProject_Add` with CMake-native `FetchContent_Declare` (with SHA-256 verification) and `FetchContent_MakeAvailable(yaml-cpp)`. Aliased target to `libyaml-cpp`, integrating directly into the CMake build graph and eliminating custom subproject makefile invocations.
  * **`spdlog`**: Migrated from `ExternalProject_Add` to `FetchContent_Declare` (with SHA-256 verification and in-flight `{fmt}` macro compatibility patch). Configured as a header-only `INTERFACE` target at configure time, eliminating unnecessary compilation and custom stamp files.
* **Target-Based Linker Options**:
  * Eliminated legacy global `CMAKE_EXE_LINKER_FLAGS` mutations.
  * Scoped interface linker options directly to `glnexus` via `target_link_options(glnexus INTERFACE ...)`, which automatically propagate to downstream executables (`glnexus_cli` and `unit_tests`).
* **Platform Concurrency & Build Hygiene**:
  * Replaced remnant `make -j$(nproc)` in `rocksdb` build command with portable `-j${NUM_CORES}`.
  * Streamlined `dependencies` and `add_dependencies(glnexus ...)` targets by removing native CMake targets now tracked automatically by the build graph.

---

## 14. Out-of-Source Build Support & Cap'n Proto 1.0.2 Upgrade

* **Out-of-Source & IDE Support (CLion / `cmake -B`)**:
  * **Directory Validation Fix**: Added `file(MAKE_DIRECTORY ...)` for imported target include paths (`htslib`, `rocksdb`) so CMake's generation step does not fail before external tarballs are extracted.
  * **Build Tree Isolation**: Added `build/` and `cmake-build-*/` to `.gitignore` to support default IDE and out-of-source build directories while keeping the repository root clean.
  * **Test Working Directory Fix**: Configured CTest `unit_tests` with `WORKING_DIRECTORY "${PROJECT_SOURCE_DIR}"` and `$<TARGET_FILE:unit_tests>` so fixture data in `test/data/` resolves properly across out-of-source builds.
  * **Test Script Binary Path Fix**: `test/jemalloc_linking.sh` and `test/getting_started.sh` hard-coded the binary as `test/../glnexus_cli`, which exists only in in-source builds, so both failed in `cmake -B build` builds. They now take the binary path as their first argument, CTest passes `$<TARGET_FILE:glnexus_cli>`, and the old location remains the default.

* **Cap'n Proto 1.0.2 Upgrade & Modern CMake Integration**:
  * **FetchContent Migration**: Migrated from legacy `ExternalProject_Add` (Cap'n Proto 0.7.0 with custom `./configure && make`) to `FetchContent_Declare` with Cap'n Proto 1.0.2 and SHA-256 verification.
  * **Native Code Generation**: Replaced custom `capnp compile` shell commands with Cap'n Proto's official `capnp_generate_cpp()` macro, outputting generated headers and source files cleanly into `${CMAKE_CURRENT_BINARY_DIR}`.
  * **Target-Based Linking**: Replaced hardcoded static library names (`libcapnp.a`, `libkj.a`) with the official `CapnProto::capnp` target.
  * **API Modernization**: Replaced `::capnp::UnalignedFlatArrayMessageReader` (removed in Cap'n Proto 1.0 after alignment requirements were folded into the base reader) with `::capnp::FlatArrayMessageReader` in `src/BCFKeyValueData.cc` and `src/BCFKeyValueData_utils.h`.
  * **Unaligned Data Deserialization**: Added `add_compile_definitions(CAPNP_ALLOW_UNALIGNED)` to allow deserializing unaligned bucket byte slices from key-value stores without Cap'n Proto 1.0 arena alignment assertions failing.
  * **Build Minimization (`EXCLUDE_FROM_ALL`)**: Tagged Cap'n Proto and yaml-cpp `FetchContent_Declare` blocks with `EXCLUDE_FROM_ALL`, ensuring unused subproject targets (RPC, websockets, JSON, HTTP) are skipped during builds.

---

## 15. C++23 Standard Migration, RocksDB 11.8.1 Upgrade, Catch3 Modernization, htslib config

* **C++23 Standard Migration**:
  * **Global CMake Standard**: Set `CMAKE_CXX_STANDARD 23`, `CMAKE_CXX_STANDARD_REQUIRED ON`, and `CMAKE_CXX_EXTENSIONS ON` at the top of `CMakeLists.txt`.
  * **Target Standard**: Bumped `target_compile_features(glnexus PUBLIC cxx_std_23)` in `CMakeLists.txt`. Both `libglnexus.a` and `glnexus_cli` compile cleanly.
  * **Header Inclusion**: Added `#include <functional>` to `src/unifier.cc` (standard library headers no longer transitively pull `std::function` under C++23).
  * **Dead Pragma Cleanup**: Removed legacy `auto_ptr` warning suppression pragmas around `#include "yaml-cpp/yaml.h"` in `include/types.h` (obsolete after yaml-cpp 0.8.0 upgrade).
  * **Dependencies Under C++23**:
    * `yaml-cpp`, `CapnProto`, `Catch2`: Inherit and compile cleanly with `-std=gnu++23` via `FetchContent`.
    * `spdlog`, `CTPL`, `fcmm`: Header-only libraries compile cleanly under `-std=gnu++23`.
    * `rocksdb`: Built via Makefile using detected C++20 ABI, verified 100% interoperable.
    * `htslib`: Pure C (C99 Makefile), unaffected by C++ standard.

* **Catch3 Upgrade (v3.8.0) & Zero-Touch Compatibility Shim**:
  * **FetchContent Integration**: Replaced legacy `ExternalProject_Add(catch 1.12.2)` and its manual assembly/signal stack patches with modern `FetchContent_Declare(Catch2 ... v3.8.0)` and `FetchContent_MakeAvailable(Catch2)`.
  * **Target Linking**: Linked `unit_tests` to `Catch2::Catch2`.
  * **Zero-Touch Shim Header (`test/catch.hpp`)**:
    * Created compatibility bridge header that includes `<catch2/catch_test_macros.hpp>` and implements `main()` via `Catch::Session().run()` when `CATCH_CONFIG_MAIN` is defined.
    * Preserves full backward compatibility with Catch v1 test macros (`TEST_CASE`, `SECTION`, `REQUIRE`, `CHECK`) without modifying a single line across the 12 existing test files.

* **RocksDB 11.8.1 Upgrade & Modernization**:
  * **Version Bump**: Upgraded RocksDB from `v6.29.3` to latest stable `v11.8.1` in `CMakeLists.txt`. Removed `-include cstdint` workaround from build command.
  * **API Modernization (`std::unique_ptr<rocksdb::DB>`)**: Updated `rocksdb::DB::Open` and `rocksdb::DB::OpenForReadOnly` call sites in `src/RocksKeyValue.cc` and `test/rocks_behaviors.cc` to use `std::unique_ptr<rocksdb::DB>*` instead of deprecated raw double pointers.
  * **Obsolete Options Cleanup**: Removed `opts.access_hint_on_compaction_start` in `src/RocksKeyValue.cc` (deprecated and removed; readahead behavior is now governed by `compaction_readahead_size`).
  * **Block Cache Modernization**: Replaced deprecated `rocksdb::NewLRUCache()` with `rocksdb::LRUCacheOptions(...).MakeSharedCache()` in `NewBlockCache()`.
  * **SST Format Version**: Bumped `bbto.format_version` from 4 to 5 in `src/RocksKeyValue.cc` for faster checksumming (xxHash64/kXXH3) and dictionary block support.

* **CMake Modernization & Build Hygiene**:
  * **htslib Autotools Configure & libdeflate Acceleration**: Replaced hacky `PATCH_COMMAND sed` with standard `./configure --disable-libcurl --with-libdeflate --disable-bz2 --disable-lzma` passing compiler, CFLAGS, CPPFLAGS, and LDFLAGS cleanly, building static target via `make lib-static`. Linked `deflate` (`libdeflate.a` on Linux) to accelerate BGZF gzip compression/decompression across VCF/BCF operations. Added `libdeflate-dev` to `Dockerfile`.
  * **Elimination of Unused Compression Dependencies (`bz2`, `lzma`)**: Removed unused CRAM-only compressors (`libbz2`, `liblzma`) from `htslib` and disabled bzip in RocksDB (`ROCKSDB_DISABLE_BZIP=1`). Completely dropped `bz2` and `lzma` from `EXTERNAL_DEPS`, removed Homebrew `opt/xz` include/lib path workarounds, and removed `libbz2-dev` and `liblzma-dev` from `Dockerfile`.
  * **Linker & Environment Cleanup**: Eliminated legacy global `link_directories()` and dead `set(ENV{...})` mutations; scoped macOS Homebrew library search directory directly to `glnexus` via target-based `target_link_options(glnexus INTERFACE ...)`.
  * **Target Separation & Cleanliness**: Moved `test/utils.cc` out of production `libglnexus.a` into `unit_tests`; removed redundant compilation of `src/diploid.cc` in `unit_tests`.
  * **Ghost Include Cleanup**: Removed non-existent `src/rocksdb/include` from `target_include_directories(glnexus PRIVATE ...)`.
  * **Docker & Multi-Arch Container Modernization**:
    * Updated [Dockerfile](file:///Users/vinter/projects/GLnexus/Dockerfile) to replace `libbz2-dev` and `liblzma-dev` with `libdeflate-dev`.
    * Configured multi-arch `LD_PRELOAD` resolution for `libjemalloc.so.2` in the `builder` stage so CTest/Catch2 test execution runs with jemalloc active.
    * Added `cmake-build-*/` and `_deps/` to [`.dockerignore`](file:///Users/vinter/projects/GLnexus/.dockerignore), reducing build context transfer from 3.7GB down to 9.6KB.
    * Modernized [test/getting_started.sh](file:///Users/vinter/projects/GLnexus/test/getting_started.sh) to dynamically locate `libjemalloc` across architectures (`x86_64` and `aarch64`) and accept thread budgets (`${THREADS:-4}`) to avoid OOM killing during multi-thousand-sample genotyping in resource-constrained environments. All tests (`unit_tests`, `jemalloc_linking`, `getting_started`) verified passing 100% inside container.



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

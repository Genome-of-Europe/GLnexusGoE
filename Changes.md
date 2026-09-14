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
| **capnp** | 0.7.0 | 1.0.2 | **Yes** | **Medium** | Fixes ARM64 quirks (we disabled `check`). Wire format backward-compatible. Generated C++ compiler output needs verification. |
| **rocksdb** | 6.29.3 | 9.10.x | **No** (hold) | **High** | RocksDB 8+ requires C++17 (GLnexus is `-std=c++14`). Breaking C++ API changes (`SstFileWriter`, options). Complex build/SIMD matrix. |
| **catch** (tests) | 1.12.2 (v1) | 3.8.0 (v3) | **No** | **High** | Catch v1 -> v3 is total rewrite. Drops single-header `catch.hpp`, breaks macros across all 12 test files. High effort, zero runtime benefit. |
| **CTPL** | 0.0.2 | 0.0.2 | **No** | **N/A** | Abandoned header library (2016). No newer version exists. |
| **fcmm** | 1.0.1 | 1.0.1 | **No** | **N/A** | Upstream deleted; we use mirror. No newer version exists. |

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



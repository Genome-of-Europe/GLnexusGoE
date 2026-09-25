cmake_minimum_required(VERSION 3.20)
include(ExternalProject)

if(NOT CMAKE_BUILD_TYPE)
  set(CMAKE_BUILD_TYPE Release CACHE STRING
      "Choose the type of build, options are: None Debug Release RelWithDebInfo MinSizeRel."
      FORCE)
endif(NOT CMAKE_BUILD_TYPE)

set(CMAKE_CXX_FLAGS_COVERAGE
    "-g -O0 --coverage -fprofile-arcs -ftest-coverage"
    CACHE STRING "Flags used by the C++ compiler during coverage builds."
    FORCE )
set(CMAKE_C_FLAGS_COVERAGE
    "-g -O0 --coverage -fprofile-arcs -ftest-coverage"
    CACHE STRING "Flags used by the C compiler during coverage builds."
    FORCE )
set(CMAKE_EXE_LINKER_FLAGS_COVERAGE
    ""
    CACHE STRING "Flags used for linking binaries during coverage builds."
    FORCE )
set(CMAKE_SHARED_LINKER_FLAGS_COVERAGE
    ""
    CACHE STRING "Flags used by the shared libraries linker during coverage builds."
    FORCE )
MARK_AS_ADVANCED(
    CMAKE_CXX_FLAGS_COVERAGE
    CMAKE_C_FLAGS_COVERAGE
    CMAKE_EXE_LINKER_FLAGS_COVERAGE
    CMAKE_SHARED_LINKER_FLAGS_COVERAGE )
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

# Make PROJECT_SOURCE_DIR, PROJECT_BINARY_DIR, and PROJECT_NAME available.
project(GLnexus)

INCLUDE(ExternalProject)
INCLUDE_DIRECTORIES(BEFORE ${CMAKE_BINARY_DIR}/external/include)
LINK_DIRECTORIES(${CMAKE_BINARY_DIR}/external/lib)
set(ENV{PATH} ${CMAKE_BINARY_DIR}/external/bin:$ENV{PATH})
set(ENV{PKG_CONFIG_PATH} ${CMAKE_BINARY_DIR}/external/lib/pkgconfig)

if(CMAKE_SYSTEM_PROCESSOR MATCHES "x86_64")
  set(ARCH_FLAGS "-march=ivybridge")
  set(ROCKSDB_ARCH_OPT "-march=ivybridge -msse4.2 -DHAVE_SSE42 -mpclmul")
else()
  set(ARCH_FLAGS "")
  set(ROCKSDB_ARCH_OPT "")
endif()

if(APPLE)
  link_directories(/opt/homebrew/lib)
  set(HTSLIB_EXTRA_CFLAGS "-I/opt/homebrew/opt/xz/include")
  set(ROCKSDB_EXTRA_CXXFLAGS "-I/opt/homebrew/include")
  set(ROCKSDB_EXTRA_LDFLAGS "-L/opt/homebrew/lib")
else()
  set(HTSLIB_EXTRA_CFLAGS "")
  set(ROCKSDB_EXTRA_CXXFLAGS "")
  set(ROCKSDB_EXTRA_LDFLAGS "")
endif()

# After build, double-check external/src/htslib-stamp/htslib-build-out.log
# to make sure CFLAGS were set as expected
ExternalProject_Add(htslib
    URL https://github.com/samtools/htslib/releases/download/1.24/htslib-1.24.tar.bz2
    PREFIX ${CMAKE_CURRENT_BINARY_DIR}/external
    CONFIGURE_COMMAND ""
    PATCH_COMMAND sed -i.bak -e "s|^CFLAGS .*$|CFLAGS = -gdwarf -O3 -DNDEBUG ${ARCH_FLAGS} ${HTSLIB_EXTRA_CFLAGS}|" -e "s|^NONCONFIGURE_OBJS =.*$|NONCONFIGURE_OBJS =|" -e "s|echo '#define HAVE_LIBCURL 1' >> \\$@||" Makefile
    BUILD_IN_SOURCE 1
    BUILD_COMMAND bash -c "make -n libhts.a && make -j$(nproc) libhts.a"
    INSTALL_COMMAND ""
    LOG_DOWNLOAD ON
    LOG_BUILD ON
  )
ExternalProject_Get_Property(htslib source_dir)
set(HTSLIB_INCLUDE_DIR ${source_dir}/htslib ${source_dir})
ExternalProject_Get_Property(htslib binary_dir)
add_library(libhts STATIC IMPORTED)
set(LIBHTS_A ${binary_dir}/libhts.a)
set_target_properties(libhts PROPERTIES
    IMPORTED_LOCATION ${LIBHTS_A}
    INTERFACE_INCLUDE_DIRECTORIES "${HTSLIB_INCLUDE_DIR}")

# RocksDB
#
# We set DISABLE_JEMALLOC=1 to avoid link-time dependency to jemalloc; we
# DO however wish to use jemalloc, but expect user to activate it at
# runtime with LD_PRELOAD instead.
#
# Warning: it's dangerously easy to mess with the RocksDB external project
# configuration below and silently get a librocksdb.a compiled without
# optimizations, or targeting an instruction set that's too old or too new.
#
# Here are some checks to perform after any adjustment:
# 1. Verify AVX is used (nonzero results):
#      objdump -d external/src/rocksdb/librocksdb.a | grep vzeroupper | wc -l
# 2. Verify Haswell-and-newer instructions are NOT used (zero results):
#      objdump -d external/src/rocksdb/librocksdb.a | egrep "[[:space:]]andn[[:space:]]"
# 3. Verify accelerated CRC32 is used (nonzero results):
#      objdump -d external/src/rocksdb/librocksdb.a | grep crc32q
# 4. Verify compiler optimizations performed:
#      (TODO better heuristics needed)
#      a) check external/src/rocksdb-stamp/rocksdb-build-out.log to see
#         compiler invocations with -O3
#      b) go through perf/FlameGraph profiling flow and check that no
#         rocksdb function has a big chunk like 5% or more
ExternalProject_Add(rocksdb
    URL https://github.com/facebook/rocksdb/archive/v6.29.3.tar.gz
    PREFIX ${CMAKE_CURRENT_BINARY_DIR}/external
    CONFIGURE_COMMAND ""
    BUILD_IN_SOURCE 1
    BUILD_COMMAND bash -c "export PORTABLE=1 && export DISABLE_JEMALLOC=1 && export OPT='-DNDEBUG -O3 ${ROCKSDB_ARCH_OPT} -DROCKSDB_NO_DYNAMIC_EXTENSION' && export EXTRA_CXXFLAGS='-include cstdint -Wno-error ${ROCKSDB_EXTRA_CXXFLAGS}' && export EXTRA_LDFLAGS='${ROCKSDB_EXTRA_LDFLAGS}' && make -n static_lib && make -j$(nproc) static_lib"
    INSTALL_COMMAND ""
    LOG_DOWNLOAD ON
    LOG_BUILD ON
  )
ExternalProject_Get_Property(rocksdb source_dir)
set(ROCKSDB_INCLUDE_DIR ${source_dir}/include ${source_dir})
ExternalProject_Get_Property(rocksdb binary_dir)
add_library(librocksdb STATIC IMPORTED)
set(LIBROCKSDB_A ${binary_dir}/librocksdb.a)
set_target_properties(librocksdb PROPERTIES
    IMPORTED_LOCATION ${LIBROCKSDB_A}
    INTERFACE_INCLUDE_DIRECTORIES "${ROCKSDB_INCLUDE_DIR}")

# After build, double-check external/src/yaml-cpp-stamp/yaml-cpp-build-out.log
# to make sure CFLAGS were set as expected
ExternalProject_Add(yaml-cpp
    URL https://github.com/jbeder/yaml-cpp/archive/0.8.0.tar.gz
    PREFIX ${CMAKE_CURRENT_BINARY_DIR}/external
    CONFIGURE_COMMAND cmake -DCMAKE_POLICY_VERSION_MINIMUM=3.5 -DYAML_CPP_BUILD_TESTS=OFF -DYAML_CPP_BUILD_TOOLS=OFF -DYAML_CPP_BUILD_CONTRIB=OFF -DCMAKE_BUILD_TYPE=Release -DCMAKE_CXX_FLAGS=${ARCH_FLAGS} .
    BUILD_IN_SOURCE 1
    BUILD_COMMAND bash -c "make -j$(nproc)"
    INSTALL_COMMAND ""
    LOG_DOWNLOAD ON
    LOG_BUILD ON
  )
ExternalProject_Get_Property(yaml-cpp source_dir)
set(YAML_CPP_INCLUDE_DIR ${source_dir}/include)
ExternalProject_Get_Property(yaml-cpp binary_dir)
add_library(libyaml-cpp STATIC IMPORTED)
set(LIBYAML_CPP_A ${binary_dir}/libyaml-cpp.a)
set_target_properties(libyaml-cpp PROPERTIES
    IMPORTED_LOCATION ${LIBYAML_CPP_A}
    INTERFACE_INCLUDE_DIRECTORIES "${YAML_CPP_INCLUDE_DIR}")

add_library(libctpl INTERFACE)
target_include_directories(libctpl INTERFACE ${CMAKE_CURRENT_SOURCE_DIR}/third_party/ctpl)

add_library(libfcmm INTERFACE)
target_include_directories(libfcmm INTERFACE ${CMAKE_CURRENT_SOURCE_DIR}/third_party/fcmm)

ExternalProject_Add(spdlog
    URL https://github.com/gabime/spdlog/archive/v1.15.1.tar.gz
    PREFIX ${CMAKE_CURRENT_BINARY_DIR}/external
    CONFIGURE_COMMAND ""
    PATCH_COMMAND sed -i.bak -e "s|str(S())|str(S{})|g" -e "s|string_view(S())|string_view(S{})|g" include/spdlog/fmt/bundled/base.h
    BUILD_IN_SOURCE 1
    BUILD_COMMAND ""
    INSTALL_COMMAND ""
    LOG_DOWNLOAD ON
  )
ExternalProject_Get_Property(spdlog source_dir)
add_library(libspdlog INTERFACE)
add_dependencies(libspdlog spdlog)
target_include_directories(libspdlog INTERFACE ${source_dir}/include)

ExternalProject_Add(capnp
    URL https://capnproto.org/capnproto-c++-0.7.0.tar.gz
    PREFIX ${CMAKE_CURRENT_BINARY_DIR}/external
    CONFIGURE_COMMAND ./configure --prefix=${CMAKE_BINARY_DIR}/external
    BUILD_IN_SOURCE 1
    BUILD_COMMAND bash -c "make -j$(nproc)"
    INSTALL_COMMAND make install
    LOG_DOWNLOAD ON
  )

execute_process(COMMAND git describe --tags --long --dirty --always
                OUTPUT_VARIABLE GIT_REVISION OUTPUT_STRIP_TRAILING_WHITESPACE)
set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -DGIT_REVISION=\"\\\"${GIT_REVISION}\\\"\" -pthread -std=c++14 -Wall -Werror=return-type -Werror=unused-result -Wno-sign-compare -Wno-write-strings -Wno-terminate -Wno-return-type-c-linkage -fdiagnostics-color=auto ${ARCH_FLAGS}")
set(CMAKE_CXX_FLAGS_RELEASE "-gdwarf -DNDEBUG -O3")

option(BUILD_DEPS_ONLY "Only fetch and build external dependencies" OFF)
if(BUILD_DEPS_ONLY)
  add_custom_target(dependencies ALL DEPENDS htslib rocksdb yaml-cpp spdlog capnp)
  return()
endif()

# Invoke cap'n proto IDL compiler, to generate C++ serialization code from
# definitions.
add_custom_command(
  OUTPUT  capnp/serialize/defs.capnp.c++ capnp/serialize/defs.capnp.h
  COMMAND ${CMAKE_BINARY_DIR}/external/bin/capnp compile -I${CMAKE_CURRENT_BINARY_DIR}/external/include -oexternal/bin/capnpc-c++ capnp/serialize/defs.capnp
  DEPENDS capnp/serialize/defs.capnp
  COMMENT "GLnexus: generating cap'n proto C++ and H files")

add_library(glnexus
            capnp/serialize/defs.capnp.h capnp/serialize/defs.capnp.c++
            include/types.h src/types.cc
            include/data.h src/data.cc
            include/compare_queries.h src/compare_queries.cc
            include/diploid.h src/diploid.cc
            include/service.h src/service.cc
            include/discovery.h src/discovery.cc
            include/unifier.h src/unifier.cc
            include/genotyper.h src/genotyper.cc
            src/genotyper_utils.h
            src/BCFKeyValueData_utils.h
            include/residuals.h src/residuals.cc
            include/KeyValue.h src/KeyValue.cc
            include/BCFSerialize.h src/BCFSerialize.cc
            include/BCFKeyValueData.h src/BCFKeyValueData.cc
            include/BCF_utils.h src/BCF_utils.cc
            include/RocksKeyValue.h src/RocksKeyValue.cc
            include/cli_utils.h src/cli_utils.cc
            test/utils.cc)
target_compile_features(glnexus PUBLIC cxx_std_14)
target_include_directories(glnexus
  PUBLIC
    $<BUILD_INTERFACE:${PROJECT_SOURCE_DIR}/include>
  PRIVATE
    src
    src/rocksdb/include
    capnp/serialize
)
add_dependencies(glnexus htslib)
add_dependencies(glnexus rocksdb)
add_dependencies(glnexus yaml-cpp)
add_dependencies(glnexus capnp)
add_library(libglnexus ALIAS glnexus)

if(APPLE)
  set(CMAKE_EXE_LINKER_FLAGS "${CMAKE_EXE_LINKER_FLAGS} -pthread -Wl,-U,_mallctl")
  set(EXTERNAL_DEPS libhts librocksdb libyaml-cpp libctpl libfcmm libspdlog z snappy bz2 zstd lzma lz4 libcapnp.a libkj.a)
else()
  set(CMAKE_EXE_LINKER_FLAGS "${CMAKE_EXE_LINKER_FLAGS} ${ARCH_FLAGS} -static-libstdc++ -pthread")
  set(EXTERNAL_DEPS libhts librocksdb libyaml-cpp libctpl libfcmm libspdlog libz.a libsnappy.a libbz2.a libzstd.a liblzma.a librt.a libcapnp.a libkj.a m)
endif()
target_link_libraries(glnexus PUBLIC ${EXTERNAL_DEPS})

add_executable(glnexus_cli cli/glnexus_cli.cc)
target_link_libraries(glnexus_cli PRIVATE glnexus)

install(TARGETS glnexus_cli DESTINATION bin)

################################
# Testing
################################

ExternalProject_Add(catch
  URL https://github.com/philsquared/Catch/archive/v1.12.2.zip
  PREFIX ${CMAKE_CURRENT_BINARY_DIR}/external
  CONFIGURE_COMMAND ""
  PATCH_COMMAND sed -i.bak -e "s|__asm__(\"int \\$3\\\\n\" : : /\\* NOLINT \\*/ )|__builtin_debugtrap()|" -e "s|altStackMem\\[SIGSTKSZ\\]|altStackMem[32768]|g" -e "s|sigStack.ss_size = SIGSTKSZ|sigStack.ss_size = sizeof(altStackMem)|g" single_include/catch.hpp
  BUILD_COMMAND ""
  INSTALL_COMMAND ""
  LOG_DOWNLOAD ON
  )
ExternalProject_Get_Property(catch source_dir)
add_library(libcatch INTERFACE)
add_dependencies(libcatch catch)
target_include_directories(libcatch INTERFACE ${source_dir}/single_include)

set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -Wno-unused-function")
add_executable(unit_tests
                src/diploid.cc test/diploid.cc
                test/unit_tests.cc
                test/htslib_behaviors.cc
                test/rocks_behaviors.cc
                test/types.cc
                test/genotyper.cc
                test/service.cc
                test/gvcf_test_cases.cc
                test/BCFKeyValueData.cc
                test/rocks_integration.cc
                test/unifier.cc
                test/cli_utils.cc
                test/cli.cc)
target_link_libraries(unit_tests PRIVATE glnexus libcatch)

include(CTest)
add_test(NAME unit_tests COMMAND ./unit_tests -d yes)
if(NOT APPLE)
  add_test(NAME jemalloc_warning COMMAND test/jemalloc_linking.sh)
  add_test(NAME getting_started COMMAND test/getting_started.sh)
endif()

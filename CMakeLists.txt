cmake_minimum_required(VERSION 3.20)

# ==============================================================================
# 1. Project & Build Options
# ==============================================================================
if(POLICY CMP0135)
  cmake_policy(SET CMP0135 NEW)
endif()

if(NOT CMAKE_BUILD_TYPE)
  set(CMAKE_BUILD_TYPE Release CACHE STRING
      "Choose the type of build, options are: None Debug Release RelWithDebInfo MinSizeRel."
      FORCE)
endif()

option(ENABLE_COVERAGE "Enable code coverage instrumentation" OFF)
if(ENABLE_COVERAGE)
  add_compile_options(--coverage -O0 -g)
  add_link_options(--coverage)
endif()

set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

project(GLnexus)

# ==============================================================================
# 2. Platform, Hardware & Architecture Configuration
# ==============================================================================

# Logical core query used solely for -j flag in ExternalProject_Add build commands
cmake_host_system_information(RESULT NUM_CORES QUERY NUMBER_OF_LOGICAL_CORES)
if(NOT NUM_CORES OR NUM_CORES LESS 1)
  set(NUM_CORES 4)
endif()

link_directories(${CMAKE_BINARY_DIR}/external/lib)
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
  find_program(BREW_BIN brew)
  if(BREW_BIN)
    execute_process(COMMAND ${BREW_BIN} --prefix OUTPUT_VARIABLE BREW_PREFIX OUTPUT_STRIP_TRAILING_WHITESPACE)
  elseif(EXISTS "/opt/homebrew")
    set(BREW_PREFIX "/opt/homebrew")
  elseif(EXISTS "/usr/local")
    set(BREW_PREFIX "/usr/local")
  endif()

  if(BREW_PREFIX)
    list(APPEND CMAKE_PREFIX_PATH "${BREW_PREFIX}")
    link_directories("${BREW_PREFIX}/lib")
    set(HTSLIB_EXTRA_CFLAGS "-I${BREW_PREFIX}/opt/xz/include -I${BREW_PREFIX}/include")
    set(ROCKSDB_EXTRA_CXXFLAGS "-I${BREW_PREFIX}/include")
    set(ROCKSDB_EXTRA_LDFLAGS "-L${BREW_PREFIX}/lib")
  endif()
else()
  set(HTSLIB_EXTRA_CFLAGS "")
  set(ROCKSDB_EXTRA_CXXFLAGS "")
  set(ROCKSDB_EXTRA_LDFLAGS "")
endif()

execute_process(COMMAND git describe --tags --long --dirty --always
                OUTPUT_VARIABLE GIT_REVISION OUTPUT_STRIP_TRAILING_WHITESPACE)

# ==============================================================================
# 3. Vendored Header Libraries (third_party/)
# ==============================================================================
add_library(libctpl INTERFACE)
target_include_directories(libctpl INTERFACE ${CMAKE_CURRENT_SOURCE_DIR}/third_party/ctpl)

add_library(libfcmm INTERFACE)
target_include_directories(libfcmm INTERFACE ${CMAKE_CURRENT_SOURCE_DIR}/third_party/fcmm)

# ==============================================================================
# 4. External Dependencies (Downloaded & Built)
# ==============================================================================
include(ExternalProject)

# htslib
ExternalProject_Add(htslib
    URL https://github.com/samtools/htslib/releases/download/1.24/htslib-1.24.tar.bz2
    PREFIX ${CMAKE_CURRENT_BINARY_DIR}/external
    CONFIGURE_COMMAND ""
    PATCH_COMMAND sed -i.bak -e "s|^CFLAGS .*$|CFLAGS = -gdwarf -O3 -DNDEBUG ${ARCH_FLAGS} ${HTSLIB_EXTRA_CFLAGS}|" -e "s|^NONCONFIGURE_OBJS =.*$|NONCONFIGURE_OBJS =|" -e "s|echo '#define HAVE_LIBCURL 1' >> \\$@||" Makefile
    BUILD_IN_SOURCE 1
    BUILD_COMMAND bash -c "make -n libhts.a && make -j${NUM_CORES} libhts.a"
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
# Warning: DISABLE_JEMALLOC=1 avoids link-time jemalloc dependency (LD_PRELOAD at runtime).
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

# yaml-cpp
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

# spdlog
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

# capnproto
ExternalProject_Add(capnp
    URL https://capnproto.org/capnproto-c++-0.7.0.tar.gz
    PREFIX ${CMAKE_CURRENT_BINARY_DIR}/external
    CONFIGURE_COMMAND ./configure --prefix=${CMAKE_BINARY_DIR}/external
    BUILD_IN_SOURCE 1
    BUILD_COMMAND bash -c "make -j${NUM_CORES}"
    INSTALL_COMMAND make install
    LOG_DOWNLOAD ON
  )

option(BUILD_DEPS_ONLY "Only fetch and build external dependencies" OFF)
if(BUILD_DEPS_ONLY)
  add_custom_target(dependencies ALL DEPENDS htslib rocksdb yaml-cpp spdlog capnp)
  return()
endif()

# ==============================================================================
# 5. Code Generation (Cap'n Proto)
# ==============================================================================
add_custom_command(
  OUTPUT  capnp/serialize/defs.capnp.c++ capnp/serialize/defs.capnp.h
  COMMAND ${CMAKE_BINARY_DIR}/external/bin/capnp compile -I${CMAKE_CURRENT_BINARY_DIR}/external/include -oexternal/bin/capnpc-c++ capnp/serialize/defs.capnp
  DEPENDS capnp/serialize/defs.capnp
  COMMENT "GLnexus: generating cap'n proto C++ and H files")

# ==============================================================================
# 6. Core Library (glnexus)
# ==============================================================================
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
target_compile_definitions(glnexus PUBLIC
    GIT_REVISION=\"${GIT_REVISION}\"
)
target_compile_options(glnexus PUBLIC
    -pthread
    -Wall
    -Werror=return-type
    -Werror=unused-result
    -Wno-sign-compare
    -Wno-write-strings
    -Wno-return-type-c-linkage
    -fdiagnostics-color=auto
    ${ARCH_FLAGS}
    $<$<CXX_COMPILER_ID:GNU>:-Wno-terminate>
    $<$<CONFIG:Release>:-gdwarf>
)

target_include_directories(glnexus
  PUBLIC
    $<BUILD_INTERFACE:${PROJECT_SOURCE_DIR}/include>
  PRIVATE
    src
    src/rocksdb/include
    capnp/serialize
    ${CMAKE_BINARY_DIR}/external/include
)
add_dependencies(glnexus htslib rocksdb yaml-cpp capnp)
add_library(libglnexus ALIAS glnexus)

if(APPLE)
  set(CMAKE_EXE_LINKER_FLAGS "${CMAKE_EXE_LINKER_FLAGS} -pthread -Wl,-U,_mallctl")
  set(EXTERNAL_DEPS libhts librocksdb libyaml-cpp libctpl libfcmm libspdlog z snappy bz2 zstd lzma lz4 libcapnp.a libkj.a)
else()
  set(CMAKE_EXE_LINKER_FLAGS "${CMAKE_EXE_LINKER_FLAGS} ${ARCH_FLAGS} -static-libstdc++ -pthread")
  set(EXTERNAL_DEPS libhts librocksdb libyaml-cpp libctpl libfcmm libspdlog libz.a libsnappy.a libbz2.a libzstd.a liblzma.a librt.a libcapnp.a libkj.a m)
endif()
target_link_libraries(glnexus PUBLIC ${EXTERNAL_DEPS})

# ==============================================================================
# 7. CLI Executable (glnexus_cli)
# ==============================================================================
add_executable(glnexus_cli cli/glnexus_cli.cc)
target_link_libraries(glnexus_cli PRIVATE glnexus)

install(TARGETS glnexus_cli DESTINATION bin)

# ==============================================================================
# 8. Testing (unit_tests & CTest)
# ==============================================================================
include(CTest)

if(BUILD_TESTING)
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
  target_compile_options(unit_tests PRIVATE -Wno-unused-function)
  target_link_libraries(unit_tests PRIVATE glnexus libcatch)

  add_test(NAME unit_tests COMMAND ./unit_tests -d yes)
  if(NOT APPLE)
    add_test(NAME jemalloc_warning COMMAND test/jemalloc_linking.sh)
    add_test(NAME getting_started COMMAND test/getting_started.sh)
  endif()
endif()

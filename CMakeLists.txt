cmake_minimum_required(VERSION 3.20)

# ==============================================================================
# 1. Project & Build Options
# ==============================================================================
if(POLICY CMP0135)
  cmake_policy(SET CMP0135 NEW)
endif()
if(POLICY CMP0169)
  cmake_policy(SET CMP0169 OLD)
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
set(CMAKE_CXX_STANDARD 23)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS ON)

project(GLnexus)

# ==============================================================================
# 2. Platform, Hardware & Architecture Configuration
# ==============================================================================

# Logical core query used solely for -j flag in ExternalProject_Add build commands
cmake_host_system_information(RESULT NUM_CORES QUERY NUMBER_OF_LOGICAL_CORES)
if(NOT NUM_CORES OR NUM_CORES LESS 1)
  set(NUM_CORES 4)
endif()

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
    execute_process(COMMAND ${BREW_BIN} --prefix
                    OUTPUT_VARIABLE BREW_PREFIX
                    OUTPUT_STRIP_TRAILING_WHITESPACE)
  elseif(EXISTS "/opt/homebrew")
    set(BREW_PREFIX "/opt/homebrew")
  elseif(EXISTS "/usr/local")
    set(BREW_PREFIX "/usr/local")
  endif()

  if(BREW_PREFIX)
    list(APPEND CMAKE_PREFIX_PATH "${BREW_PREFIX}")
    set(HTSLIB_EXTRA_CFLAGS "-I${BREW_PREFIX}/include")
    set(HTSLIB_EXTRA_LDFLAGS "-L${BREW_PREFIX}/lib")
    set(ROCKSDB_EXTRA_CXXFLAGS "-I${BREW_PREFIX}/include")
    set(ROCKSDB_EXTRA_LDFLAGS "-L${BREW_PREFIX}/lib")
  endif()
else()
  set(HTSLIB_EXTRA_CFLAGS "")
  set(HTSLIB_EXTRA_LDFLAGS "")
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
include(FetchContent)

# htslib
ExternalProject_Add(htslib
    URL https://github.com/samtools/htslib/releases/download/1.24/htslib-1.24.tar.bz2
    PREFIX ${CMAKE_CURRENT_BINARY_DIR}/external
    BUILD_IN_SOURCE 1
    CONFIGURE_COMMAND ./configure
        --disable-libcurl
        --with-libdeflate
        --disable-bz2
        --disable-lzma
        CC=${CMAKE_C_COMPILER}
        CFLAGS=-gdwarf\ -O3\ -DNDEBUG\ ${ARCH_FLAGS}
        CPPFLAGS=${HTSLIB_EXTRA_CFLAGS}
        LDFLAGS=${HTSLIB_EXTRA_LDFLAGS}
    BUILD_COMMAND make -j${NUM_CORES} lib-static
    INSTALL_COMMAND ""
    LOG_DOWNLOAD ON
    LOG_BUILD ON
  )
ExternalProject_Get_Property(htslib source_dir)
set(HTSLIB_INCLUDE_DIR ${source_dir}/htslib ${source_dir})
file(MAKE_DIRECTORY ${HTSLIB_INCLUDE_DIR})
ExternalProject_Get_Property(htslib binary_dir)
add_library(libhts STATIC IMPORTED)
set(LIBHTS_A ${binary_dir}/libhts.a)
set_target_properties(libhts PROPERTIES
    IMPORTED_LOCATION ${LIBHTS_A}
    INTERFACE_INCLUDE_DIRECTORIES "${HTSLIB_INCLUDE_DIR}")

# RocksDB
# Warning: DISABLE_JEMALLOC=1 avoids link-time jemalloc dependency (LD_PRELOAD at runtime).
ExternalProject_Add(rocksdb
    URL https://github.com/facebook/rocksdb/archive/v11.8.1.tar.gz
    PREFIX ${CMAKE_CURRENT_BINARY_DIR}/external
    CONFIGURE_COMMAND ""
    BUILD_IN_SOURCE 1
    BUILD_COMMAND bash -c "export PORTABLE=1 \
        && export DISABLE_JEMALLOC=1 \
        && export ROCKSDB_DISABLE_BZIP=1 \
        && export OPT='-DNDEBUG -O3 ${ROCKSDB_ARCH_OPT} -DROCKSDB_NO_DYNAMIC_EXTENSION' \
        && export EXTRA_CXXFLAGS='-Wno-error ${ROCKSDB_EXTRA_CXXFLAGS}' \
        && export EXTRA_LDFLAGS='${ROCKSDB_EXTRA_LDFLAGS}' \
        && make -n static_lib \
        && make -j${NUM_CORES} static_lib"
    INSTALL_COMMAND ""
    LOG_DOWNLOAD ON
    LOG_BUILD ON
  )
ExternalProject_Get_Property(rocksdb source_dir)
set(ROCKSDB_INCLUDE_DIR ${source_dir}/include ${source_dir})
file(MAKE_DIRECTORY ${ROCKSDB_INCLUDE_DIR})
ExternalProject_Get_Property(rocksdb binary_dir)
add_library(librocksdb STATIC IMPORTED)
set(LIBROCKSDB_A ${binary_dir}/librocksdb.a)
set_target_properties(librocksdb PROPERTIES
    IMPORTED_LOCATION ${LIBROCKSDB_A}
    INTERFACE_INCLUDE_DIRECTORIES "${ROCKSDB_INCLUDE_DIR}")


# yaml-cpp
set(CMAKE_POLICY_VERSION_MINIMUM 3.5)
set(YAML_CPP_BUILD_TESTS OFF CACHE INTERNAL "")
set(YAML_CPP_BUILD_TOOLS OFF CACHE INTERNAL "")
set(YAML_CPP_BUILD_CONTRIB OFF CACHE INTERNAL "")
set(YAML_BUILD_SHARED_LIBS OFF CACHE INTERNAL "")
FetchContent_Declare(
    yaml-cpp
    URL https://github.com/jbeder/yaml-cpp/archive/0.8.0.tar.gz
    URL_HASH SHA256=fbe74bbdcee21d656715688706da3c8becfd946d92cd44705cc6098bb23b3a16
    EXCLUDE_FROM_ALL
)
FetchContent_MakeAvailable(yaml-cpp)
add_library(libyaml-cpp ALIAS yaml-cpp)

# spdlog (header-only)
FetchContent_Declare(
    spdlog
    URL https://github.com/gabime/spdlog/archive/v1.15.1.tar.gz
    URL_HASH SHA256=25c843860f039a1600f232c6eb9e01e6627f7d030a2ae5e232bdd3c9205d26cc
    PATCH_COMMAND sed -i.bak
        -e "s|str(S())|str(S{})|g"
        -e "s|string_view(S())|string_view(S{})|g"
        include/spdlog/fmt/bundled/base.h
)
FetchContent_GetProperties(spdlog)
if(NOT spdlog_POPULATED)
  FetchContent_Populate(spdlog)
endif()
add_library(libspdlog INTERFACE)
target_include_directories(libspdlog INTERFACE ${spdlog_SOURCE_DIR}/include)

# capnproto
set(WITH_OPENSSL OFF CACHE INTERNAL "")
set(BUILD_TESTING OFF)
add_compile_definitions(CAPNP_ALLOW_UNALIGNED)
FetchContent_Declare(
    CapnProto
    URL https://capnproto.org/capnproto-c++-1.0.2.tar.gz
    URL_HASH SHA256=9057dbc0223366b74bbeca33a05de164a229b0377927f1b7ef3828cdd8cb1d7e
    EXCLUDE_FROM_ALL
)
FetchContent_MakeAvailable(CapnProto)
unset(BUILD_TESTING)

option(BUILD_DEPS_ONLY "Only fetch and build external dependencies" OFF)
if(BUILD_DEPS_ONLY)
  add_custom_target(dependencies ALL DEPENDS htslib rocksdb)
  return()
endif()

# ==============================================================================
# 5. Code Generation (Cap'n Proto)
# ==============================================================================
set(CAPNPC_SRC_PREFIX "${CMAKE_CURRENT_SOURCE_DIR}/capnp/serialize")
capnp_generate_cpp(CAPNP_SRCS CAPNP_HDRS "${CMAKE_CURRENT_SOURCE_DIR}/capnp/serialize/defs.capnp")

# ==============================================================================
# 6. Core Library (glnexus)
# ==============================================================================
add_library(glnexus
            ${CAPNP_SRCS} ${CAPNP_HDRS}
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
            include/cli_utils.h src/cli_utils.cc)

target_compile_features(glnexus PUBLIC cxx_std_23)
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
    ${CMAKE_CURRENT_BINARY_DIR}
)
add_dependencies(glnexus htslib rocksdb)
add_library(libglnexus ALIAS glnexus)

option(STATIC_LIBDEPS "Link dependencies statically on Linux" OFF)

if(APPLE)
  target_link_options(glnexus INTERFACE -pthread -Wl,-U,_mallctl $<$<BOOL:${BREW_PREFIX}>:-L${BREW_PREFIX}/lib>)
  set(EXTERNAL_DEPS
      libhts librocksdb libyaml-cpp libctpl libfcmm libspdlog
      z deflate snappy zstd lz4 CapnProto::capnp)
else()
  target_link_options(glnexus INTERFACE ${ARCH_FLAGS} -static-libstdc++ -pthread)
  if(STATIC_LIBDEPS)
    set(SYS_LIBS libz.a libdeflate.a libsnappy.a libzstd.a librt.a)
  else()
    set(SYS_LIBS z deflate snappy zstd rt)
  endif()
  set(EXTERNAL_DEPS
      libhts librocksdb libyaml-cpp libctpl libfcmm libspdlog
      ${SYS_LIBS} CapnProto::capnp m ${CMAKE_DL_LIBS})
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
  FetchContent_Declare(
      Catch2
      URL https://github.com/catchorg/Catch2/archive/v3.8.0.tar.gz
      URL_HASH SHA256=1ab2de20460d4641553addfdfe6acd4109d871d5531f8f519a52ea4926303087
      EXCLUDE_FROM_ALL
  )
  FetchContent_MakeAvailable(Catch2)

  add_executable(unit_tests
                  test/diploid.cc
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
                  test/cli.cc
                  test/utils.cc)
  target_compile_options(unit_tests PRIVATE -Wno-unused-function)
  target_link_libraries(unit_tests PRIVATE glnexus Catch2::Catch2)

  add_test(NAME unit_tests
           WORKING_DIRECTORY "${PROJECT_SOURCE_DIR}"
           COMMAND $<TARGET_FILE:unit_tests> -d yes)
  if(NOT APPLE)
    add_test(NAME jemalloc_warning COMMAND ${CMAKE_CURRENT_SOURCE_DIR}/test/jemalloc_linking.sh $<TARGET_FILE:glnexus_cli>)
    add_test(NAME getting_started COMMAND ${CMAKE_CURRENT_SOURCE_DIR}/test/getting_started.sh $<TARGET_FILE:glnexus_cli>)
  endif()
endif()

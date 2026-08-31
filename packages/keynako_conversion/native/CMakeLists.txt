cmake_minimum_required(VERSION 3.14)
project(keynako_zenzai LANGUAGES C CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
include(CTest)

add_library(keynako_ime_core STATIC
  ime_core/azookey_dictionary.cpp
  ime_core/keynako_ime_core.cpp
  ime_core/zenzai_client.cpp
)
target_include_directories(keynako_ime_core PUBLIC ime_core)
set_target_properties(keynako_ime_core PROPERTIES POSITION_INDEPENDENT_CODE ON)

add_library(keynako_ime_bridge SHARED ime_core/keynako_ime_c_api.cpp)
target_link_libraries(keynako_ime_bridge PRIVATE keynako_ime_core)
target_include_directories(keynako_ime_bridge PUBLIC ime_core)
set_target_properties(keynako_ime_bridge PROPERTIES CXX_VISIBILITY_PRESET hidden)

if(BUILD_TESTING)
  add_executable(keynako_ime_core_test ime_core/keynako_ime_core_test.cpp)
  target_link_libraries(keynako_ime_core_test PRIVATE keynako_ime_core)
  add_test(NAME keynako_ime_core_test COMMAND keynako_ime_core_test)
  get_filename_component(KEYNAKO_TEST_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/../../.." ABSOLUTE)
  set_tests_properties(keynako_ime_core_test PROPERTIES ENVIRONMENT
    "KEYNAKO_TEST_AZOOKEY_DICTIONARY=${KEYNAKO_TEST_ROOT}/third_party/azookey_dictionary_storage/Dictionary")

  add_executable(keynako_ime_c_api_test ime_core/keynako_ime_c_api_test.cpp)
  target_link_libraries(keynako_ime_c_api_test PRIVATE keynako_ime_bridge)
  add_test(NAME keynako_ime_c_api_test COMMAND keynako_ime_c_api_test)
endif()

set(LLAMA_BUILD_COMMON OFF CACHE BOOL "" FORCE)
set(LLAMA_BUILD_TESTS OFF CACHE BOOL "" FORCE)
set(LLAMA_BUILD_EXAMPLES OFF CACHE BOOL "" FORCE)
set(LLAMA_BUILD_SERVER OFF CACHE BOOL "" FORCE)
set(BUILD_SHARED_LIBS OFF CACHE BOOL "" FORCE)
set(GGML_NATIVE OFF CACHE BOOL "" FORCE)
set(GGML_OPENMP OFF CACHE BOOL "" FORCE)
set(GGML_LLAMAFILE OFF CACHE BOOL "" FORCE)
set(GGML_METAL OFF CACHE BOOL "" FORCE)
set(GGML_VULKAN OFF CACHE BOOL "" FORCE)

get_filename_component(KEYNAKO_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/../../.." ABSOLUTE)
set(LLAMA_SOURCE "${KEYNAKO_ROOT}/android/app/src/main/cpp/llama.cpp")

if(NOT EXISTS "${LLAMA_SOURCE}/CMakeLists.txt")
  message(FATAL_ERROR "llama.cpp submodule is missing; run git submodule update --init --recursive")
endif()

add_subdirectory("${LLAMA_SOURCE}" "${CMAKE_CURRENT_BINARY_DIR}/llama")

add_executable(keynako_zenzai zenzai_cli.cpp)
target_include_directories(keynako_zenzai PRIVATE "${LLAMA_SOURCE}/include")
target_link_libraries(keynako_zenzai PRIVATE llama ggml)

if(MSVC)
  target_compile_options(keynako_zenzai PRIVATE /O2 /EHsc)
else()
  target_compile_options(keynako_zenzai PRIVATE -O3)
endif()

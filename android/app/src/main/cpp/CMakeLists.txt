cmake_minimum_required(VERSION 3.22.1)
project(keynako_zenz LANGUAGES C CXX)

option(ZENZ_NATIVE_OPTIMIZED "Build the Zenz native library with optimized flags" ON)

if(ZENZ_NATIVE_OPTIMIZED)
    set(CMAKE_BUILD_TYPE Release CACHE STRING "" FORCE)
    add_compile_options(-O3 -ffast-math -fno-finite-math-only -DNDEBUG)
endif()

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

set(LLAMA_BUILD_COMMON ON CACHE BOOL "" FORCE)
set(LLAMA_BUILD_TESTS OFF CACHE BOOL "" FORCE)
set(LLAMA_BUILD_EXAMPLES OFF CACHE BOOL "" FORCE)
set(LLAMA_BUILD_SERVER OFF CACHE BOOL "" FORCE)
set(BUILD_SHARED_LIBS OFF CACHE BOOL "" FORCE)
set(GGML_OPENMP OFF CACHE BOOL "" FORCE)
set(GGML_LLAMAFILE OFF CACHE BOOL "" FORCE)

add_definitions(-D__ANDROID__)
add_subdirectory(llama.cpp)

add_library(zenz SHARED zenz_bridge.cpp)

target_include_directories(zenz PRIVATE
    ${CMAKE_SOURCE_DIR}
    ${CMAKE_SOURCE_DIR}/llama.cpp/include
    ${CMAKE_SOURCE_DIR}/llama.cpp/ggml/include
    ${CMAKE_SOURCE_DIR}/llama.cpp/common
)

find_library(log-lib log)

target_link_libraries(zenz
    PRIVATE
    llama
    ggml
    ${log-lib}
)

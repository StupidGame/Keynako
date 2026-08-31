cmake_minimum_required(VERSION 3.20)
project(keynako_windows_ime LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

get_filename_component(KEYNAKO_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/../.." ABSOLUTE)
set(KEYNAKO_CORE "${KEYNAKO_ROOT}/packages/keynako_conversion/native/ime_core")

add_library(KeynakoIME SHARED
  keynako_tsf.cpp
  KeynakoIME.def
  KeynakoIME.rc
  "${KEYNAKO_CORE}/azookey_dictionary.cpp"
  "${KEYNAKO_CORE}/keynako_ime_core.cpp"
  "${KEYNAKO_CORE}/zenzai_client.cpp"
)
target_include_directories(KeynakoIME PRIVATE "${KEYNAKO_CORE}")
target_compile_definitions(KeynakoIME PRIVATE UNICODE _UNICODE WIN32_LEAN_AND_MEAN NOMINMAX)
target_link_libraries(KeynakoIME PRIVATE advapi32 dwmapi gdi32 ole32 oleaut32 shell32 user32 uuid)
set_target_properties(KeynakoIME PROPERTIES PREFIX "" OUTPUT_NAME "KeynakoIME")

if(MSVC)
  target_compile_options(KeynakoIME PRIVATE /W4 /EHsc /utf-8 /permissive-)
endif()

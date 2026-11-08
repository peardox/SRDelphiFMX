#
# LenticularBridge.dll - C shim around the lenticular display runtime's DX11 weaver for Delphi.
#
#   cmake -S . -B build -G "Visual Studio 17 2022" -A x64 -DLENTICULAR_SDKROOT=C:/path/to/the-runtime-SDK
#   cmake --build build --config Release
#
# Must be built with MSVC x64 (the runtime's weaver C++ interface uses MSVC ABI).
#
cmake_minimum_required(VERSION 3.16)
project(LenticularBridge CXX)

if(NOT MSVC)
  message(FATAL_ERROR "LenticularBridge must be built with MSVC (the runtime's weaver uses the MSVC C++ ABI).")
endif()
if(NOT CMAKE_SIZEOF_VOID_P EQUAL 8)
  message(FATAL_ERROR "Build for x64 (-A x64). The runtime SDK is 64-bit.")
endif()

set(LENTICULAR_SDKROOT "$ENV{LENTICULAR_SDKROOT}" CACHE PATH "Path to the extracted display runtime SDK")
if(NOT EXISTS "${LENTICULAR_SDKROOT}/include/sr/weaver/dx11weaver.h")
  message(FATAL_ERROR "LENTICULAR_SDKROOT does not point at the runtime SDK (include/sr/weaver/dx11weaver.h not found)")
endif()

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# The runtime's C functions can throw C++ exceptions (e.g. ServerNotAvailableException).
# /EHs (without 'c') stops MSVC assuming extern "C" functions never throw,
# so our try/catch(...) around them is not optimised away.
string(REPLACE "/EHsc" "/EHs" CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS}")

add_library(LenticularBridge SHARED LenticularBridge.cpp LenticularBridge.h)
# sdk_stub MUST come first: it replaces sr/management/srcontext.h with a forward
# declaration so OpenCV is never pulled in (see sdk_stub/sr/management/srcontext.h).
target_include_directories(LenticularBridge BEFORE PRIVATE
  "${CMAKE_CURRENT_SOURCE_DIR}/sdk_stub"
  "${LENTICULAR_SDKROOT}/include"
)
target_compile_definitions(LenticularBridge PRIVATE WIN32 _CRT_SECURE_NO_WARNINGS)
target_compile_options(LenticularBridge PRIVATE /W3 /wd4251 /wd4275 /wd4996 /EHs)
target_link_libraries(LenticularBridge PRIVATE d3d11 dxgi d3dcompiler dwmapi)
# Use the dynamic release CRT (/MD) like the display runtime itself, even in Debug builds
set_property(TARGET LenticularBridge PROPERTY MSVC_RUNTIME_LIBRARY "MultiThreadedDLL")

# Copy the built DLL into the repository's dll folder, where the Delphi
# projects' post-build step picks it up.
add_custom_command(TARGET LenticularBridge POST_BUILD
  COMMAND ${CMAKE_COMMAND} -E make_directory "${CMAKE_CURRENT_SOURCE_DIR}/../dll"
  COMMAND ${CMAKE_COMMAND} -E copy_if_different "$<TARGET_FILE:LenticularBridge>" "${CMAKE_CURRENT_SOURCE_DIR}/../dll/"
  COMMENT "Copying LenticularBridge.dll to dll/")

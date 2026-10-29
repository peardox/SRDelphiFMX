#
# SRFmxBridge.dll - C shim around the LeiaSR DX11 weaver for Delphi.
#
#   cmake -S . -B build -G "Visual Studio 17 2022" -A x64 -DLEIASR_SDKROOT=C:/path/to/simulatedreality-SDK
#   cmake --build build --config Release
#
# Must be built with MSVC x64 (the SR weaver C++ interface uses MSVC ABI).
#
cmake_minimum_required(VERSION 3.16)
project(SRFmxBridge CXX)

if(NOT MSVC)
  message(FATAL_ERROR "SRFmxBridge must be built with MSVC (SR weaver uses the MSVC C++ ABI).")
endif()
if(NOT CMAKE_SIZEOF_VOID_P EQUAL 8)
  message(FATAL_ERROR "Build for x64 (-A x64). The SR SDK is 64-bit.")
endif()

set(LEIASR_SDKROOT "$ENV{LEIASR_SDKROOT}" CACHE PATH "Path to the extracted LeiaSR SDK")
if(NOT EXISTS "${LEIASR_SDKROOT}/include/sr/weaver/dx11weaver.h")
  message(FATAL_ERROR "LEIASR_SDKROOT does not point at the SR SDK (include/sr/weaver/dx11weaver.h not found)")
endif()

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# The SR C functions can throw C++ exceptions (e.g. ServerNotAvailableException).
# /EHs (without 'c') stops MSVC assuming extern "C" functions never throw,
# so our try/catch(...) around them is not optimised away.
string(REPLACE "/EHsc" "/EHs" CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS}")

add_library(SRFmxBridge SHARED SRFmxBridge.cpp SRFmxBridge.h)
# sr_stub MUST come first: it replaces sr/management/srcontext.h with a forward
# declaration so OpenCV is never pulled in (see sr_stub/sr/management/srcontext.h).
target_include_directories(SRFmxBridge BEFORE PRIVATE
  "${CMAKE_CURRENT_SOURCE_DIR}/sr_stub"
  "${LEIASR_SDKROOT}/include"
)
target_compile_definitions(SRFmxBridge PRIVATE WIN32 _CRT_SECURE_NO_WARNINGS)
target_compile_options(SRFmxBridge PRIVATE /W3 /wd4251 /wd4275 /wd4996 /EHs)
target_link_libraries(SRFmxBridge PRIVATE d3d11 dxgi)
# Use the dynamic release CRT (/MD) like the SR runtime itself, even in Debug builds
set_property(TARGET SRFmxBridge PROPERTY MSVC_RUNTIME_LIBRARY "MultiThreadedDLL")

# Copy the built DLL into the repository's dll folder, where the Delphi
# projects' post-build step picks it up.
add_custom_command(TARGET SRFmxBridge POST_BUILD
  COMMAND ${CMAKE_COMMAND} -E make_directory "${CMAKE_CURRENT_SOURCE_DIR}/../dll"
  COMMAND ${CMAKE_COMMAND} -E copy_if_different "$<TARGET_FILE:SRFmxBridge>" "${CMAKE_CURRENT_SOURCE_DIR}/../dll/"
  COMMENT "Copying SRFmxBridge.dll to dll/")

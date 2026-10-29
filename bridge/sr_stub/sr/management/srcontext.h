/*
 * Stand-in for the SDK's sr/management/srcontext.h, used ONLY by SRFmxBridge.
 *
 * The real header pulls in sr/network/... which includes <opencv2/opencv.hpp>;
 * that drags inline OpenCV code into this DLL needing opencv_world.lib, which
 * the SDK does not ship (LNK2019 cv::String::deallocate).
 *
 * dx11weaver.h only uses SR::SRContext as an opaque pointer type, so a forward
 * declaration is all we need. The mangled name is identical ("class SRContext"
 * in namespace SR), so SR::CreateDX11Weaver still resolves.
 */
#pragma once

namespace SR {
class SRContext;
}

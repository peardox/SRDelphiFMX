/*
 * SRFmxBridge.cpp - see SRFmxBridge.h for the overview.
 *
 * Build with MSVC x64 (the SR weaver interface uses MSVC virtual-inheritance
 * layout, so MinGW/Clang-GNU builds are NOT ABI compatible).
 *
 * The SR runtime DLLs are loaded dynamically, so no SR import libraries are
 * needed at link time (the SDK zip does not ship them).
 */
#define WIN32_LEAN_AND_MEAN
#define NOMINMAX
#include <windows.h>
#include <d3d11.h>
#include <dxgi1_2.h>

#include <float.h>
#include <cstdarg>
#include <csignal>
#include <cstdio>
#include <exception>
#include <stdlib.h>
#include <algorithm>
#include <atomic>
#include <cstring>
#include <deque>
#include <mutex>
#include <string>

#include "sr/types.h"
#include "sr/sense/system/systemevent.h"
#include "sr/weaver/dx11weaver.h"

#define SRFMXBRIDGE_EXPORTS
#include "SRFmxBridge.h"

#pragma comment(lib, "d3d11.lib")
#pragma comment(lib, "dxgi.lib")

namespace {

// ---------------------------------------------------------------------------
// SR C API function pointers (resolved at runtime)
// ---------------------------------------------------------------------------
typedef void* (*PFN_newSRContext)();
typedef void  (*PFN_initializeSRContext)(void*);
typedef void  (*PFN_deleteSRContext)(void*);
typedef void* (*PFN_createSystemSense)(void*);
typedef void* (*PFN_createSystemEventListener)(void*, void (*)(SR_systemEvent));
typedef void  (*PFN_deleteSystemEventListener)(void*);
typedef void* (*PFN_createDisplay)(void*);
typedef int   (*PFN_getInt)(void*);
typedef float (*PFN_getFloat)(void*);
typedef void* (*PFN_createSwitchableLensHint)(void*);
typedef void  (*PFN_lensHint)(void*);
typedef const char* (*PFN_getSRPlatformVersion)();
typedef WeaverErrorCode (*PFN_CreateDX11Weaver)(SR::SRContext*, ID3D11DeviceContext*, HWND, SR::IDX11Weaver1**);

struct SRApi {
    HMODULE core = nullptr, displays = nullptr, directx = nullptr, version = nullptr;

    PFN_newSRContext               newSRContext = nullptr;
    PFN_initializeSRContext        initializeSRContext = nullptr;
    PFN_deleteSRContext            deleteSRContext = nullptr;
    PFN_createSystemSense          createSystemSense = nullptr;
    PFN_createSystemEventListener  createSystemEventListener = nullptr;
    PFN_deleteSystemEventListener  deleteSystemEventListener = nullptr;

    PFN_createDisplay              createDisplay = nullptr;
    PFN_getInt                     getResolutionWidth = nullptr, getResolutionHeight = nullptr;
    PFN_getInt                     getPhysicalResolutionWidth = nullptr, getPhysicalResolutionHeight = nullptr;
    PFN_getFloat                   getPhysicalSizeWidth = nullptr, getPhysicalSizeHeight = nullptr;
    PFN_getInt                     getRecommendedViewsTextureWidth = nullptr, getRecommendedViewsTextureHeight = nullptr;
    PFN_createSwitchableLensHint   createSwitchableLensHint = nullptr;
    PFN_lensHint                   lensEnableHint = nullptr, lensDisableHint = nullptr;

    PFN_getSRPlatformVersion       getSRPlatformVersion = nullptr;
    PFN_CreateDX11Weaver           CreateDX11Weaver = nullptr;

    bool loaded = false;
};

// Find an export whose (decorated) name contains `needle`. Used for the C++
// function SR::CreateDX11Weaver, whose MSVC-mangled name we'd rather not hard-code.
FARPROC FindExportContaining(HMODULE mod, const char* needle)
{
    if (!mod) return nullptr;
    auto base = reinterpret_cast<const BYTE*>(mod);
    auto dos  = reinterpret_cast<const IMAGE_DOS_HEADER*>(base);
    if (dos->e_magic != IMAGE_DOS_SIGNATURE) return nullptr;
    auto nt   = reinterpret_cast<const IMAGE_NT_HEADERS*>(base + dos->e_lfanew);
    const IMAGE_DATA_DIRECTORY& dir = nt->OptionalHeader.DataDirectory[IMAGE_DIRECTORY_ENTRY_EXPORT];
    if (dir.VirtualAddress == 0) return nullptr;
    auto exp   = reinterpret_cast<const IMAGE_EXPORT_DIRECTORY*>(base + dir.VirtualAddress);
    auto names = reinterpret_cast<const DWORD*>(base + exp->AddressOfNames);
    auto ords  = reinterpret_cast<const WORD*>(base + exp->AddressOfNameOrdinals);
    auto funcs = reinterpret_cast<const DWORD*>(base + exp->AddressOfFunctions);
    for (DWORD i = 0; i < exp->NumberOfNames; ++i) {
        const char* name = reinterpret_cast<const char*>(base + names[i]);
        if (std::strstr(name, needle) != nullptr)
            return reinterpret_cast<FARPROC>(const_cast<BYTE*>(base + funcs[ords[i]]));
    }
    return nullptr;
}

// ---------------------------------------------------------------------------
// Global bridge state (single instance - one SR window per process)
// ---------------------------------------------------------------------------
struct Bridge {
    SRApi api;

    // SR objects
    void*               srContext   = nullptr;
    void*               display     = nullptr;
    void*               sysListener = nullptr;
    void*               lensHint    = nullptr;
    SR::IDX11Weaver1*   weaver      = nullptr;
    std::atomic<bool>   contextInvalid{ false };
    ULONGLONG           lastReinitTick = 0;

    // D3D
    ID3D11Device*           dev   = nullptr;
    ID3D11DeviceContext*    ctx   = nullptr;
    IDXGISwapChain1*        swap  = nullptr;
    ID3D11RenderTargetView* rtv   = nullptr;
    ID3D11Texture2D*        sbsTex = nullptr;
    ID3D11ShaderResourceView* sbsSrv = nullptr;
    int  texViewW = 0, texViewH = 0, texFmt = -1;
    bool weaverInputDirty = true;

    // Window
    HWND parent = nullptr, child = nullptr;
    int  x = 0, y = 0, bbW = 0, bbH = 0;
    bool visible = true;

    // Options
    int      vsync = 1;
    uint64_t latencyFrames = 0;   // 0 = leave weaver default
    bool     lensOn = true;

    // Events / errors
    std::mutex                  evMutex;
    std::deque<SRB_SystemEvent> events;
    std::string                 lastError;
    std::string                 versionStr;

    bool initialized = false;

    // Diagnostics (srb_GetStats)
    SRB_Stats stats{};
};

Bridge g;

// Delphi (11 and earlier) runs with floating-point exceptions UNMASKED. Driver /
// SR / OpenCV code expects them masked, so every export masks them for its
// duration and restores the caller's control word on exit.
struct FPGuard {
    unsigned int saved = 0;
    FPGuard()  { unsigned int t; _controlfp_s(&saved, 0, 0); _controlfp_s(&t, _MCW_EM, _MCW_EM); }
    ~FPGuard() { unsigned int t; _controlfp_s(&t, saved, _MCW_EM); }
};
#define SRB_ENTRY FPGuard fpGuard_; (void)fpGuard_

template <class T> void SafeRelease(T*& p) { if (p) { p->Release(); p = nullptr; } }

// ---------------------------------------------------------------------------
// Diagnostic log: lines go to a callback set by the host (srb_SetLogCallback),
// which must be thread-safe, since SR calls us on its own threads.
// ---------------------------------------------------------------------------
std::atomic<SRB_LogCallback> g_logCallback{ nullptr };
std::atomic<int> g_submitTrace{ 3 };   // first submits logged step by step

void BLog(const char* fmt, ...)
{
    SRB_LogCallback cb = g_logCallback.load();
    if (!cb) return;
    char buf[1024];
    int n = std::snprintf(buf, sizeof(buf), "[bridge t%lu] ", static_cast<unsigned long>(GetCurrentThreadId()));
    va_list args;
    va_start(args, fmt);
    std::vsnprintf(buf + n, sizeof(buf) - n, fmt, args);
    va_end(args);
    cb(buf);
}

// Last-gasp handlers: these are reached when something in this process (most
// likely the SR runtime or a driver) aborts, throws past every catch, calls a
// pure virtual function or passes a bad argument to the CRT. They log and then
// let the process end as it would have.
void OnAbortSignal(int)
{
    BLog("FATAL: abort() called (SIGABRT) - a C++ library gave up");
}
void OnTerminate()
{
    BLog("FATAL: std::terminate - a C++ exception escaped on thread %lu",
         static_cast<unsigned long>(GetCurrentThreadId()));
    std::abort();
}
void OnPureCall()
{
    BLog("FATAL: pure virtual function call (an object used after destruction?)");
    std::abort();
}
void OnInvalidParameter(const wchar_t*, const wchar_t*, const wchar_t*, unsigned int, uintptr_t)
{
    BLog("FATAL: CRT invalid parameter");
    std::abort();
}

void InstallFatalHandlers()
{
    static bool done = false;
    if (done) return;
    done = true;
    std::signal(SIGABRT, OnAbortSignal);
    std::set_terminate(OnTerminate);
    _set_purecall_handler(OnPureCall);
    _set_invalid_parameter_handler(OnInvalidParameter);
}

int Fail(int code, const char* msg)
{
    g.lastError = msg;
    BLog("error %d: %s", code, msg);
    return code;
}

// ---------------------------------------------------------------------------
// SR runtime loading
// ---------------------------------------------------------------------------
bool LoadSRApi()
{
    SRApi& a = g.api;
    if (a.loaded) return true;

    a.core     = LoadLibraryW(L"SimulatedRealityCore.dll");
    a.displays = LoadLibraryW(L"SimulatedRealityDisplays.dll");
    a.directx  = LoadLibraryW(L"SimulatedRealityDirectX.dll");
    a.version  = LoadLibraryW(L"SimulatedReality.dll");   // optional (version string only)

    if (!a.core || !a.displays || !a.directx) {
        g.lastError = "SR runtime DLLs not found (SimulatedRealityCore/Displays/DirectX.dll). "
                      "Install the LeiaSR Platform runtime or call srb_SetDllDirectory().";
        return false;
    }

#define LOADFN(mod, name) a.name = reinterpret_cast<decltype(a.name)>(GetProcAddress(a.mod, #name)); \
                          if (!a.name) { g.lastError = "Missing SR export: " #name; return false; }
    LOADFN(core, newSRContext);
    LOADFN(core, initializeSRContext);
    LOADFN(core, deleteSRContext);
    LOADFN(core, createSystemSense);
    LOADFN(core, createSystemEventListener);
    LOADFN(core, deleteSystemEventListener);
    LOADFN(displays, createDisplay);
    LOADFN(displays, getResolutionWidth);
    LOADFN(displays, getResolutionHeight);
    LOADFN(displays, getPhysicalResolutionWidth);
    LOADFN(displays, getPhysicalResolutionHeight);
    LOADFN(displays, getPhysicalSizeWidth);
    LOADFN(displays, getPhysicalSizeHeight);
    LOADFN(displays, getRecommendedViewsTextureWidth);
    LOADFN(displays, getRecommendedViewsTextureHeight);
    LOADFN(displays, createSwitchableLensHint);
    LOADFN(displays, lensEnableHint);
    LOADFN(displays, lensDisableHint);
#undef LOADFN

    if (a.version)
        a.getSRPlatformVersion = reinterpret_cast<PFN_getSRPlatformVersion>(GetProcAddress(a.version, "getSRPlatformVersion"));

    // SR::CreateDX11Weaver(SR::SRContext*, ID3D11DeviceContext*, HWND, SR::IDX11Weaver1**)
    a.CreateDX11Weaver = reinterpret_cast<PFN_CreateDX11Weaver>(GetProcAddress(a.directx,
        "?CreateDX11Weaver@SR@@YA?AW4WeaverErrorCode@@PEAVSRContext@1@PEAUID3D11DeviceContext@@PEAUHWND__@@PEAPEAVIDX11Weaver1@1@@Z"));
    if (!a.CreateDX11Weaver)
        a.CreateDX11Weaver = reinterpret_cast<PFN_CreateDX11Weaver>(FindExportContaining(a.directx, "?CreateDX11Weaver@SR@@"));
    if (!a.CreateDX11Weaver) {
        g.lastError = "SR::CreateDX11Weaver not exported by SimulatedRealityDirectX.dll (runtime too old?)";
        return false;
    }

    a.loaded = true;
    return true;
}

void OnSystemEvent(SR_systemEvent ev)   // called on an SR thread
{
    SRB_SystemEvent e{};
    e.time = ev.time;
    e.eventType = static_cast<uint64_t>(ev.eventType);
    if (ev.message) {
        size_t n = std::min<size_t>(static_cast<size_t>(ev.messageLength), sizeof(e.message) - 1);
        std::memcpy(e.message, ev.message, n);
        e.message[n] = 0;
    }
    if (e.eventType == 1 /* ContextInvalid */)
        g.contextInvalid = true;
    BLog("SR system event %llu: %s", static_cast<unsigned long long>(e.eventType), e.message);

    std::lock_guard<std::mutex> lock(g.evMutex);
    if (g.events.size() > 256) g.events.pop_front();
    g.events.push_back(e);
}

void TearDownSR()
{
    g.contextInvalid = false;   // cleared first so an event arriving during teardown isn't lost
    if (g.weaver || g.srContext) BLog("tearing down SR (weaver %p, context %p)", (void*)g.weaver, g.srContext);
    if (g.weaver) { g.weaver->destroy(); g.weaver = nullptr; BLog("weaver destroyed"); }
    if (g.sysListener && g.api.deleteSystemEventListener) { g.api.deleteSystemEventListener(g.sysListener); g.sysListener = nullptr; }
    // display, systemSense and lensHint are owned by the context
    g.display = nullptr;
    g.lensHint = nullptr;
    if (g.srContext && g.api.deleteSRContext) {
        try { g.api.deleteSRContext(g.srContext); } catch (...) { BLog("exception deleting SR context"); }
        g.srContext = nullptr;
        BLog("SR context deleted");
    }
}

// Creates context, waits for the display, creates weaver. Requires D3D + child window.
int CreateSR(double timeoutSeconds)
{
    const ULONGLONG start = GetTickCount64();
    auto timedOut = [&]() { return (GetTickCount64() - start) > static_cast<ULONGLONG>(timeoutSeconds * 1000.0); };

    // 1. Context (throws SR::ServerNotAvailableException while the SR service starts up)
    BLog("creating SR context (timeout %.1f s)", timeoutSeconds);
    while (!g.srContext) {
        try { g.srContext = g.api.newSRContext(); } catch (...) { g.srContext = nullptr; }
        if (g.srContext || timedOut()) break;
        Sleep(100);
    }
    if (g.srContext) BLog("SR context %p", g.srContext);
    if (!g.srContext) return Fail(SRB_E_NO_SERVICE, "Could not create SR context - is the SR service running?");

    // 2. Display ready
    bool ready = false;
    for (;;) {
        try {
            if (!g.display) g.display = g.api.createDisplay(g.srContext);   // owned by the context: create once
            if (g.display && g.api.getResolutionWidth(g.display) > 0 && g.api.getPhysicalSizeWidth(g.display) > 0.0f)
                ready = true;
        } catch (...) {}
        if (ready || timedOut()) break;
        Sleep(100);
    }
    if (!ready) { TearDownSR(); return Fail(SRB_E_NO_DISPLAY, "SR display not ready (cable / USB connected? display in extended mode at native resolution?)"); }

    BLog("display %p ready: %d x %d px, %.1f x %.1f cm", g.display,
         g.api.getResolutionWidth(g.display), g.api.getResolutionHeight(g.display),
         g.api.getPhysicalSizeWidth(g.display), g.api.getPhysicalSizeHeight(g.display));

    // 3. System events
    try {
        void* sense = g.api.createSystemSense(g.srContext);
        if (sense) g.sysListener = g.api.createSystemEventListener(sense, &OnSystemEvent);
    } catch (...) {}

    // 4. Lens hint
    try {
        g.lensHint = g.api.createSwitchableLensHint(g.srContext);
        if (g.lensHint) { if (g.lensOn) g.api.lensEnableHint(g.lensHint); else g.api.lensDisableHint(g.lensHint); }
    } catch (...) {}

    BLog("system listener %p, lens hint %p", g.sysListener, g.lensHint);

    // 5. Weaver (the SR C context handle is the C++ SR::SRContext*)
    SR::IDX11Weaver1* w = nullptr;
    WeaverErrorCode rc = WeaverErrorCode::WeaverTextureNotFound;
    try { rc = g.api.CreateDX11Weaver(reinterpret_cast<SR::SRContext*>(g.srContext), g.ctx, g.child, &w); }
    catch (...) { w = nullptr; }
    if (rc != WeaverErrorCode::WeaverSuccess || !w) { TearDownSR(); return Fail(SRB_E_WEAVER, "SR::CreateDX11Weaver failed"); }
    g.weaver = w;
    BLog("weaver %p created", (void*)w);
    g.weaver->setShaderSRGBConversion(false, false);  // we use *_SRGB views: hardware conversion
    if (g.latencyFrames) g.weaver->setLatencyInFrames(g.latencyFrames);
    g.weaverInputDirty = true;

    // 6. Initialise context after all senses / weaver are created (as in the SDK samples)
    try { g.api.initializeSRContext(g.srContext); } catch (...) { BLog("exception in initializeSRContext"); }
    BLog("SR context initialised");
    return SRB_OK;
}

// ---------------------------------------------------------------------------
// Child window
// ---------------------------------------------------------------------------
LRESULT CALLBACK ChildWndProc(HWND hWnd, UINT msg, WPARAM wParam, LPARAM lParam)
{
    switch (msg) {
    case WM_NCHITTEST:   return HTTRANSPARENT;  // mouse goes to the FMX form underneath
    case WM_ERASEBKGND:  return 1;
    case WM_PAINT:       ValidateRect(hWnd, nullptr); return 0;
    }
    return DefWindowProcW(hWnd, msg, wParam, lParam);
}

bool CreateChildWindow(HWND parent)
{
    static const wchar_t* kClass = L"SRFmxBridgeChildWindow";
    HINSTANCE inst = GetModuleHandleW(nullptr);
    WNDCLASSEXW wc{};
    wc.cbSize = sizeof(wc);
    if (!GetClassInfoExW(inst, kClass, &wc)) {
        wc = {};
        wc.cbSize        = sizeof(wc);
        wc.lpfnWndProc   = ChildWndProc;
        wc.hInstance     = inst;
        wc.hCursor       = LoadCursor(nullptr, IDC_ARROW);
        wc.lpszClassName = kClass;
        if (!RegisterClassExW(&wc)) return false;
    }
    // Make sure the parent doesn't paint over us.
    LONG_PTR style = GetWindowLongPtrW(parent, GWL_STYLE);
    if (!(style & WS_CLIPCHILDREN)) SetWindowLongPtrW(parent, GWL_STYLE, style | WS_CLIPCHILDREN);

    g.child = CreateWindowExW(WS_EX_NOPARENTNOTIFY, kClass, L"", WS_CHILD | WS_CLIPSIBLINGS,
                              0, 0, 1, 1, parent, nullptr, inst, nullptr);
    g.bbW = 1; g.bbH = 1;
    return g.child != nullptr;
}

// ---------------------------------------------------------------------------
// D3D11
// ---------------------------------------------------------------------------
bool CreateRTV()
{
    SafeRelease(g.rtv);
    ID3D11Texture2D* bb = nullptr;
    if (FAILED(g.swap->GetBuffer(0, __uuidof(ID3D11Texture2D), reinterpret_cast<void**>(&bb)))) return false;
    D3D11_RENDER_TARGET_VIEW_DESC rd{};
    rd.Format = DXGI_FORMAT_B8G8R8A8_UNORM_SRGB;     // sRGB view on a UNORM flip-model buffer
    rd.ViewDimension = D3D11_RTV_DIMENSION_TEXTURE2D;
    HRESULT hr = g.dev->CreateRenderTargetView(bb, &rd, &g.rtv);
    bb->Release();
    return SUCCEEDED(hr);
}

bool CreateD3D()
{
    UINT flags = D3D11_CREATE_DEVICE_BGRA_SUPPORT;
    const D3D_FEATURE_LEVEL levels[] = { D3D_FEATURE_LEVEL_11_1, D3D_FEATURE_LEVEL_11_0 };
    HRESULT hr = D3D11CreateDevice(nullptr, D3D_DRIVER_TYPE_HARDWARE, nullptr, flags, levels, 2,
                                   D3D11_SDK_VERSION, &g.dev, nullptr, &g.ctx);
    if (hr == E_INVALIDARG) // no 11_1 runtime
        hr = D3D11CreateDevice(nullptr, D3D_DRIVER_TYPE_HARDWARE, nullptr, flags, levels + 1, 1,
                               D3D11_SDK_VERSION, &g.dev, nullptr, &g.ctx);
    if (FAILED(hr)) return false;

    IDXGIDevice*   dxgiDev = nullptr;
    IDXGIAdapter*  adapter = nullptr;
    IDXGIFactory2* factory = nullptr;
    bool ok = SUCCEEDED(g.dev->QueryInterface(__uuidof(IDXGIDevice), reinterpret_cast<void**>(&dxgiDev)))
           && SUCCEEDED(dxgiDev->GetAdapter(&adapter))
           && SUCCEEDED(adapter->GetParent(__uuidof(IDXGIFactory2), reinterpret_cast<void**>(&factory)));
    if (ok) {
        DXGI_SWAP_CHAIN_DESC1 sd{};
        sd.Width = static_cast<UINT>(g.bbW);
        sd.Height = static_cast<UINT>(g.bbH);
        sd.Format = DXGI_FORMAT_B8G8R8A8_UNORM;
        sd.SampleDesc.Count = 1;
        sd.BufferUsage = DXGI_USAGE_RENDER_TARGET_OUTPUT;
        sd.BufferCount = 2;
        sd.Scaling = DXGI_SCALING_STRETCH;
        sd.SwapEffect = DXGI_SWAP_EFFECT_FLIP_DISCARD;
        sd.AlphaMode = DXGI_ALPHA_MODE_IGNORE;
        hr = factory->CreateSwapChainForHwnd(g.dev, g.child, &sd, nullptr, nullptr, &g.swap);
        if (FAILED(hr)) { // pre-Windows-10 fallback
            sd.SwapEffect = DXGI_SWAP_EFFECT_FLIP_SEQUENTIAL;
            hr = factory->CreateSwapChainForHwnd(g.dev, g.child, &sd, nullptr, nullptr, &g.swap);
        }
        ok = SUCCEEDED(hr);
        if (ok) factory->MakeWindowAssociation(g.child, DXGI_MWA_NO_ALT_ENTER);
    }
    SafeRelease(factory); SafeRelease(adapter); SafeRelease(dxgiDev);
    return ok && CreateRTV();
}

void DestroyD3D()
{
    if (g.ctx) { g.ctx->ClearState(); g.ctx->Flush(); }
    SafeRelease(g.sbsSrv); SafeRelease(g.sbsTex);
    SafeRelease(g.rtv); SafeRelease(g.swap);
    SafeRelease(g.ctx); SafeRelease(g.dev);
    g.texViewW = g.texViewH = 0; g.texFmt = -1;
}

bool ResizeBackBuffer(int w, int h)
{
    if (!g.swap) return false;
    g.ctx->OMSetRenderTargets(0, nullptr, nullptr);
    SafeRelease(g.rtv);
    g.ctx->Flush();
    if (FAILED(g.swap->ResizeBuffers(0, static_cast<UINT>(w), static_cast<UINT>(h), DXGI_FORMAT_UNKNOWN, 0))) return false;
    g.bbW = w; g.bbH = h;
    return CreateRTV();
}

bool EnsureViewTexture(int viewW, int viewH, int fmt)
{
    if (g.sbsTex && viewW == g.texViewW && viewH == g.texViewH && fmt == g.texFmt) return true;
    SafeRelease(g.sbsSrv); SafeRelease(g.sbsTex);

    D3D11_TEXTURE2D_DESC td{};
    td.Width = static_cast<UINT>(viewW * 2);
    td.Height = static_cast<UINT>(viewH);
    td.MipLevels = 1;
    td.ArraySize = 1;
    td.Format = (fmt == SRB_FMT_RGBA8) ? DXGI_FORMAT_R8G8B8A8_TYPELESS : DXGI_FORMAT_B8G8R8A8_TYPELESS;
    td.SampleDesc.Count = 1;
    td.Usage = D3D11_USAGE_DEFAULT;
    td.BindFlags = D3D11_BIND_SHADER_RESOURCE;
    if (FAILED(g.dev->CreateTexture2D(&td, nullptr, &g.sbsTex))) return false;

    D3D11_SHADER_RESOURCE_VIEW_DESC sv{};
    sv.Format = (fmt == SRB_FMT_RGBA8) ? DXGI_FORMAT_R8G8B8A8_UNORM_SRGB : DXGI_FORMAT_B8G8R8A8_UNORM_SRGB;
    sv.ViewDimension = D3D11_SRV_DIMENSION_TEXTURE2D;
    sv.Texture2D.MipLevels = 1;
    if (FAILED(g.dev->CreateShaderResourceView(g.sbsTex, &sv, &g.sbsSrv))) { SafeRelease(g.sbsTex); return false; }

    g.texViewW = viewW; g.texViewH = viewH; g.texFmt = fmt;
    g.weaverInputDirty = true;
    return true;
}

DXGI_FORMAT ViewSrvFormat() {
    return (g.texFmt == SRB_FMT_RGBA8) ? DXGI_FORMAT_R8G8B8A8_UNORM_SRGB : DXGI_FORMAT_B8G8R8A8_UNORM_SRGB;
}

} // namespace

// ===========================================================================
// Exports
// ===========================================================================

SRB_API int32_t srb_Initialize(void* parentWnd, double timeoutSeconds)
{
    SRB_ENTRY;
    if (g.initialized) {
        if (g.parent == static_cast<HWND>(parentWnd)) return SRB_OK;
        return Fail(SRB_E_ARGS, "Already initialised for a different window (one SR window per process)");
    }
    g.lastError.clear();
    InstallFatalHandlers();
    g_submitTrace = 3;
    BLog("srb_Initialize(parent %p)", parentWnd);
    HWND parent = static_cast<HWND>(parentWnd);
    if (!parent || !IsWindow(parent)) return Fail(SRB_E_ARGS, "Invalid parent window handle");
    if (!LoadSRApi()) return SRB_E_SR_DLL_MISSING;

    g.parent = parent;
    if (!CreateChildWindow(parent)) return Fail(SRB_E_WINDOW, "Could not create child window");
    if (!CreateD3D()) { DestroyD3D(); DestroyWindow(g.child); g.child = nullptr; return Fail(SRB_E_D3D, "Direct3D 11 initialisation failed"); }

    BLog("child window %p, D3D device %p, swap chain %p", (void*)g.child, (void*)g.dev, (void*)g.swap);
    int rc = CreateSR(timeoutSeconds);
    if (rc != SRB_OK) { DestroyD3D(); DestroyWindow(g.child); g.child = nullptr; return rc; }

    g.initialized = true;
    BLog("srb_Initialize done");
    return SRB_OK;
}

SRB_API void srb_Finalize(void)
{
    SRB_ENTRY;
    BLog("srb_Finalize");
    try { TearDownSR(); } catch (...) { g.weaver = nullptr; g.srContext = nullptr; }          // weaver before context, context before D3D
    DestroyD3D();
    if (g.child) { DestroyWindow(g.child); g.child = nullptr; }
    {
        std::lock_guard<std::mutex> lock(g.evMutex);
        g.events.clear();
    }
    g.initialized = false;
}

SRB_API int32_t srb_IsInitialized(void) { return g.initialized ? 1 : 0; }
SRB_API int32_t srb_IsWeaving(void)     { return (g.initialized && g.weaver) ? 1 : 0; }

SRB_API int32_t srb_SetBounds(int32_t x, int32_t y, int32_t width, int32_t height)
{
    if (!g.initialized) return SRB_E_NOT_INITIALIZED;
    if (width < 1 || height < 1) { ShowWindow(g.child, SW_HIDE); return SRB_OK; }
    if (x != g.x || y != g.y || width != g.bbW || height != g.bbH || !IsWindowVisible(g.child) != !g.visible) {
        SetWindowPos(g.child, HWND_TOP, x, y, width, height,
                     SWP_NOACTIVATE | (g.visible ? SWP_SHOWWINDOW : SWP_HIDEWINDOW));
        g.x = x; g.y = y;
        if (width != g.bbW || height != g.bbH)
            if (!ResizeBackBuffer(width, height)) return Fail(SRB_E_D3D, "ResizeBuffers failed");
    }
    return SRB_OK;
}

SRB_API void srb_SetVisible(int32_t visible)
{
    g.visible = visible != 0;
    if (g.child) ShowWindow(g.child, g.visible ? SW_SHOWNA : SW_HIDE);
}

SRB_API int32_t srb_GetDisplayInfo(SRB_DisplayInfo* info)
{
    if (!info) return SRB_E_ARGS;
    if (!g.initialized || !g.display) return SRB_E_NOT_INITIALIZED;
    SRB_ENTRY;
    SRApi& a = g.api;
    try {
    info->resolutionWidth          = a.getResolutionWidth(g.display);
    info->resolutionHeight         = a.getResolutionHeight(g.display);
    info->physicalResolutionWidth  = a.getPhysicalResolutionWidth(g.display);
    info->physicalResolutionHeight = a.getPhysicalResolutionHeight(g.display);
    info->physicalWidthMM          = a.getPhysicalSizeWidth(g.display) * 10.0f;   // API returns cm
    info->physicalHeightMM         = a.getPhysicalSizeHeight(g.display) * 10.0f;
    info->recommendedViewWidth     = a.getRecommendedViewsTextureWidth(g.display);
    info->recommendedViewHeight    = a.getRecommendedViewsTextureHeight(g.display);
    } catch (...) { g.contextInvalid = true; return Fail(SRB_E_NO_DISPLAY, "SR display query failed"); }
    return SRB_OK;
}

SRB_API int32_t srb_GetWindowRectMM(double* centerX, double* centerY, double* width, double* height)
{
    if (!centerX || !centerY || !width || !height) return SRB_E_ARGS;
    if (!g.initialized || !g.display) return SRB_E_NOT_INITIALIZED;

    RECT wr{};
    GetWindowRect(g.child, &wr);
    MONITORINFO mi{ sizeof(mi) };
    GetMonitorInfoW(MonitorFromWindow(g.child, MONITOR_DEFAULTTONEAREST), &mi);
    const double monW = static_cast<double>(mi.rcMonitor.right - mi.rcMonitor.left);
    const double monH = static_cast<double>(mi.rcMonitor.bottom - mi.rcMonitor.top);
    if (monW <= 0 || monH <= 0) return SRB_E_ARGS;

    SRB_ENTRY;
    double mmPerPxX = 0, mmPerPxY = 0;
    try {
        mmPerPxX = g.api.getPhysicalSizeWidth(g.display)  * 10.0 / monW;
        mmPerPxY = g.api.getPhysicalSizeHeight(g.display) * 10.0 / monH;
    } catch (...) { g.contextInvalid = true; return Fail(SRB_E_NO_DISPLAY, "SR display query failed"); }
    if (mmPerPxX <= 0 || mmPerPxY <= 0) return SRB_E_NO_DISPLAY;

    const double monCx = (mi.rcMonitor.left + mi.rcMonitor.right) * 0.5;
    const double monCy = (mi.rcMonitor.top + mi.rcMonitor.bottom) * 0.5;
    const double winCx = (wr.left + wr.right) * 0.5;
    const double winCy = (wr.top + wr.bottom) * 0.5;

    *centerX = (winCx - monCx) * mmPerPxX;
    *centerY = -(winCy - monCy) * mmPerPxY;       // y up
    *width   = (wr.right - wr.left) * mmPerPxX;
    *height  = (wr.bottom - wr.top) * mmPerPxY;
    return SRB_OK;
}

SRB_API int32_t srb_GetEyePositions(float* left, float* right)
{
    if (!left || !right) return SRB_E_ARGS;
    if (g.initialized && g.weaver) {
        SRB_ENTRY;
        try {
            g.weaver->getPredictedEyePositions(left, right);
            return SRB_OK;
        } catch (...) { g.contextInvalid = true; }
    }
    // Default viewer: 63 mm IPD, 65 cm in front of the screen centre.
    left[0] = -31.5f; left[1] = 0.0f; left[2] = 650.0f;
    right[0] = 31.5f; right[1] = 0.0f; right[2] = 650.0f;
    return SRB_E_NOT_INITIALIZED;
}

SRB_API int32_t srb_SubmitViews(const void* pixels, int32_t viewWidth, int32_t viewHeight,
                                int32_t pitch, int32_t pixelFormat)
{
    if (!g.initialized) return SRB_E_NOT_INITIALIZED;
    if (!pixels || viewWidth < 1 || viewHeight < 1 || pitch < viewWidth * 8) return SRB_E_ARGS;
    SRB_ENTRY;
    const bool trace = g_submitTrace > 0;
    if (trace) { g_submitTrace--; BLog("submit: %d x %d per eye, pitch %d, format %d", viewWidth, viewHeight, pitch, pixelFormat); }
    try {

    // Recover from SR context loss (e.g. SR service restart), at most every 3 s
    // (each attempt may block briefly while connecting to the SR service).
    if (g.contextInvalid || !g.weaver) {
        ULONGLONG now = GetTickCount64();
        if (now - g.lastReinitTick > 3000) {
            g.lastReinitTick = now;
            BLog("re-creating SR (context invalid %d, weaver %p)", g.contextInvalid ? 1 : 0, (void*)g.weaver);
            TearDownSR();
            g.stats.reinitAttempts++;
            if (CreateSR(0.0) == SRB_OK)   // single non-blocking attempt; on failure we show 2D
                g.stats.reinitSuccesses++;
        }
    }

    if (!EnsureViewTexture(viewWidth, viewHeight, pixelFormat)) return Fail(SRB_E_D3D, "Could not create view texture");
    g.ctx->UpdateSubresource(g.sbsTex, 0, nullptr, pixels, static_cast<UINT>(pitch), 0);
    if (trace) BLog("submit: uploaded");

    if (g.weaver && g.weaverInputDirty) {
        BLog("setInputViewTexture(%p, %d, %d)", (void*)g.sbsSrv, viewWidth, viewHeight);
        g.weaver->setInputViewTexture(g.sbsSrv, viewWidth, viewHeight, ViewSrvFormat());
        g.weaverInputDirty = false;
    }

    if (!g.rtv) return Fail(SRB_E_D3D, "No render target");
    const float black[4] = { 0, 0, 0, 1 };
    g.ctx->OMSetRenderTargets(1, &g.rtv, nullptr);
    D3D11_VIEWPORT vp{ 0.0f, 0.0f, static_cast<float>(g.bbW), static_cast<float>(g.bbH), 0.0f, 1.0f };
    g.ctx->RSSetViewports(1, &vp);
    g.ctx->ClearRenderTargetView(g.rtv, black);

    if (g.weaver) {
        try { g.weaver->weave(); }
        catch (...) { g.contextInvalid = true; g.stats.exceptions++; BLog("exception in weave()"); }
        if (trace) BLog("submit: woven");
    } else {
        // 2D fallback: show the left view unwoven.
        ID3D11Texture2D* bb = nullptr;
        if (pixelFormat == SRB_FMT_BGRA8 &&
            SUCCEEDED(g.swap->GetBuffer(0, __uuidof(ID3D11Texture2D), reinterpret_cast<void**>(&bb)))) {
            D3D11_BOX box{ 0, 0, 0, static_cast<UINT>(std::min(viewWidth, g.bbW)), static_cast<UINT>(std::min(viewHeight, g.bbH)), 1 };
            g.ctx->CopySubresourceRegion(bb, 0, 0, 0, 0, g.sbsTex, 0, &box);
            bb->Release();
        }
    }

    HRESULT hr = g.swap->Present(g.vsync ? 1 : 0, 0);
    g.stats.framesSubmitted++;
    g.stats.lastPresentHr = static_cast<int32_t>(hr);
    if (trace) BLog("submit: presented, hr 0x%08X", static_cast<unsigned>(hr));
    if (hr == DXGI_ERROR_DEVICE_REMOVED || hr == DXGI_ERROR_DEVICE_RESET)
        return Fail(SRB_E_D3D, "D3D device removed - call srb_Finalize/srb_Initialize");
    if (hr == DXGI_STATUS_OCCLUDED) { g.stats.framesOccluded++; return SRB_S_OCCLUDED; }
    if (g.weaver) { g.stats.framesWoven++; return SRB_OK; }
    g.stats.frames2D++;
    return SRB_S_2D_FALLBACK;

    } catch (...) {
        g.contextInvalid = true;
        g.stats.exceptions++;
        BLog("exception in srb_SubmitViews");
        return Fail(SRB_S_2D_FALLBACK, "Exception during weaving; will re-create SR context");
    }
}

SRB_API void srb_SetVSync(int32_t enabled) { g.vsync = enabled ? 1 : 0; }

SRB_API void srb_SetLatencyInFrames(uint64_t frames)
{
    g.latencyFrames = frames;
    SRB_ENTRY;
    if (g.weaver && frames) { try { g.weaver->setLatencyInFrames(frames); } catch (...) {} }
}

SRB_API void srb_SetLens(int32_t enabled)
{
    g.lensOn = enabled != 0;
    SRB_ENTRY;
    if (g.lensHint) {
        try { if (g.lensOn) g.api.lensEnableHint(g.lensHint); else g.api.lensDisableHint(g.lensHint); } catch (...) {}
    }
}

SRB_API int32_t srb_PollSystemEvent(SRB_SystemEvent* ev)
{
    if (!ev) return 0;
    std::lock_guard<std::mutex> lock(g.evMutex);
    if (g.events.empty()) return 0;
    *ev = g.events.front();
    g.events.pop_front();
    return 1;
}

SRB_API const char* srb_GetLastError(void) { return g.lastError.c_str(); }

SRB_API const char* srb_GetPlatformVersion(void)
{
    SRB_ENTRY;
    if (!g.api.loaded && !LoadSRApi()) return "";
    if (g.api.getSRPlatformVersion) {
        try { const char* v = g.api.getSRPlatformVersion(); g.versionStr = v ? v : ""; } catch (...) {}
    }
    return g.versionStr.c_str();
}

SRB_API void srb_SetDllDirectory(const wchar_t* path)
{
    // Must be called before srb_Initialize; affects where the SR runtime DLLs are searched.
    SetDllDirectoryW(path);
}

SRB_API int32_t srb_GetStats(SRB_Stats* stats)
{
    if (!stats) return SRB_E_ARGS;
    *stats = g.stats;
    stats->backBufferWidth  = g.bbW;
    stats->backBufferHeight = g.bbH;
    stats->viewWidth        = g.texViewW;
    stats->viewHeight       = g.texViewH;
    stats->weaving          = g.weaver ? 1 : 0;
    stats->contextInvalid   = g.contextInvalid ? 1 : 0;
    if (g.weaver) {
        SRB_ENTRY;
        try { stats->weaverLatencyUs = g.weaver->getLatency(); } catch (...) {}
    }
    return SRB_OK;
}

SRB_API void srb_SetLogCallback(SRB_LogCallback callback)
{
    g_logCallback = callback;
    InstallFatalHandlers();
    BLog("log callback set");
}

/*
 * SRBridge.cpp - see SRBridge.h for the overview.
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
#include <d3d11_1.h>
#include <dxgi1_2.h>
#include <dwmapi.h>
#include <d3dcompiler.h>
#include <DirectXMath.h>

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
#include <vector>
#include <cmath>

#include "sr/types.h"
#include "sr/sense/system/systemevent.h"
#include "sr/weaver/dx11weaver.h"

#define SRBRIDGE_EXPORTS
#include "SRBridge.h"

#pragma comment(lib, "d3d11.lib")
#pragma comment(lib, "dxgi.lib")
#pragma comment(lib, "d3dcompiler.lib")
#pragma comment(lib, "dwmapi.lib")

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
    ID3D11ShaderResourceView* weaverInput = nullptr;   // the view texture the weaver was last given
    ID3D11Texture2D*        resolveTex = nullptr;      // single-sample copy of a multisampled eye (srb_CopyEyeTexture)

    // Another program's device (srb_SetExternalDevice, FMX's), and the
    // bridge's own pipeline state on it, swapped in around every call so
    // the bridge and the program never see each other's bindings.
    ID3D11Device*           extDev = nullptr;
    ID3D11DeviceContext1*   ctx1 = nullptr;
    ID3DDeviceContextState* ctxState = nullptr;
    bool                    eyeCopyLogged = false;

    // The program's own device, for the GPU check only (srb_SetProgramDevice)
    ID3D11Device*           progDev = nullptr;
    // The GPU driving the SR display, found before any device is made
    LUID                    srAdapterLuid{};
    bool                    srAdapterKnown = false;
    std::string             srAdapterName;
    bool                    sharedRefused = false;   // the program's device was not on the SR display's GPU

    // The SR display's DXGI output, for pacing frames to its refresh
    IDXGIOutput*            srOutput = nullptr;
    DWORD                   srRefreshHz = 0;
    bool                    paceLogged = false;

    // Window: the bridge's own child window over the viewport, which the
    // swap chain and weaver are on.
    HWND parent = nullptr, child = nullptr;
    bool ownChild = true;          // the bridge created `child` and destroys it
    int  x = 0, y = 0, bbW = 0, bbH = 0;
    bool visible = true;

    // Options
    int      vsync = 1;
    uint64_t latencyFrames = 0;   // 0 = leave weaver default
    bool     lensOn = true;
    bool     frameCap = true;     // with vsync, wait for the compositor after each Present (DwmFlush)
    LUID     adapterLuid{};       // the adapter the bridge's device is on
    std::string adapterName;

    // Events / errors
    std::mutex                  evMutex;
    std::deque<SRB_SystemEvent> events;
    std::string                 lastError;
    std::string                 versionStr;

    bool initialized = false;

    // Diagnostics (srb_GetStats)
    SRB_Stats stats{};

    // Where the SR display is on the desktop (physical pixels), see FindSRDisplayRect
    RECT displayRect{};
    bool displayRectValid = false;
    std::string displayRectSource;
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

// On a device shared with the program (srb_SetExternalDevice), swaps the
// bridge's own pipeline state in for the length of a call and the
// program's back afterwards. Does nothing on the bridge's own device.
struct CtxGuard {
    ID3DDeviceContextState* prev = nullptr;
    bool on = false;
    CtxGuard()
    {
        if (g.ctx1 && g.ctxState) { g.ctx1->SwapDeviceContextState(g.ctxState, &prev); on = true; }
    }
    ~CtxGuard()
    {
        if (on) { g.ctx1->SwapDeviceContextState(prev, nullptr); if (prev) prev->Release(); }
    }
    CtxGuard(const CtxGuard&) = delete;
    CtxGuard& operator=(const CtxGuard&) = delete;
};

// Releases the state block and the ID3D11DeviceContext1, after any guard has ended.
void ReleaseCtxState()
{
    SafeRelease(g.ctxState);
    SafeRelease(g.ctx1);
}

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
    if (g.srOutput) { g.srOutput->Release(); g.srOutput = nullptr; }
    g.paceLogged = false;
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

void FindSRDisplayRect();   // below, with the display search
void LogSRDisplayAdapter();  // below, with the adapter choice
int  CreateSRWeaver();

// First half of starting SR: context, display, events, lens hint, and
// where the display is and which GPU drives it. Needs no D3D device.
int CreateSRContext(double timeoutSeconds)
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
    FindSRDisplayRect();
    LogSRDisplayAdapter();
    return SRB_OK;
}

// Second half: the weaver on the bridge's device, then the context
// initialised. Requires D3D + the window.
int CreateSRWeaver()
{
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
    if (!g.displayRectValid) { FindSRDisplayRect(); LogSRDisplayAdapter(); }   // may only be known now
    return SRB_OK;
}

// Both halves (recovery after a context loss: the device already exists).
int CreateSR(double timeoutSeconds)
{
    int rc = CreateSRContext(timeoutSeconds);
    return rc == SRB_OK ? CreateSRWeaver() : rc;
}

// ---------------------------------------------------------------------------
// Finding the SR display on the desktop
// ---------------------------------------------------------------------------

// The C API has no getLocation, but SR::Display (sr/world/display/display.h)
// does. Its base, WorldObject, has no virtual functions, so SR::Display's
// vtable is exactly its own virtual functions in declaration order. This
// class declares the same functions in the same order, so calling through
// it calls the real ones, without including display.h (which pulls in
// OpenCV). The result is only trusted after getResolutionWidth through the
// mirror matches the C API's answer.
class DisplayMirror {
public:
    virtual ~DisplayMirror() = default;
    virtual const int getResolutionHeight() = 0;
    virtual const int getResolutionWidth() = 0;
    virtual const int getPhysicalResolutionHeight() = 0;
    virtual const int getPhysicalResolutionWidth() = 0;
    virtual const float getPhysicalSizeHeight() = 0;
    virtual const float getPhysicalSizeWidth() = 0;
    virtual const float getDotPitch() = 0;
    virtual SR_recti getLocation() = 0;
    virtual int getRecommendedViewsTextureWidth() = 0;
    virtual int getRecommendedViewsTextureHeight() = 0;
};

// Calls the mirror under SEH, so a wrong guess about the handle cannot crash.
bool MirrorLocation(void* display, int* resolutionWidth, SR_recti* location)
{
#ifdef _MSC_VER
    __try {
#endif
        DisplayMirror* m = static_cast<DisplayMirror*>(display);
        *resolutionWidth = m->getResolutionWidth();
        *location = m->getLocation();
        return true;
#ifdef _MSC_VER
    } __except (EXCEPTION_EXECUTE_HANDLER) {
        return false;
    }
#endif
}

struct MonitorSearch {
    int width = 0, height = 0;          // SR resolution, pixels
    double widthMM = 0, heightMM = 0;   // SR physical size
    double bestScore = 1e30;
    RECT best{};
    int candidates = 0;
};

BOOL CALLBACK MonitorSearchProc(HMONITOR mon, HDC, LPRECT, LPARAM param)
{
    MonitorSearch* ms = reinterpret_cast<MonitorSearch*>(param);
    MONITORINFOEXW mi{};
    mi.cbSize = sizeof(mi);
    if (!GetMonitorInfoW(mon, &mi)) return TRUE;
    const int w = mi.rcMonitor.right - mi.rcMonitor.left;
    const int h = mi.rcMonitor.bottom - mi.rcMonitor.top;
    double hmm = 0, vmm = 0;
    HDC dc = CreateDCW(L"DISPLAY", mi.szDevice, nullptr, nullptr);
    if (dc) { hmm = GetDeviceCaps(dc, HORZSIZE); vmm = GetDeviceCaps(dc, VERTSIZE); DeleteDC(dc); }
    BLog("monitor %ls at (%ld, %ld) %d x %d px, %.0f x %.0f mm", mi.szDevice,
         mi.rcMonitor.left, mi.rcMonitor.top, w, h, hmm, vmm);
    if (w != ms->width || h != ms->height) return TRUE;
    ms->candidates++;
    // Closest physical size wins; a monitor reporting no size scores badly but can still win
    const double score = (hmm > 0 && vmm > 0) ? std::abs(hmm - ms->widthMM) + std::abs(vmm - ms->heightMM) : 1e6;
    if (score < ms->bestScore) { ms->bestScore = score; ms->best = mi.rcMonitor; }
    return TRUE;
}

// Finds the SR display's rectangle on the desktop, first from SR itself, then
// by matching monitors' resolution and physical size. Logs what it found.
void FindSRDisplayRect()
{
    g.displayRectValid = false;
    if (!g.display) return;
    const int resW = g.api.getResolutionWidth(g.display);
    const int resH = g.api.getResolutionHeight(g.display);

    int mirrorW = 0;
    SR_recti loc{};
    if (MirrorLocation(g.display, &mirrorW, &loc) && mirrorW == resW &&
        loc.right - loc.left == resW && loc.bottom - loc.top == resH) {
        g.displayRect = { static_cast<LONG>(loc.left), static_cast<LONG>(loc.top),
                          static_cast<LONG>(loc.right), static_cast<LONG>(loc.bottom) };
        g.displayRectValid = true;
        g.displayRectSource = "SR::Display::getLocation";
    } else {
        BLog("SR::Display::getLocation not usable (mirror width %d, location %lld,%lld-%lld,%lld); matching monitors",
             mirrorW, loc.left, loc.top, loc.right, loc.bottom);
        MonitorSearch ms;
        ms.width = resW;
        ms.height = resH;
        ms.widthMM = g.api.getPhysicalSizeWidth(g.display) * 10.0;
        ms.heightMM = g.api.getPhysicalSizeHeight(g.display) * 10.0;
        EnumDisplayMonitors(nullptr, nullptr, MonitorSearchProc, reinterpret_cast<LPARAM>(&ms));
        if (ms.candidates > 0) {
            g.displayRect = ms.best;
            g.displayRectValid = true;
            g.displayRectSource = ms.candidates == 1 ? "monitor match (resolution)" :
                                                       "monitor match (resolution and size)";
        }
    }
    if (g.displayRectValid)
        BLog("SR display at (%ld, %ld)-(%ld, %ld), from %s", g.displayRect.left, g.displayRect.top,
             g.displayRect.right, g.displayRect.bottom, g.displayRectSource.c_str());
    else
        BLog("SR display position not found; using the monitor the window is on");
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
    static const wchar_t* kClass = L"SRBridgeChildWindow";
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
    rd.Format = DXGI_FORMAT_B8G8R8A8_UNORM_SRGB;     // the bitblt buffer is sRGB; on a UNORM flip-model buffer, an sRGB view
    rd.ViewDimension = D3D11_RTV_DIMENSION_TEXTURE2D;
    HRESULT hr = g.dev->CreateRenderTargetView(bb, &rd, &g.rtv);
    bb->Release();
    return SUCCEEDED(hr);
}

std::string Utf8(const wchar_t* w)
{
    char buf[512] = {};
    WideCharToMultiByte(CP_UTF8, 0, w, -1, buf, sizeof(buf) - 1, nullptr, nullptr);
    return buf;
}

// Logs every adapter and the monitors it drives, and picks one the way
// Leia's 1.36 DX11 sample does: not software, not Microsoft's basic adapter,
// the most dedicated video memory. With an integrated GPU beside a discrete
// one, the default adapter (nullptr) can be the integrated one. The GPU
// that drives the SR display, when known, comes first.
IDXGIAdapter1* ChooseAdapter()
{
    IDXGIFactory1* factory = nullptr;
    if (FAILED(CreateDXGIFactory1(__uuidof(IDXGIFactory1), reinterpret_cast<void**>(&factory)))) {
        BLog("CreateDXGIFactory1 failed; using the default adapter");
        return nullptr;
    }
    IDXGIAdapter1* best = nullptr;
    SIZE_T bestMem = 0;
    IDXGIAdapter1* a = nullptr;
    for (UINT i = 0; factory->EnumAdapters1(i, &a) != DXGI_ERROR_NOT_FOUND; ++i) {
        DXGI_ADAPTER_DESC1 d{};
        a->GetDesc1(&d);
        const bool software = (d.Flags & DXGI_ADAPTER_FLAG_SOFTWARE) != 0 || d.VendorId == 0x1414;
        std::string outs;
        IDXGIOutput* o = nullptr;
        for (UINT j = 0; a->EnumOutputs(j, &o) != DXGI_ERROR_NOT_FOUND; ++j) {
            DXGI_OUTPUT_DESC od{};
            o->GetDesc(&od);
            char tmp[160];
            snprintf(tmp, sizeof(tmp), "%s%s (%ld, %ld)-(%ld, %ld)", outs.empty() ? "" : ", ",
                     Utf8(od.DeviceName).c_str(), od.DesktopCoordinates.left, od.DesktopCoordinates.top,
                     od.DesktopCoordinates.right, od.DesktopCoordinates.bottom);
            outs += tmp;
            o->Release();
        }
        BLog("adapter %u: %s, vendor 0x%04X, %llu MB dedicated%s; monitors: %s", i,
             Utf8(d.Description).c_str(), d.VendorId,
             static_cast<unsigned long long>(d.DedicatedVideoMemory / (1024 * 1024)),
             software ? " (software, skipped)" : "", outs.empty() ? "none" : outs.c_str());
        if (!software && (best == nullptr || d.DedicatedVideoMemory > bestMem)) {
            if (best) best->Release();
            best = a;
            bestMem = d.DedicatedVideoMemory;
        } else {
            a->Release();
        }
    }
    factory->Release();
    if (g.srAdapterKnown) {
        // The GPU that drives the SR display, found before the device
        IDXGIFactory1* f2 = nullptr;
        IDXGIAdapter1* onSR = nullptr;
        if (SUCCEEDED(CreateDXGIFactory1(__uuidof(IDXGIFactory1), reinterpret_cast<void**>(&f2)))) {
            IDXGIAdapter1* c = nullptr;
            for (UINT i = 0; !onSR && f2->EnumAdapters1(i, &c) != DXGI_ERROR_NOT_FOUND; ++i) {
                DXGI_ADAPTER_DESC1 d{};
                c->GetDesc1(&d);
                if (d.AdapterLuid.LowPart == g.srAdapterLuid.LowPart && d.AdapterLuid.HighPart == g.srAdapterLuid.HighPart)
                    onSR = c;
                else
                    c->Release();
            }
            f2->Release();
        }
        if (onSR) {
            BLog("adapter choice: the one driving the SR display");
            if (best) best->Release();
            return onSR;
        }
    }
    return best;
}

// Says which adapter drives the SR display, and whether it is the bridge's.
void LogSRDisplayAdapter()
{
    if (!g.displayRectValid) return;
    IDXGIFactory1* factory = nullptr;
    if (FAILED(CreateDXGIFactory1(__uuidof(IDXGIFactory1), reinterpret_cast<void**>(&factory)))) return;
    IDXGIAdapter1* a = nullptr;
    bool found = false;
    for (UINT i = 0; !found && factory->EnumAdapters1(i, &a) != DXGI_ERROR_NOT_FOUND; ++i) {
        DXGI_ADAPTER_DESC1 d{};
        a->GetDesc1(&d);
        IDXGIOutput* o = nullptr;
        for (UINT j = 0; !found && a->EnumOutputs(j, &o) != DXGI_ERROR_NOT_FOUND; ++j) {
            DXGI_OUTPUT_DESC od{};
            o->GetDesc(&od);
            if (EqualRect(&od.DesktopCoordinates, &g.displayRect)) {
                found = true;
                const bool same = d.AdapterLuid.LowPart == g.adapterLuid.LowPart &&
                                  d.AdapterLuid.HighPart == g.adapterLuid.HighPart;
                g.srAdapterLuid = d.AdapterLuid;
                g.srAdapterKnown = true;
                g.srAdapterName = Utf8(d.Description);
                DEVMODEW dm{};
                dm.dmSize = sizeof(dm);
                g.srRefreshHz = EnumDisplaySettingsW(od.DeviceName, ENUM_CURRENT_SETTINGS, &dm) ? dm.dmDisplayFrequency : 0;
                BLog("SR display is driven by adapter %u (%s)%s; output %s at %lu Hz", i, Utf8(d.Description).c_str(),
                     !g.dev ? "" : same ? ": the same as the bridge's" : ": NOT the bridge's; frames cross between GPUs",
                     Utf8(od.DeviceName).c_str(), static_cast<unsigned long>(g.srRefreshHz));
                if (g.srOutput) g.srOutput->Release();
                g.srOutput = o;   // kept for pacing frames (WaitForVBlank)
                o = nullptr;
            }
            if (o) o->Release();
        }
        a->Release();
    }
    if (!found) BLog("no adapter output matches the SR display rectangle");
    factory->Release();
}

// The window's client area in screen pixels (the child has no frame, so for it
// this is its window rectangle).
RECT WeaverWindowScreenRect()
{
    RECT r{};
    GetClientRect(g.child, &r);
    POINT tl{ r.left, r.top }, br{ r.right, r.bottom };
    ClientToScreen(g.child, &tl);
    ClientToScreen(g.child, &br);
    return { tl.x, tl.y, br.x, br.y };
}

// Uses the program's device (FMX's): its immediate context, plus a state
// block of the bridge's own on it (needs D3D 11.1).
// The GPU a device is on: its LUID and name; false if it cannot be asked.
bool DeviceAdapter(ID3D11Device* dev, LUID& luid, std::string& name, UINT& vendor)
{
    IDXGIDevice* dxgiDev = nullptr;
    IDXGIAdapter* adapter = nullptr;
    bool ok = dev && SUCCEEDED(dev->QueryInterface(__uuidof(IDXGIDevice), reinterpret_cast<void**>(&dxgiDev))) &&
              SUCCEEDED(dxgiDev->GetAdapter(&adapter));
    if (ok) {
        DXGI_ADAPTER_DESC d{};
        adapter->GetDesc(&d);
        luid = d.AdapterLuid;
        name = Utf8(d.Description);
        vendor = d.VendorId;
    }
    SafeRelease(adapter); SafeRelease(dxgiDev);
    return ok;
}

bool SameLuid(const LUID& a, const LUID& b) { return a.LowPart == b.LowPart && a.HighPart == b.HighPart; }

bool UseExternalDevice()
{
    g.sharedRefused = false;
    LUID luid{};
    std::string name;
    UINT vendor = 0;
    if (g.srAdapterKnown && DeviceAdapter(g.extDev, luid, name, vendor) && !SameLuid(luid, g.srAdapterLuid)) {
        g.sharedRefused = true;
        BLog("WARNING: the program renders on %s, but the SR display is driven by %s. Not sharing its device: "
             "the bridge makes its own on %s, and each frame crosses between the GPUs (slow). Set the program to "
             "the SR display's GPU (Windows Settings > System > Display > Graphics).",
             name.c_str(), g.srAdapterName.c_str(), g.srAdapterName.c_str());
        return false;
    }
    g.dev = g.extDev;
    g.dev->AddRef();
    g.dev->GetImmediateContext(&g.ctx);
    IDXGIDevice* dxgiDev = nullptr;
    IDXGIAdapter* adapter = nullptr;
    if (SUCCEEDED(g.dev->QueryInterface(__uuidof(IDXGIDevice), reinterpret_cast<void**>(&dxgiDev))) &&
        SUCCEEDED(dxgiDev->GetAdapter(&adapter))) {
        DXGI_ADAPTER_DESC d{};
        adapter->GetDesc(&d);
        g.adapterLuid = d.AdapterLuid;
        g.adapterName = Utf8(d.Description);
    }
    SafeRelease(adapter); SafeRelease(dxgiDev);
    ID3D11Device1* dev1 = nullptr;
    HRESULT hr = g.dev->QueryInterface(__uuidof(ID3D11Device1), reinterpret_cast<void**>(&dev1));
    if (SUCCEEDED(hr)) hr = g.ctx->QueryInterface(__uuidof(ID3D11DeviceContext1), reinterpret_cast<void**>(&g.ctx1));
    if (SUCCEEDED(hr)) {
        const D3D_FEATURE_LEVEL fl = g.dev->GetFeatureLevel();
        hr = dev1->CreateDeviceContextState(0, &fl, 1, D3D11_SDK_VERSION, __uuidof(ID3D11Device1), nullptr, &g.ctxState);
    }
    SafeRelease(dev1);
    if (FAILED(hr)) {
        BLog("the program's device has no D3D 11.1 state blocks (hr 0x%08X); not sharing it", static_cast<unsigned>(hr));
        ReleaseCtxState();
        SafeRelease(g.ctx); SafeRelease(g.dev);
        return false;
    }
    BLog("D3D11 device: the program's own (%p) on %s, with a separate state block; views are copied on the GPU",
         (void*)g.dev, g.adapterName.c_str());
    return true;
}

bool CreateD3D()
{
    UINT flags = D3D11_CREATE_DEVICE_BGRA_SUPPORT;
    const D3D_FEATURE_LEVEL levels[] = { D3D_FEATURE_LEVEL_11_1, D3D_FEATURE_LEVEL_11_0 };
    HRESULT hr = E_FAIL;
    if (g.extDev && UseExternalDevice()) {
        hr = S_OK;
    } else {
        IDXGIAdapter1* chosen = ChooseAdapter();
        const D3D_DRIVER_TYPE type = chosen ? D3D_DRIVER_TYPE_UNKNOWN : D3D_DRIVER_TYPE_HARDWARE;
        hr = D3D11CreateDevice(chosen, type, nullptr, flags, levels, 2,
                               D3D11_SDK_VERSION, &g.dev, nullptr, &g.ctx);
        if (hr == E_INVALIDARG) // no 11_1 runtime
            hr = D3D11CreateDevice(chosen, type, nullptr, flags, levels + 1, 1,
                                   D3D11_SDK_VERSION, &g.dev, nullptr, &g.ctx);
        if (chosen) {
            DXGI_ADAPTER_DESC1 d{};
            chosen->GetDesc1(&d);
            g.adapterLuid = d.AdapterLuid;
            g.adapterName = Utf8(d.Description);
            chosen->Release();
        }
        if (FAILED(hr)) return false;
        BLog("D3D11 device on %s", g.adapterName.empty() ? "the default adapter" : g.adapterName.c_str());
    }

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
        sd.SampleDesc.Count = 1;
        sd.BufferUsage = DXGI_USAGE_RENDER_TARGET_OUTPUT;
        sd.Scaling = DXGI_SCALING_STRETCH;
        // Bitblt model, exactly as Leia's DX11 sample (1.34 and 1.36): one
        // sRGB buffer, DXGI_SWAP_EFFECT_DISCARD. Always composed by DWM,
        // never scanned out directly.
        sd.Format = DXGI_FORMAT_B8G8R8A8_UNORM_SRGB;
        sd.BufferCount = 1;
        sd.SwapEffect = DXGI_SWAP_EFFECT_DISCARD;
        sd.AlphaMode = DXGI_ALPHA_MODE_UNSPECIFIED;
        hr = factory->CreateSwapChainForHwnd(g.dev, g.child, &sd, nullptr, nullptr, &g.swap);
        ok = SUCCEEDED(hr);
        if (!ok) BLog("CreateSwapChainForHwnd failed, hr 0x%08X", static_cast<unsigned>(hr));
        if (ok) factory->MakeWindowAssociation(g.child, DXGI_MWA_NO_ALT_ENTER);
    }
    SafeRelease(factory); SafeRelease(adapter); SafeRelease(dxgiDev);
    return ok && CreateRTV();
}

void ReleaseScene();   // below, with the native scene

void DestroyD3D()
{
    ReleaseScene();
    if (g.ctx) { g.ctx->ClearState(); g.ctx->Flush(); }   // the bridge's state only, when sharing (under CtxGuard)
    SafeRelease(g.resolveTex);
    g.eyeCopyLogged = false;
    SafeRelease(g.sbsSrv); SafeRelease(g.sbsTex);
    SafeRelease(g.rtv); SafeRelease(g.swap);
    SafeRelease(g.ctx); SafeRelease(g.dev);
    g.texViewW = g.texViewH = 0; g.texFmt = -1;
    g.weaverInput = nullptr;
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

// The weaver window's rectangle on the SR display in millimetres, from the
// display centre, x right and y up (the eye tracker's frame).
int WindowRectMM(double& centerX, double& centerY, double& width, double& height)
{
    const RECT wr = WeaverWindowScreenRect();
    MONITORINFO mi{ sizeof(mi) };
    if (g.displayRectValid)
        mi.rcMonitor = g.displayRect;   // the SR panel, wherever the window is
    else
        GetMonitorInfoW(MonitorFromWindow(g.child, MONITOR_DEFAULTTONEAREST), &mi);
    const double monW = static_cast<double>(mi.rcMonitor.right - mi.rcMonitor.left);
    const double monH = static_cast<double>(mi.rcMonitor.bottom - mi.rcMonitor.top);
    if (monW <= 0 || monH <= 0) return SRB_E_ARGS;

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

    centerX = (winCx - monCx) * mmPerPxX;
    centerY = -(winCy - monCy) * mmPerPxY;       // y up
    width   = (wr.right - wr.left) * mmPerPxX;
    height  = (wr.bottom - wr.top) * mmPerPxY;
    return SRB_OK;
}

// Re-creates SR after a context loss (an SR service restart), at most every
// 3 s; each attempt may block briefly while connecting to the SR service.
void RecoverSR()
{
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
}

// Gives the weaver its input view texture when it has changed.
void SetWeaverInput(ID3D11ShaderResourceView* srv, int viewW, int viewH, DXGI_FORMAT fmt)
{
    if (!g.weaver) return;
    if (g.weaverInputDirty || g.weaverInput != srv) {
        BLog("setInputViewTexture(%p, %d, %d)", (void*)srv, viewW, viewH);
        g.weaver->setInputViewTexture(srv, viewW, viewH, fmt);
        g.weaverInputDirty = false;
        g.weaverInput = srv;
    }
}

// Weaves the current input into the back buffer (or, with no weaver, copies
// the left view unwoven) and presents.
int WeaveAndPresent(ID3D11Texture2D* src, int viewW, int viewH, bool canCopy2D, bool trace)
{
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
    } else if (canCopy2D) {
        // 2D fallback: show the left view unwoven.
        ID3D11Texture2D* bb = nullptr;
        if (SUCCEEDED(g.swap->GetBuffer(0, __uuidof(ID3D11Texture2D), reinterpret_cast<void**>(&bb)))) {
            D3D11_BOX box{ 0, 0, 0, static_cast<UINT>(std::min(viewW, g.bbW)), static_cast<UINT>(std::min(viewH, g.bbH)), 1 };
            g.ctx->CopySubresourceRegion(bb, 0, 0, 0, 0, src, 0, &box);
            bb->Release();
        }
    }

    HRESULT hr = g.swap->Present(g.vsync ? 1 : 0, 0);
    // A bitblt swap chain is composed by DWM, and Present does not wait for
    // the display: without this the GPU draws hundreds of frames a second
    // that are never seen. Wait for the SR display's own vertical blank;
    // DwmFlush (the compositor, which follows the fastest monitor, 240 Hz on
    // the owner's laptop) only if its output was not found.
    if (g.vsync && g.frameCap && SUCCEEDED(hr)) {
        if (!g.paceLogged) {
            g.paceLogged = true;
            if (g.srOutput)
                BLog("frame cap: one frame per vertical blank of the SR display (%lu Hz)", static_cast<unsigned long>(g.srRefreshHz));
            else
                BLog("frame cap: the SR display's output was not found; waiting for the compositor (DwmFlush)");
        }
        if (!g.srOutput || FAILED(g.srOutput->WaitForVBlank())) DwmFlush();
    }
    g.stats.framesSubmitted++;
    g.stats.lastPresentHr = static_cast<int32_t>(hr);
    if (trace) BLog("submit: presented, hr 0x%08X", static_cast<unsigned>(hr));
    if (hr == DXGI_ERROR_DEVICE_REMOVED || hr == DXGI_ERROR_DEVICE_RESET)
        return Fail(SRB_E_D3D, "D3D device removed - call srb_Finalize/srb_Initialize");
    if (hr == DXGI_STATUS_OCCLUDED) { g.stats.framesOccluded++; return SRB_S_OCCLUDED; }
    if (g.weaver) { g.stats.framesWoven++; return SRB_OK; }
    g.stats.frames2D++;
    return SRB_S_2D_FALLBACK;
}

// ---------------------------------------------------------------------------
// The native scene (srb_RenderScene): drawn by the bridge straight into a
// side-by-side view texture, one off-axis projection per eye, then woven.
// No copy through the CPU. Units are millimetres in the eye tracker's frame
// (display centre, x right, y up, z towards the viewer; the glass is z = 0).
// ---------------------------------------------------------------------------
using namespace DirectX;

struct SceneVertex { float px, py, pz, nx, ny, nz; };

struct SceneCB {
    XMFLOAT4X4 world;
    XMFLOAT4X4 viewProj;
    XMFLOAT4   color;
    XMFLOAT4   lightDir;   // xyz: the direction the light travels; w: ambient
    XMFLOAT4   eyePos;
};

struct Scene {
    bool tried = false, ready = false;
    ID3D11VertexShader* vs = nullptr;
    ID3D11PixelShader* ps = nullptr;
    ID3D11InputLayout* layout = nullptr;
    ID3D11Buffer* cb = nullptr;
    ID3D11RasterizerState* rs = nullptr;
    ID3D11Buffer* cubeVB = nullptr;   UINT cubeCount = 0;
    ID3D11Buffer* quadVB = nullptr;   UINT quadCount = 0;
    ID3D11Buffer* sphereVB = nullptr; ID3D11Buffer* sphereIB = nullptr; UINT sphereIndexCount = 0;
    // Targets: both eyes side by side, and a depth buffer
    ID3D11Texture2D* tex = nullptr;
    ID3D11RenderTargetView* rtv = nullptr;
    ID3D11ShaderResourceView* srv = nullptr;
    ID3D11Texture2D* depth = nullptr;
    ID3D11DepthStencilView* dsv = nullptr;
    int viewW = 0, viewH = 0;
};
Scene gs;

const char kSceneHlsl[] = R"(
cbuffer CB : register(b0) {
    row_major float4x4 World;
    row_major float4x4 ViewProj;
    float4 Color;
    float4 LightDir;
    float4 EyePos;
};
struct VSIn  { float3 pos : POSITION; float3 nrm : NORMAL; };
struct VSOut { float4 pos : SV_Position; float3 nrm : NORMAL; float3 wpos : TEXCOORD0; };
VSOut VS(VSIn i) {
    VSOut o;
    float4 w = mul(float4(i.pos, 1), World);
    o.wpos = w.xyz;
    o.pos = mul(w, ViewProj);
    o.nrm = mul(float4(i.nrm, 0), World).xyz;
    return o;
}
float4 PS(VSOut i) : SV_Target {
    float3 n = normalize(i.nrm);
    float3 l = normalize(-LightDir.xyz);
    float3 v = normalize(EyePos.xyz - i.wpos);
    if (dot(n, v) < 0) n = -n;   // two-sided
    float d = saturate(dot(n, l));
    float s = pow(saturate(dot(n, normalize(l + v))), 32) * 0.35;
    return float4(Color.rgb * (LightDir.w + (1 - LightDir.w) * d) + s, 1);
}
)";

void ReleaseSceneTargets()
{
    SafeRelease(gs.dsv); SafeRelease(gs.depth);
    SafeRelease(gs.srv); SafeRelease(gs.rtv); SafeRelease(gs.tex);
    gs.viewW = gs.viewH = 0;
}

void ReleaseScene()
{
    ReleaseSceneTargets();
    SafeRelease(gs.sphereIB); SafeRelease(gs.sphereVB); SafeRelease(gs.quadVB); SafeRelease(gs.cubeVB);
    SafeRelease(gs.rs); SafeRelease(gs.cb); SafeRelease(gs.layout); SafeRelease(gs.ps); SafeRelease(gs.vs);
    gs.tried = gs.ready = false;
}

ID3D11Buffer* MakeBuffer(const void* data, UINT bytes, UINT bind)
{
    D3D11_BUFFER_DESC bd{};
    bd.ByteWidth = bytes;
    bd.Usage = D3D11_USAGE_IMMUTABLE;
    bd.BindFlags = bind;
    D3D11_SUBRESOURCE_DATA sd{ data, 0, 0 };
    ID3D11Buffer* b = nullptr;
    return SUCCEEDED(g.dev->CreateBuffer(&bd, &sd, &b)) ? b : nullptr;
}

ID3DBlob* CompileScene(const char* entry, const char* target)
{
    ID3DBlob* code = nullptr;
    ID3DBlob* errors = nullptr;
    HRESULT hr = D3DCompile(kSceneHlsl, sizeof(kSceneHlsl) - 1, "scene", nullptr, nullptr, entry, target,
                            D3DCOMPILE_OPTIMIZATION_LEVEL3, 0, &code, &errors);
    if (FAILED(hr))
        BLog("scene shader %s failed to compile, hr 0x%08X: %s", entry, static_cast<unsigned>(hr),
             errors ? static_cast<const char*>(errors->GetBufferPointer()) : "no message");
    SafeRelease(errors);
    return SUCCEEDED(hr) ? code : nullptr;
}

// Shaders, constant buffer and meshes, made once per device.
bool EnsureSceneResources()
{
    if (gs.ready) return true;
    if (gs.tried) return false;   // failed before; logged then
    gs.tried = true;

    ID3DBlob* vsCode = CompileScene("VS", "vs_4_0");
    ID3DBlob* psCode = CompileScene("PS", "ps_4_0");
    bool ok = vsCode && psCode
        && SUCCEEDED(g.dev->CreateVertexShader(vsCode->GetBufferPointer(), vsCode->GetBufferSize(), nullptr, &gs.vs))
        && SUCCEEDED(g.dev->CreatePixelShader(psCode->GetBufferPointer(), psCode->GetBufferSize(), nullptr, &gs.ps));
    if (ok) {
        const D3D11_INPUT_ELEMENT_DESC ied[] = {
            { "POSITION", 0, DXGI_FORMAT_R32G32B32_FLOAT, 0, 0,  D3D11_INPUT_PER_VERTEX_DATA, 0 },
            { "NORMAL",   0, DXGI_FORMAT_R32G32B32_FLOAT, 0, 12, D3D11_INPUT_PER_VERTEX_DATA, 0 },
        };
        ok = SUCCEEDED(g.dev->CreateInputLayout(ied, 2, vsCode->GetBufferPointer(), vsCode->GetBufferSize(), &gs.layout));
    }
    SafeRelease(vsCode); SafeRelease(psCode);
    if (!ok) { BLog("scene: shaders could not be created"); ReleaseScene(); gs.tried = true; return false; }

    D3D11_BUFFER_DESC cbd{};
    cbd.ByteWidth = sizeof(SceneCB);
    cbd.Usage = D3D11_USAGE_DYNAMIC;
    cbd.BindFlags = D3D11_BIND_CONSTANT_BUFFER;
    cbd.CPUAccessFlags = D3D11_CPU_ACCESS_WRITE;
    D3D11_RASTERIZER_DESC rd{};
    rd.FillMode = D3D11_FILL_SOLID;
    rd.CullMode = D3D11_CULL_NONE;    // winding does not matter; the depth buffer sorts it out
    rd.DepthClipEnable = TRUE;
    ok = SUCCEEDED(g.dev->CreateBuffer(&cbd, nullptr, &gs.cb)) && SUCCEEDED(g.dev->CreateRasterizerState(&rd, &gs.rs));

    // Cube: unit size, 6 faces of 2 triangles
    std::vector<SceneVertex> cube;
    const float n6[6][3] = { {1,0,0}, {-1,0,0}, {0,1,0}, {0,-1,0}, {0,0,1}, {0,0,-1} };
    for (auto& n : n6) {
        XMVECTOR N = XMVectorSet(n[0], n[1], n[2], 0);
        XMVECTOR U = std::abs(n[1]) > 0.5f ? XMVectorSet(1, 0, 0, 0) : XMVectorSet(0, 1, 0, 0);
        XMVECTOR V = XMVector3Cross(N, U);
        XMVECTOR C = N * 0.5f;
        XMVECTOR q[4] = { C - U * 0.5f - V * 0.5f, C + U * 0.5f - V * 0.5f, C + U * 0.5f + V * 0.5f, C - U * 0.5f + V * 0.5f };
        const int idx[6] = { 0, 1, 2, 0, 2, 3 };
        for (int i : idx) {
            XMFLOAT3 p; XMStoreFloat3(&p, q[i]);
            cube.push_back({ p.x, p.y, p.z, n[0], n[1], n[2] });
        }
    }
    // Quad: unit square in the xy plane, facing +z
    const SceneVertex quad[6] = {
        { -0.5f, -0.5f, 0, 0, 0, 1 }, { 0.5f, -0.5f, 0, 0, 0, 1 }, { 0.5f, 0.5f, 0, 0, 0, 1 },
        { -0.5f, -0.5f, 0, 0, 0, 1 }, { 0.5f, 0.5f, 0, 0, 0, 1 }, { -0.5f, 0.5f, 0, 0, 0, 1 } };
    // Sphere: unit radius
    std::vector<SceneVertex> sv;
    std::vector<uint16_t> si;
    const int stacks = 24, slices = 40;
    for (int i = 0; i <= stacks; ++i) {
        const float phi = XM_PI * i / stacks;
        for (int j = 0; j <= slices; ++j) {
            const float th = XM_2PI * j / slices;
            const float x = std::sin(phi) * std::cos(th), y = std::cos(phi), z = std::sin(phi) * std::sin(th);
            sv.push_back({ x, y, z, x, y, z });
        }
    }
    for (int i = 0; i < stacks; ++i)
        for (int j = 0; j < slices; ++j) {
            const uint16_t a = static_cast<uint16_t>(i * (slices + 1) + j), b = static_cast<uint16_t>(a + slices + 1);
            const uint16_t t[6] = { a, b, static_cast<uint16_t>(a + 1), static_cast<uint16_t>(a + 1), b, static_cast<uint16_t>(b + 1) };
            si.insert(si.end(), t, t + 6);
        }
    if (ok) {
        gs.cubeVB = MakeBuffer(cube.data(), static_cast<UINT>(cube.size() * sizeof(SceneVertex)), D3D11_BIND_VERTEX_BUFFER);
        gs.cubeCount = static_cast<UINT>(cube.size());
        gs.quadVB = MakeBuffer(quad, sizeof(quad), D3D11_BIND_VERTEX_BUFFER);
        gs.quadCount = 6;
        gs.sphereVB = MakeBuffer(sv.data(), static_cast<UINT>(sv.size() * sizeof(SceneVertex)), D3D11_BIND_VERTEX_BUFFER);
        gs.sphereIB = MakeBuffer(si.data(), static_cast<UINT>(si.size() * sizeof(uint16_t)), D3D11_BIND_INDEX_BUFFER);
        gs.sphereIndexCount = static_cast<UINT>(si.size());
        ok = gs.cubeVB && gs.quadVB && gs.sphereVB && gs.sphereIB;
    }
    if (!ok) { BLog("scene: buffers could not be created"); ReleaseScene(); gs.tried = true; return false; }
    gs.ready = true;
    BLog("scene ready: shaders compiled, %u cube, %u sphere vertices", gs.cubeCount, static_cast<unsigned>(sv.size()));
    return true;
}

// The side-by-side colour target and its depth buffer, at the view size.
bool EnsureSceneTargets(int viewW, int viewH)
{
    if (gs.tex && gs.viewW == viewW && gs.viewH == viewH) return true;
    ReleaseSceneTargets();
    D3D11_TEXTURE2D_DESC td{};
    td.Width = static_cast<UINT>(viewW * 2);
    td.Height = static_cast<UINT>(viewH);
    td.MipLevels = 1;
    td.ArraySize = 1;
    td.Format = DXGI_FORMAT_B8G8R8A8_TYPELESS;
    td.SampleDesc.Count = 1;
    td.Usage = D3D11_USAGE_DEFAULT;
    td.BindFlags = D3D11_BIND_RENDER_TARGET | D3D11_BIND_SHADER_RESOURCE;
    D3D11_RENDER_TARGET_VIEW_DESC rvd{};
    rvd.Format = DXGI_FORMAT_B8G8R8A8_UNORM_SRGB;
    rvd.ViewDimension = D3D11_RTV_DIMENSION_TEXTURE2D;
    D3D11_SHADER_RESOURCE_VIEW_DESC svd{};
    svd.Format = DXGI_FORMAT_B8G8R8A8_UNORM_SRGB;
    svd.ViewDimension = D3D11_SRV_DIMENSION_TEXTURE2D;
    svd.Texture2D.MipLevels = 1;
    D3D11_TEXTURE2D_DESC dd = td;
    dd.Format = DXGI_FORMAT_D24_UNORM_S8_UINT;
    dd.BindFlags = D3D11_BIND_DEPTH_STENCIL;
    const bool ok = SUCCEEDED(g.dev->CreateTexture2D(&td, nullptr, &gs.tex))
        && SUCCEEDED(g.dev->CreateRenderTargetView(gs.tex, &rvd, &gs.rtv))
        && SUCCEEDED(g.dev->CreateShaderResourceView(gs.tex, &svd, &gs.srv))
        && SUCCEEDED(g.dev->CreateTexture2D(&dd, nullptr, &gs.depth))
        && SUCCEEDED(g.dev->CreateDepthStencilView(gs.depth, nullptr, &gs.dsv));
    if (!ok) { ReleaseSceneTargets(); return false; }
    gs.viewW = viewW;
    gs.viewH = viewH;
    g.weaverInputDirty = true;
    BLog("scene targets %d x %d per eye", viewW, viewH);
    return true;
}

// The eyes to draw from, after the caller's options; fills the info.
void SceneEyes(const SRB_SceneParams& p, SRB_SceneInfo& info, XMVECTOR& el, XMVECTOR& er)
{
    double cx = 0, cy = 0, ww = 600, wh = 340;
    WindowRectMM(cx, cy, ww, wh);
    info.windowCenterX = static_cast<float>(cx);
    info.windowCenterY = static_cast<float>(cy);
    info.windowWidth = static_cast<float>(ww);
    info.windowHeight = static_cast<float>(wh);

    float L[3] = { 0, 0, 0 }, R[3] = { 0, 0, 0 };
    bool got = false;
    if (g.weaver) {
        try { g.weaver->getPredictedEyePositions(L, R); got = true; }
        catch (...) { g.contextInvalid = true; }
    }
    // Before the tracker locks on it reports both eyes at one point (0, 100, 600)
    info.nominalEyes = (!got || L[2] < 100.0f || R[2] < 100.0f) ? 1 : 0;
    if (info.nominalEyes) {
        L[0] = static_cast<float>(cx) - 31.5f; L[1] = static_cast<float>(cy); L[2] = 650.0f;
        R[0] = static_cast<float>(cx) + 31.5f; R[1] = static_cast<float>(cy); R[2] = 650.0f;
    }
    el = XMVectorSet(L[0], L[1], L[2], 0);
    er = XMVectorSet(R[0], R[1], R[2], 0);
    XMVECTOR mid = (el + er) * 0.5f;
    float sep = XMVectorGetX(XMVector3Length(er - el));
    XMVECTOR dir = sep > 1.0f ? (er - el) / sep : XMVectorSet(1, 0, 0, 0);
    info.separationRebuilt = (sep < 45.0f || sep > 85.0f) ? 1 : 0;
    if (info.separationRebuilt) sep = 63.0f;
    if (p.eyeSeparationMM > 0) sep = p.eyeSeparationMM;
    if (p.depthScale > 0) sep *= p.depthScale;
    if (!p.lookAround) {
        mid = XMVectorSet(static_cast<float>(cx), static_cast<float>(cy), 650.0f, 0);
        dir = XMVectorSet(1, 0, 0, 0);
    }
    if (p.flat) sep = 0;
    el = mid - dir * (sep * 0.5f);
    er = mid + dir * (sep * 0.5f);
    XMStoreFloat3(reinterpret_cast<XMFLOAT3*>(info.leftEye), el);
    XMStoreFloat3(reinterpret_cast<XMFLOAT3*>(info.rightEye), er);
}

void DrawSceneMesh(const XMMATRIX& world, XMFLOAT4 color, const XMMATRIX& viewProj, FXMVECTOR eye,
                   ID3D11Buffer* vb, ID3D11Buffer* ib, UINT count)
{
    D3D11_MAPPED_SUBRESOURCE m{};
    if (FAILED(g.ctx->Map(gs.cb, 0, D3D11_MAP_WRITE_DISCARD, 0, &m))) return;
    SceneCB* c = static_cast<SceneCB*>(m.pData);
    XMStoreFloat4x4(&c->world, world);
    XMStoreFloat4x4(&c->viewProj, viewProj);
    c->color = color;
    XMStoreFloat4(&c->lightDir, XMVector3Normalize(XMVectorSet(-0.35f, -0.55f, -0.75f, 0)));
    c->lightDir.w = 0.3f;
    XMStoreFloat4(&c->eyePos, eye);
    g.ctx->Unmap(gs.cb, 0);
    const UINT stride = sizeof(SceneVertex), offset = 0;
    g.ctx->IASetVertexBuffers(0, 1, &vb, &stride, &offset);
    if (ib) {
        g.ctx->IASetIndexBuffer(ib, DXGI_FORMAT_R16_UINT, 0);
        g.ctx->DrawIndexed(count, 0, 0);
    } else {
        g.ctx->Draw(count, 0);
    }
}

// SRDemoFMX's scene, in FMX's world units: the viewport is this many units
// high on the glass (FMX's camera 20 units back, 45 degree field of view).
const float kWorldViewHeight = 16.5685f;

// Colours as SRDemoFMX's (TAlphaColors), 0..1.
XMFLOAT4 Rgb(unsigned rgb)
{
    return { ((rgb >> 16) & 0xFF) / 255.0f, ((rgb >> 8) & 0xFF) / 255.0f, (rgb & 0xFF) / 255.0f, 1.0f };
}

// One digit of the frame rate as seven flat bars, top left at (x0, y0) in
// world units (y down), on the glass.
void DrawDigit(int digit, float x0, float y0, float w, float h, float t, const XMMATRIX& toMM,
               const XMMATRIX& viewProj, FXMVECTOR eye)
{
    // Segments a (top), b, c (right, top and bottom), d (bottom), e, f (left,
    // bottom and top), g (middle)
    static const unsigned char kSegments[10] = { 0x3F, 0x06, 0x5B, 0x4F, 0x66, 0x6D, 0x7D, 0x07, 0x7F, 0x6F };
    struct Bar { float x, y, sx, sy; };
    const Bar bars[7] = {
        { x0 + w / 2, y0,             w, t },       // a
        { x0 + w,     y0 + h / 4,     t, h / 2 },   // b
        { x0 + w,     y0 + 3 * h / 4, t, h / 2 },   // c
        { x0 + w / 2, y0 + h,         w, t },       // d
        { x0,         y0 + 3 * h / 4, t, h / 2 },   // e
        { x0,         y0 + h / 4,     t, h / 2 },   // f
        { x0 + w / 2, y0 + h / 2,     w, t },       // g
    };
    if (digit < 0 || digit > 9) return;
    for (int s = 0; s < 7; ++s)
        if (kSegments[digit] & (1u << s))
            DrawSceneMesh(XMMatrixScaling(bars[s].sx, bars[s].sy, 0.02f) * XMMatrixTranslation(bars[s].x, bars[s].y, -0.01f) * toMM,
                          { 1, 1, 1, 1 }, viewProj, eye, gs.cubeVB, nullptr, gs.cubeCount);
}

// Draws both eyes into the side-by-side target: SRDemoFMX's scene (see
// SRB_SceneParams), converted from FMX's world units to millimetres.
void RenderSceneViews(const SRB_SceneParams& p, const SRB_SceneInfo& info, FXMVECTOR el, FXMVECTOR er)
{
    ID3D11DeviceContext* c = g.ctx;
    const XMFLOAT4 bgc = Rgb(0x101828);
    const float bg[4] = { bgc.x, bgc.y, bgc.z, 1.0f };
    c->OMSetRenderTargets(1, &gs.rtv, gs.dsv);
    c->ClearRenderTargetView(gs.rtv, bg);
    c->ClearDepthStencilView(gs.dsv, D3D11_CLEAR_DEPTH, 1.0f, 0);
    c->IASetInputLayout(gs.layout);
    c->IASetPrimitiveTopology(D3D11_PRIMITIVE_TOPOLOGY_TRIANGLELIST);
    c->VSSetShader(gs.vs, nullptr, 0);
    c->PSSetShader(gs.ps, nullptr, 0);
    c->VSSetConstantBuffers(0, 1, &gs.cb);
    c->PSSetConstantBuffers(0, 1, &gs.cb);
    c->RSSetState(gs.rs);
    c->OMSetDepthStencilState(nullptr, 0);
    c->OMSetBlendState(nullptr, nullptr, 0xFFFFFFFF);

    const float cx = info.windowCenterX, cy = info.windowCenterY;
    const float ww = info.windowWidth, wh = info.windowHeight;
    // World units (x right, y down, z away) to mm (x right, y up, z towards
    // the viewer), the world origin at the window's centre on the glass
    const float U = wh / kWorldViewHeight;
    const XMMATRIX toMM = XMMatrixScaling(U, -U, -U) * XMMatrixTranslation(cx, cy, 0);
    // The whole scene turned about the main sphere and moved in depth; the
    // grid turned about its vertical axis as well
    const XMMATRIX sceneM = XMMatrixRotationX(XMConvertToRadians(p.tiltDeg)) *
                            XMMatrixRotationZ(XMConvertToRadians(p.rollDeg)) *
                            XMMatrixTranslation(0, 0, p.sceneZ) * toMM;
    const XMMATRIX gridM = XMMatrixRotationY(XMConvertToRadians(p.gridSpinDeg)) * sceneM;

    const int half = 5;
    const float step = 3.0f, radius = 0.7f, cubeY = 4.5f, cubeGap = 4.5f;
    // One colour per depth, nearest the viewer first (z = -15 .. 15)
    static const unsigned kDepthColours[11] = { 0xFF0000, 0xFF4500, 0xFF8C00, 0xFFA500, 0xFFFF00, 0xFFFFFF,
                                                0x87CEFA, 0x00BFFF, 0x1E90FF, 0x4169E1, 0x0000CD };
    const XMFLOAT4 mainColour = Rgb(0x32CD32), cubeColour = Rgb(0xE8A33D), wallColour = Rgb(0x35507A);

    for (int eye = 0; eye < 2; ++eye) {
        D3D11_VIEWPORT vp{ static_cast<float>(eye * gs.viewW), 0.0f, static_cast<float>(gs.viewW),
                           static_cast<float>(gs.viewH), 0.0f, 1.0f };
        c->RSSetViewports(1, &vp);
        XMVECTOR E = eye == 0 ? el : er;
        const float ex = XMVectorGetX(E), ey = XMVectorGetY(E), ez = std::max(XMVectorGetZ(E), 50.0f);
        const float n = 10.0f, f = ez + 5000.0f;
        // Off-axis frustum through the window's edges, seen from this eye
        const float l = (cx - ww * 0.5f - ex) * n / ez, r = (cx + ww * 0.5f - ex) * n / ez;
        const float b = (cy - wh * 0.5f - ey) * n / ez, t = (cy + wh * 0.5f - ey) * n / ez;
        const XMMATRIX viewProj = XMMatrixTranslation(-ex, -ey, -ez) * XMMatrixPerspectiveOffCenterRH(l, r, b, t, n, f);
        const XMVECTOR eyePos = XMVectorSet(ex, ey, ez, 1);

        // Back wall, behind the furthest spheres
        DrawSceneMesh(XMMatrixScaling(60, 40, 1) * XMMatrixTranslation(0, 0, (half + 1) * step) * sceneM,
                      wallColour, viewProj, eyePos, gs.quadVB, nullptr, gs.quadCount);
        // Two columns of three cubes, above and below the grid, turning
        for (int k = 0; k < 6; ++k) {
            const float y = (k < 3 ? -1.0f : 1.0f) * (cubeY + (k % 3) * cubeGap);
            DrawSceneMesh(XMMatrixScaling(3, 3, 3) * XMMatrixRotationY(p.rotation) * XMMatrixTranslation(0, y, 0) * sceneM,
                          cubeColour, viewProj, eyePos, gs.cubeVB, nullptr, gs.cubeCount);
        }
        // The grid of spheres, one colour per depth, the main sphere green
        for (int j = -half; j <= half; ++j)
            for (int i = -half; i <= half; ++i)
                DrawSceneMesh(XMMatrixScaling(radius, radius, radius) * XMMatrixTranslation(i * step, 0, j * step) * gridM,
                              (i == 0 && j == 0) ? mainColour : Rgb(kDepthColours[j + half]),
                              viewProj, eyePos, gs.sphereVB, gs.sphereIB, gs.sphereIndexCount);
        // The frame rate, on the glass at the top left (not moved with the
        // scene): a dark panel and digits
        if (p.fps >= 0) {
            DrawSceneMesh(XMMatrixScaling(3, 1, 1) * XMMatrixTranslation(-12, -7, 0.02f) * toMM,
                          Rgb(0x202838), viewProj, eyePos, gs.quadVB, nullptr, gs.quadCount);
            char digits[8];
            const int count = std::snprintf(digits, sizeof(digits), "%d", std::min(p.fps, 999));
            const float dw = 0.36f, dh = 0.6f, dt = 0.08f, gap = 0.18f;
            const float total = count * dw + (count - 1) * gap;
            float x = -12 - total / 2;
            for (int d = 0; d < count; ++d, x += dw + gap)
                DrawDigit(digits[d] - '0', x, -7 - dh / 2, dw, dh, dt, toMM, viewProj, eyePos);
        }
    }
    c->OMSetRenderTargets(0, nullptr, nullptr);
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
    g.ownChild = true;
    if (!CreateChildWindow(parent)) return Fail(SRB_E_WINDOW, "Could not create child window");
    auto dropWindow = []() { if (g.ownChild && g.child) DestroyWindow(g.child); g.child = nullptr; };
    // SR first: which GPU drives the display decides the device
    int rcCtx = CreateSRContext(timeoutSeconds);
    if (rcCtx != SRB_OK) { dropWindow(); return rcCtx; }
    if (!CreateD3D()) {
        TearDownSR();
        { CtxGuard guard; DestroyD3D(); }   // on a shared device, clear only the bridge's state
        ReleaseCtxState();
        dropWindow();
        return Fail(SRB_E_D3D, "Direct3D 11 initialisation failed");
    }
    int rc = SRB_OK;
    {
    CtxGuard guard;

    BLog("child window %p, %d x %d, D3D device %p, swap chain %p (bitblt model, DISCARD, as Leia's samples)",
         (void*)g.child, g.bbW, g.bbH, (void*)g.dev, (void*)g.swap);
    LogSRDisplayAdapter();   // now with the device, says whether they match
    rc = CreateSRWeaver();
    if (rc != SRB_OK) DestroyD3D();
    }
    if (rc != SRB_OK) { ReleaseCtxState(); dropWindow(); return rc; }

    g.initialized = true;
    BLog("srb_Initialize done");
    return SRB_OK;
}

SRB_API int32_t srb_Probe(int32_t timeoutMs)
{
    SRB_ENTRY;
    if (g.initialized) return SRB_OK;
    const ULONGLONG start = GetTickCount64();
    const ULONGLONG limit = static_cast<ULONGLONG>(std::max<int32_t>(0, timeoutMs));
    BLog("probe: checking for SR (up to %llu ms)", limit);
    if (!LoadSRApi()) { BLog("probe: %s", g.lastError.c_str()); return SRB_E_SR_DLL_MISSING; }
    // The context throws while the service is starting: keep trying
    void* ctx = nullptr;
    for (;;) {
        try { ctx = g.api.newSRContext(); } catch (...) { ctx = nullptr; }
        if (ctx || GetTickCount64() - start > limit) break;
        Sleep(100);
    }
    if (!ctx) {
        BLog("probe: no SR context after %llu ms", GetTickCount64() - start);
        return Fail(SRB_E_NO_SERVICE, "The SR service is not running (no SR context could be created)");
    }
    // A plugged-in display has been ready at the first query in every log
    // so far
    bool ready = false;
    int w = 0, h = 0;
    for (;;) {
        try {
            void* d = g.api.createDisplay(ctx);   // owned by the context
            if (d) {
                w = g.api.getResolutionWidth(d);
                h = g.api.getResolutionHeight(d);
                ready = w > 0 && g.api.getPhysicalSizeWidth(d) > 0.0f;
            }
        } catch (...) { ready = false; }
        if (ready || GetTickCount64() - start > limit) break;
        Sleep(100);
    }
    try { g.api.deleteSRContext(ctx); } catch (...) { BLog("probe: exception deleting the SR context"); }
    BLog("probe: SR context created, display %s (%d x %d) after %llu ms",
         ready ? "ready" : "NOT ready", w, h, GetTickCount64() - start);
    if (!ready)
        return Fail(SRB_E_NO_DISPLAY, "No SR display was found (cable and USB connected? display on, "
                                      "in extended mode at its native resolution?)");
    return SRB_OK;
}

SRB_API void srb_Finalize(void)
{
    SRB_ENTRY;
    BLog("srb_Finalize");
    {
        CtxGuard guard;
        try { TearDownSR(); } catch (...) { g.weaver = nullptr; g.srContext = nullptr; }          // weaver before context, context before D3D
        DestroyD3D();
    }
    ReleaseCtxState();
    if (g.child && g.ownChild) DestroyWindow(g.child);
    g.child = nullptr;
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
    CtxGuard guard;
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
    if (g.child && g.ownChild) ShowWindow(g.child, g.visible ? SW_SHOWNA : SW_HIDE);
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
    SRB_ENTRY;
    return WindowRectMM(*centerX, *centerY, *width, *height);
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
    CtxGuard guard;
    try {
    RecoverSR();
    if (!EnsureViewTexture(viewWidth, viewHeight, pixelFormat)) return Fail(SRB_E_D3D, "Could not create view texture");
    g.ctx->UpdateSubresource(g.sbsTex, 0, nullptr, pixels, static_cast<UINT>(pitch), 0);
    if (trace) BLog("submit: uploaded");
    SetWeaverInput(g.sbsSrv, viewWidth, viewHeight, ViewSrvFormat());
    return WeaveAndPresent(g.sbsTex, viewWidth, viewHeight, pixelFormat == SRB_FMT_BGRA8, trace);
    } catch (...) {
        g.contextInvalid = true;
        g.stats.exceptions++;
        BLog("exception in srb_SubmitViews");
        return Fail(SRB_S_2D_FALLBACK, "Exception during weaving; will re-create SR context");
    }
}

SRB_API int32_t srb_SceneParamsSize(void)
{
    static_assert(sizeof(SRB_SceneParams) == 64, "SRB_SceneParams must stay 64 bytes");
    return (int32_t)sizeof(SRB_SceneParams);
}

SRB_API int32_t srb_RenderScene(const SRB_SceneParams* params, SRB_SceneInfo* info)
{
    if (!g.initialized) return SRB_E_NOT_INITIALIZED;
    if (!params || params->viewWidth < 1 || params->viewHeight < 1) return SRB_E_ARGS;
    SRB_ENTRY;
    const bool trace = g_submitTrace > 0;
    if (trace) { g_submitTrace--; BLog("scene: %d x %d per eye", params->viewWidth, params->viewHeight); }
    CtxGuard guard;
    try {
        RecoverSR();
        if (!EnsureSceneResources()) return Fail(SRB_E_D3D, "Scene shaders or buffers could not be created (see log)");
        if (!EnsureSceneTargets(params->viewWidth, params->viewHeight)) return Fail(SRB_E_D3D, "Could not create the scene targets");
        SRB_SceneInfo si{};
        DirectX::XMVECTOR el, er;
        SceneEyes(*params, si, el, er);
        RenderSceneViews(*params, si, el, er);
        if (trace) BLog("scene: drawn");
        if (info) *info = si;
        SetWeaverInput(gs.srv, params->viewWidth, params->viewHeight, DXGI_FORMAT_B8G8R8A8_UNORM_SRGB);
        return WeaveAndPresent(gs.tex, params->viewWidth, params->viewHeight, true, trace);
    } catch (...) {
        g.contextInvalid = true;
        g.stats.exceptions++;
        BLog("exception in srb_RenderScene");
        return Fail(SRB_S_2D_FALLBACK, "Exception during the scene; will re-create SR context");
    }
}

SRB_API void srb_SetProgramDevice(void* d3d11Device)
{
    ID3D11Device* d = static_cast<ID3D11Device*>(d3d11Device);
    if (d) d->AddRef();
    SafeRelease(g.progDev);
    g.progDev = d;
}

void CopyName(char* dst, const std::string& src)
{
    std::strncpy(dst, src.c_str(), 127);
    dst[127] = 0;
}

SRB_API int32_t srb_GetGpuCheck(SRB_GpuCheck* check)
{
    if (!check) return SRB_E_ARGS;
    SRB_ENTRY;
    std::memset(check, 0, sizeof(*check));
    CopyName(check->srDisplayAdapter, g.srAdapterKnown ? g.srAdapterName : std::string());
    CopyName(check->bridgeAdapter, g.adapterName);
    check->srRefreshHz = static_cast<int32_t>(g.srRefreshHz);
    check->sharingProgramDevice = (g.extDev && g.dev == g.extDev) ? 1 : 0;
    check->sharedRefused = g.sharedRefused ? 1 : 0;
    check->bridgeOnSRAdapter = (g.srAdapterKnown && g.dev) ? (SameLuid(g.adapterLuid, g.srAdapterLuid) ? 1 : 0) : -1;
    ID3D11Device* prog = g.extDev ? g.extDev : g.progDev;
    check->programOnSRAdapter = -1;
    if (prog) {
        LUID luid{};
        std::string name;
        UINT vendor = 0;
        if (DeviceAdapter(prog, luid, name, vendor)) {
            CopyName(check->programAdapter, name);
            check->programSoftware = vendor == 0x1414 ? 1 : 0;   // Microsoft Basic Render Driver / WARP
            if (g.srAdapterKnown) check->programOnSRAdapter = SameLuid(luid, g.srAdapterLuid) ? 1 : 0;
        }
    }
    return g.srAdapterKnown ? SRB_OK : SRB_E_NO_DISPLAY;
}

SRB_API void srb_SetExternalDevice(void* d3d11Device)
{
    if (g.initialized) { BLog("srb_SetExternalDevice ignored: call it before srb_Initialize"); return; }
    ID3D11Device* d = static_cast<ID3D11Device*>(d3d11Device);
    if (d) d->AddRef();
    SafeRelease(g.extDev);
    g.extDev = d;
    BLog("external device %p %s", d3d11Device, d ? "given: the bridge will share it" : "cleared: the bridge makes its own");
}

// The view texture's pixel format family for a texture format, or -1.
int FormatFamily(DXGI_FORMAT f)
{
    switch (f) {
    case DXGI_FORMAT_B8G8R8A8_TYPELESS: case DXGI_FORMAT_B8G8R8A8_UNORM: case DXGI_FORMAT_B8G8R8A8_UNORM_SRGB:
        return SRB_FMT_BGRA8;
    case DXGI_FORMAT_R8G8B8A8_TYPELESS: case DXGI_FORMAT_R8G8B8A8_UNORM: case DXGI_FORMAT_R8G8B8A8_UNORM_SRGB:
        return SRB_FMT_RGBA8;
    default:
        return -1;
    }
}

SRB_API int32_t srb_CopyEyeTexture(int32_t eye, void* texture, int32_t viewWidth, int32_t viewHeight)
{
    if (!g.initialized) return SRB_E_NOT_INITIALIZED;
    if (!texture || eye < 0 || eye > 1 || viewWidth < 1 || viewHeight < 1) return SRB_E_ARGS;
    SRB_ENTRY;
    CtxGuard guard;
    ID3D11Texture2D* src = nullptr;
    try {
        if (FAILED(static_cast<IUnknown*>(texture)->QueryInterface(__uuidof(ID3D11Texture2D), reinterpret_cast<void**>(&src))))
            return Fail(SRB_E_ARGS, "srb_CopyEyeTexture: not a 2D texture");
        ID3D11Device* owner = nullptr;
        src->GetDevice(&owner);
        const bool sameDevice = owner == g.dev;
        SafeRelease(owner);
        if (!sameDevice) { src->Release(); return Fail(SRB_E_ARGS, "srb_CopyEyeTexture: the texture is not on the bridge's device (srb_SetExternalDevice)"); }
        D3D11_TEXTURE2D_DESC d{};
        src->GetDesc(&d);
        const int fmt = FormatFamily(d.Format);
        if (!g.eyeCopyLogged) {
            g.eyeCopyLogged = true;
            BLog("eye texture %u x %u, format %d, %u sample(s): copied on the GPU into %d x %d views",
                 d.Width, d.Height, static_cast<int>(d.Format), d.SampleDesc.Count, viewWidth, viewHeight);
        }
        if (fmt < 0) { src->Release(); return Fail(SRB_E_ARGS, "srb_CopyEyeTexture: not an 8-bit BGRA or RGBA texture"); }
        if (!EnsureViewTexture(viewWidth, viewHeight, fmt)) { src->Release(); return Fail(SRB_E_D3D, "Could not create view texture"); }
        ID3D11Texture2D* from = src;
        if (d.SampleDesc.Count > 1) {
            // Multisampled (FMX resolves it only at EndScene): resolve here
            D3D11_TEXTURE2D_DESC rd{};
            if (g.resolveTex) g.resolveTex->GetDesc(&rd);
            if (!g.resolveTex || rd.Width != d.Width || rd.Height != d.Height || rd.Format != d.Format) {
                SafeRelease(g.resolveTex);
                rd = d;
                rd.SampleDesc.Count = 1;
                rd.SampleDesc.Quality = 0;
                rd.MipLevels = 1;
                rd.ArraySize = 1;
                rd.Usage = D3D11_USAGE_DEFAULT;
                rd.BindFlags = D3D11_BIND_SHADER_RESOURCE;
                rd.CPUAccessFlags = 0;
                rd.MiscFlags = 0;
                if (FAILED(g.dev->CreateTexture2D(&rd, nullptr, &g.resolveTex))) { src->Release(); return Fail(SRB_E_D3D, "Could not create the resolve texture"); }
            }
            g.ctx->ResolveSubresource(g.resolveTex, 0, src, 0, d.Format);
            from = g.resolveTex;
        }
        D3D11_BOX box{ 0, 0, 0, std::min<UINT>(d.Width, static_cast<UINT>(viewWidth)),
                       std::min<UINT>(d.Height, static_cast<UINT>(viewHeight)), 1 };
        g.ctx->CopySubresourceRegion(g.sbsTex, 0, static_cast<UINT>(eye * viewWidth), 0, 0, from, 0, &box);
        src->Release();
        return SRB_OK;
    } catch (...) {
        SafeRelease(src);
        g.stats.exceptions++;
        return Fail(SRB_E_D3D, "Exception copying an eye texture");
    }
}

SRB_API int32_t srb_PresentViews(int32_t viewWidth, int32_t viewHeight)
{
    if (!g.initialized) return SRB_E_NOT_INITIALIZED;
    if (viewWidth < 1 || viewHeight < 1) return SRB_E_ARGS;
    SRB_ENTRY;
    const bool trace = g_submitTrace > 0;
    if (trace) { g_submitTrace--; BLog("present views: %d x %d per eye, copied on the GPU", viewWidth, viewHeight); }
    CtxGuard guard;
    try {
        RecoverSR();
        if (!g.sbsTex || g.texViewW != viewWidth || g.texViewH != viewHeight)
            return Fail(SRB_E_ARGS, "srb_PresentViews: no views of that size were copied (srb_CopyEyeTexture)");
        SetWeaverInput(g.sbsSrv, viewWidth, viewHeight, ViewSrvFormat());
        return WeaveAndPresent(g.sbsTex, viewWidth, viewHeight, g.texFmt == SRB_FMT_BGRA8, trace);
    } catch (...) {
        g.contextInvalid = true;
        g.stats.exceptions++;
        BLog("exception in srb_PresentViews");
        return Fail(SRB_S_2D_FALLBACK, "Exception during weaving; will re-create SR context");
    }
}

SRB_API void srb_SetFrameCap(int32_t enabled)
{
    g.frameCap = enabled != 0;
    BLog("frame cap %s", g.frameCap ? "on: one frame per display refresh (with vsync)" : "off");
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

SRB_API int32_t srb_GetDisplayRect(int32_t* rect)
{
    if (!rect) return SRB_E_ARGS;
    if (!g.initialized) return SRB_E_NOT_INITIALIZED;
    if (!g.displayRectValid) return SRB_E_NO_DISPLAY;
    rect[0] = g.displayRect.left;
    rect[1] = g.displayRect.top;
    rect[2] = g.displayRect.right;
    rect[3] = g.displayRect.bottom;
    return SRB_OK;
}

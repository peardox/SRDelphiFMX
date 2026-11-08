/*
 * LenticularBridge - flat C wrapper around the lenticular display runtime's DX11 weaver,
 * intended to be called from Delphi (or any language with a C FFI).
 *
 * Why this exists: the runtime's weaver API (SR::CreateDX11Weaver / SR::IDX11Weaver1) is
 * C++ only and uses virtual inheritance, so it can't be called safely from Delphi.
 * This DLL owns a small native child window placed over your FMX TViewport3D,
 * its own D3D11 device + swap chain, and the runtime's weaver. Delphi renders the left
 * and right eye images, hands the side-by-side pixels to lnb_SubmitViews(), and
 * the bridge weaves them onto the lenticular display.
 *
 * All functions must be called from the same (UI) thread.
 * Calling convention: __cdecl (on Win64 there is only one convention anyway).
 */
#pragma once

#include <stdint.h>

#ifdef LENTICULARBRIDGE_EXPORTS
#  define LNB_API extern "C" __declspec(dllexport)
#else
#  ifdef __cplusplus
#    define LNB_API extern "C" __declspec(dllimport)
#  else
#    define LNB_API __declspec(dllimport)
#  endif
#endif

/* Result codes */
#define LNB_OK                  0
#define LNB_E_NOT_INITIALIZED  -1
#define LNB_E_RUNTIME_MISSING   -2   /* display runtime DLLs not found (display runtime not installed / not on PATH) */
#define LNB_E_NO_SERVICE       -3   /* SRContext could not be created (display service not running) */
#define LNB_E_NO_DISPLAY       -4   /* 3D display not ready within timeout */
#define LNB_E_D3D              -5   /* Direct3D 11 failure */
#define LNB_E_WEAVER           -6   /* Weaver could not be created */
#define LNB_E_ARGS             -7
#define LNB_E_WINDOW           -8

/* Non-error statuses returned by lnb_SubmitViews */
#define LNB_S_2D_FALLBACK       1   /* presented unwoven (The runtime temporarily unavailable) */
#define LNB_S_OCCLUDED          2   /* window fully hidden; caller may throttle */

/* Pixel formats accepted by lnb_SubmitViews */
#define LNB_FMT_BGRA8           0
#define LNB_FMT_RGBA8           1

typedef struct {
    int32_t resolutionWidth;          /* as seen by the user (pixels) */
    int32_t resolutionHeight;
    int32_t physicalResolutionWidth;  /* panel pixels */
    int32_t physicalResolutionHeight;
    float   physicalWidthMM;          /* active area, millimetres */
    float   physicalHeightMM;
    int32_t recommendedViewWidth;     /* per eye */
    int32_t recommendedViewHeight;
} LNB_DisplayInfo;

typedef struct {
    uint64_t time;        /* microseconds since epoch */
    uint64_t eventType;   /* SR_eventType value, see sr/sense/system/systemevent.h */
    char     message[256];
} LNB_SystemEvent;

/* Counters for diagnostics (lnb_GetStats). Counts are since lnb_Initialize. */
typedef struct {
    uint64_t framesSubmitted;   /* Present calls */
    uint64_t framesWoven;
    uint64_t frames2D;          /* presented unwoven (The runtime unavailable) */
    uint64_t framesOccluded;
    uint64_t reinitAttempts;    /* runtime context re-creations tried after a loss */
    uint64_t reinitSuccesses;
    uint64_t exceptions;        /* C++ exceptions caught from the display runtime */
    uint64_t weaverLatencyUs;   /* weaver's current latency setting, microseconds */
    int32_t  lastPresentHr;     /* HRESULT of the last Present */
    int32_t  backBufferWidth;
    int32_t  backBufferHeight;
    int32_t  viewWidth;         /* per-eye view size last submitted */
    int32_t  viewHeight;
    int32_t  weaving;           /* 1 if a weaver currently exists */
    int32_t  contextInvalid;    /* 1 if a context loss is pending recovery */
    int32_t  reserved;
} LNB_Stats;

/* The native scene (lnb_RenderScene): LenticularDemoFMX's test scene. World units
   as FMX's, with its camera 20 units back at 45 degrees: the viewport is
   16.57 units high on the glass; x right, y down, z away from the viewer,
   the glass at z = 0. An 11 x 11 grid of spheres 3 units apart in x and z,
   coloured by depth, around the main sphere at the origin; two columns of
   three cubes above and below; a back wall at z = 18. */
typedef struct {
    int32_t viewWidth;        /* per eye, pixels */
    int32_t viewHeight;
    float   rotation;         /* the cubes' turn about their vertical axis, radians */
    float   eyeSeparationMM;  /* 0: as tracked */
    float   depthScale;       /* eye separation scale about the midpoint; 1 real, 0 means 1 */
    int32_t lookAround;       /* 0: a fixed viewer 650 mm in front of the window centre */
    int32_t flat;             /* 1: both eyes at the midpoint (a 2D picture, for the lens off) */
    int32_t fps;              /* frame rate drawn on the glass at the top left; < 0 none */
    float   sceneZ;           /* the whole scene moved away from the viewer, world units */
    float   tiltDeg;          /* the scene turned about the horizontal axis through the main sphere */
    float   rollDeg;          /* the scene turned about the depth axis through the main sphere */
    float   gridSpinDeg;      /* the sphere grid turned about the vertical axis through the main sphere */
    int32_t reserved[4];
} LNB_SceneParams;

typedef struct {
    float   leftEye[3];       /* the eyes drawn from, mm, display centre, x right, y up, z out */
    float   rightEye[3];
    float   windowCenterX;    /* the window on the display, mm */
    float   windowCenterY;
    float   windowWidth;
    float   windowHeight;
    int32_t nominalEyes;      /* 1: no tracked eyes yet; a default viewer was used */
    int32_t separationRebuilt;/* 1: tracked separation outside 45-85 mm, 63 mm used */
} LNB_SceneInfo;

/* Which GPUs are in use (lnb_GetGpuCheck). Names are UTF-8. */
typedef struct {
    char    programAdapter[128];   /* the program's device (lnb_SetProgramDevice / lnb_SetExternalDevice); empty if none given */
    char    bridgeAdapter[128];    /* the bridge's device */
    char    displayAdapter[128]; /* the GPU driving the 3D display; empty if not found */
    int32_t programOnDisplayAdapter;    /* 1 yes, 0 NO (slow, may misbehave), -1 unknown */
    int32_t bridgeOnDisplayAdapter;     /* 1 yes, 0 no, -1 unknown */
    int32_t sharingProgramDevice;  /* 1: zero copy in use */
    int32_t sharedRefused;         /* 1: the program's device was offered but is not on the 3D display's GPU */
    int32_t programSoftware;       /* 1: the program renders in software (WARP / Basic Render Driver) */
    int32_t displayRefreshHz;           /* the 3D display's refresh rate, 0 if unknown */
    int32_t reserved[2];
} LNB_GpuCheck;

/* Create runtime context (retrying up to timeoutSeconds), D3D11 device, a child window
 * of parentWnd and the weaver. Safe to call again after lnb_Finalize. */
LNB_API int32_t lnb_Initialize(void* parentWnd, double timeoutSeconds);
/* Can the runtime start? Without a window or a device: loads the runtime, then
 * tries for an runtime context and a ready display until timeoutMs has passed
 * (0: one try each), and deletes the context again. Meant to run on a
 * background thread, so the wait for a starting service or a display does
 * not freeze the program; nothing else in the bridge may be called until it
 * returns. Returns LNB_OK, LNB_E_RUNTIME_MISSING, LNB_E_NO_SERVICE or
 * LNB_E_NO_DISPLAY (message in lnb_GetLastError). LNB_OK at once while
 * initialised. Added 5 November 2026. */
LNB_API int32_t lnb_Probe(int32_t timeoutMs);
/* Whether the display runtime is installed: every runtime DLL the bridge
 * needs can be found where it would load it from (the normal DLL search,
 * plus a folder given to lnb_SetDllDirectory). Checked as data (no code
 * runs, nothing stays loaded), so it is quick and safe on any computer,
 * before lnb_Initialize. Says nothing about whether the display service is
 * running or a display is plugged in (lnb_Probe does that).
 * Returns 1 if all were found, 0 if any was not. */
LNB_API int32_t lnb_RuntimeInstalled(void);
LNB_API void    lnb_Finalize(void);
LNB_API int32_t lnb_IsInitialized(void);
LNB_API int32_t lnb_IsWeaving(void);            /* 1 if a weaver exists (else 2D fallback) */

/* Placement of the native child window, in physical pixels relative to the
 * parent's client area. Width/height also define the back-buffer size. */
LNB_API int32_t lnb_SetBounds(int32_t x, int32_t y, int32_t width, int32_t height);
LNB_API void    lnb_SetVisible(int32_t visible);

LNB_API int32_t lnb_GetDisplayInfo(LNB_DisplayInfo* info);

/* The 3D display's rectangle on the desktop, in physical pixels: rect[0..3] =
 * left, top, right, bottom. Taken from the runtime (SR::Display::getLocation) when
 * possible, otherwise by matching monitors' resolution and physical size.
 * Returns LNB_E_NO_DISPLAY if it could not be found. */
LNB_API int32_t lnb_GetDisplayRect(int32_t* rect);

/* Physical rectangle of the child window on the 3D display, in millimetres,
 * relative to the display centre (x right, y up) - the same frame the eye
 * tracker reports in. */
LNB_API int32_t lnb_GetWindowRectMM(double* centerX, double* centerY, double* width, double* height);

/* Predicted eye positions in millimetres (display-centred, x right, y up,
 * z towards the viewer). left/right each point to float[3]. */
LNB_API int32_t lnb_GetEyePositions(float* left, float* right);

/* Upload a side-by-side image (left view in the left half) and weave + present.
 * Returns LNB_OK (woven), LNB_S_2D_FALLBACK, LNB_S_OCCLUDED, or a negative error.
 * pixels: top-down rows, viewWidth*2 pixels wide, pitch bytes per row. */
LNB_API int32_t lnb_SubmitViews(const void* pixels, int32_t viewWidth, int32_t viewHeight,
                                int32_t pitch, int32_t pixelFormat);

/* sizeof(LNB_SceneParams) in this bridge: 64. Bridges built before
   5 November 2026, 08:30 (32-byte params, the old wall/floor/cube/four
   spheres scene) do not have it, so a program can tell an old bridge from a
   new one. Added 5 November 2026, 08:40. */
LNB_API int32_t lnb_SceneParamsSize(void);
/* Draws the bridge's own 3D scene (LenticularDemoFMX's: the grid of spheres, the
   columns of cubes, the back wall and the frame rate) for both eyes straight into
   a view texture on the GPU, with an off-axis projection per eye from the
   tracked eyes and the window's place on the display, then weaves and
   presents. No pixels pass through the caller. info (may be NULL) receives
   the eyes and window used. Returns as lnb_SubmitViews. */
LNB_API int32_t lnb_RenderScene(const LNB_SceneParams* params, LNB_SceneInfo* info);

/* Zero copy: share the program's own D3D11 device (FMX's
   TCustomDX11Context.SharedDevice) instead of making one. Call before
   lnb_Initialize; NULL goes back to the bridge's own device. The bridge
   keeps its pipeline state in a D3D 11.1 state block of its own, swapped in
   around each call, so neither side disturbs the other's bindings. Falls
   back to its own device (and logs why) if the device has no 11.1 state
   blocks. */
LNB_API void    lnb_SetExternalDevice(void* d3d11Device);
/* For the GPU check only: the program's own D3D11 device, not shared. */
LNB_API void    lnb_SetProgramDevice(void* d3d11Device);
/* After lnb_Initialize: which GPU the program, the bridge and the runtime
   display are on. Returns LNB_E_NO_DISPLAY if the 3D display's GPU was not
   found (the other fields are still filled in). */
LNB_API int32_t lnb_GetGpuCheck(LNB_GpuCheck* check);
/* Zero copy: copies one eye's rendered texture (an ID3D11Texture2D or its
   ID3D11Resource on the shared device; multisampled is resolved) into that
   eye's half of the view texture, on the GPU. eye 0 left, 1 right. */
LNB_API int32_t lnb_CopyEyeTexture(int32_t eye, void* texture, int32_t viewWidth, int32_t viewHeight);
/* Zero copy: weaves and presents the views copied with lnb_CopyEyeTexture.
   Returns as lnb_SubmitViews. */
LNB_API int32_t lnb_PresentViews(int32_t viewWidth, int32_t viewHeight);
/* 1 (default): with vsync on, wait for the 3D display's vertical blank
   after each Present (DwmFlush if its output is unknown), so no more frames
   are drawn than the display shows. */
LNB_API void    lnb_SetFrameCap(int32_t enabled);
LNB_API void    lnb_SetVSync(int32_t enabled);
LNB_API void    lnb_SetLatencyInFrames(uint64_t frames);
LNB_API void    lnb_SetLens(int32_t enabled);   /* lens on/off hint; before lnb_Initialize it also
                                                   sets the lens the runtime context starts with */
/* The lens as it actually is (the runtime's isLensEnabled): 1 on, 0 off, -1 not known
   (not initialised, or a runtime without isLensEnabled). Not in bridges
   built before 7 November 2026, 17:00. */
LNB_API int32_t lnb_GetLensState(void);

/* The bridge's ID3D11Device (its own, or the program's when shared), for a
   program that makes its eye textures on it for lnb_CopyEyeTexture (an
   OpenGL program through WGL_NV_DX_interop2). Not AddRef'd: valid until
   lnb_Finalize; NULL while not initialised. Not in bridges built before
   7 November 2026, 21:00. */
LNB_API void*   lnb_GetDevice(void);

/* Pops one queued system event. Returns 1 if an event was written, 0 if none. */
LNB_API int32_t lnb_PollSystemEvent(LNB_SystemEvent* ev);

/* Last error text (UTF-8, valid until next call). */
LNB_API const char* lnb_GetLastError(void);
LNB_API const char* lnb_GetPlatformVersion(void);

LNB_API int32_t lnb_GetStats(LNB_Stats* stats);

/* Diagnostic log. The callback receives zero-terminated UTF-8 lines, from any
 * thread (The runtime calls back on its own threads), so it must be thread-safe and
 * quick. Setting it also installs last-gasp handlers for abort(),
 * std::terminate, pure virtual calls and CRT invalid parameters, which log a
 * FATAL line before the process ends. Pass NULL to stop logging. */
typedef void (__cdecl *LNB_LogCallback)(const char* line);
LNB_API void lnb_SetLogCallback(LNB_LogCallback callback);

/* Optional: extra folder to search for the display runtime DLLs. Call before lnb_Initialize. */
LNB_API void lnb_SetDllDirectory(const wchar_t* path);

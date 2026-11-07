/*
 * SRBridge - flat C wrapper around the LeiaSR (Simulated Reality) DX11 weaver,
 * intended to be called from Delphi (or any language with a C FFI).
 *
 * Why this exists: the SR weaver API (SR::CreateDX11Weaver / SR::IDX11Weaver1) is
 * C++ only and uses virtual inheritance, so it can't be called safely from Delphi.
 * This DLL owns a small native child window placed over your FMX TViewport3D,
 * its own D3D11 device + swap chain, and the SR weaver. Delphi renders the left
 * and right eye images, hands the side-by-side pixels to srb_SubmitViews(), and
 * the bridge weaves them onto the lenticular display.
 *
 * All functions must be called from the same (UI) thread.
 * Calling convention: __cdecl (on Win64 there is only one convention anyway).
 */
#pragma once

#include <stdint.h>

#ifdef SRBRIDGE_EXPORTS
#  define SRB_API extern "C" __declspec(dllexport)
#else
#  ifdef __cplusplus
#    define SRB_API extern "C" __declspec(dllimport)
#  else
#    define SRB_API __declspec(dllimport)
#  endif
#endif

/* Result codes */
#define SRB_OK                  0
#define SRB_E_NOT_INITIALIZED  -1
#define SRB_E_SR_DLL_MISSING   -2   /* SR runtime DLLs not found (SR Platform not installed / not on PATH) */
#define SRB_E_NO_SERVICE       -3   /* SRContext could not be created (SR service not running) */
#define SRB_E_NO_DISPLAY       -4   /* SR display not ready within timeout */
#define SRB_E_D3D              -5   /* Direct3D 11 failure */
#define SRB_E_WEAVER           -6   /* Weaver could not be created */
#define SRB_E_ARGS             -7
#define SRB_E_WINDOW           -8

/* Non-error statuses returned by srb_SubmitViews */
#define SRB_S_2D_FALLBACK       1   /* presented unwoven (SR temporarily unavailable) */
#define SRB_S_OCCLUDED          2   /* window fully hidden; caller may throttle */

/* Pixel formats accepted by srb_SubmitViews */
#define SRB_FMT_BGRA8           0
#define SRB_FMT_RGBA8           1

typedef struct {
    int32_t resolutionWidth;          /* as seen by the user (pixels) */
    int32_t resolutionHeight;
    int32_t physicalResolutionWidth;  /* panel pixels */
    int32_t physicalResolutionHeight;
    float   physicalWidthMM;          /* active area, millimetres */
    float   physicalHeightMM;
    int32_t recommendedViewWidth;     /* per eye */
    int32_t recommendedViewHeight;
} SRB_DisplayInfo;

typedef struct {
    uint64_t time;        /* microseconds since epoch */
    uint64_t eventType;   /* SR_eventType value, see sr/sense/system/systemevent.h */
    char     message[256];
} SRB_SystemEvent;

/* Counters for diagnostics (srb_GetStats). Counts are since srb_Initialize. */
typedef struct {
    uint64_t framesSubmitted;   /* Present calls */
    uint64_t framesWoven;
    uint64_t frames2D;          /* presented unwoven (SR unavailable) */
    uint64_t framesOccluded;
    uint64_t reinitAttempts;    /* SR context re-creations tried after a loss */
    uint64_t reinitSuccesses;
    uint64_t exceptions;        /* C++ exceptions caught from the SR runtime */
    uint64_t weaverLatencyUs;   /* weaver's current latency setting, microseconds */
    int32_t  lastPresentHr;     /* HRESULT of the last Present */
    int32_t  backBufferWidth;
    int32_t  backBufferHeight;
    int32_t  viewWidth;         /* per-eye view size last submitted */
    int32_t  viewHeight;
    int32_t  weaving;           /* 1 if a weaver currently exists */
    int32_t  contextInvalid;    /* 1 if a context loss is pending recovery */
    int32_t  reserved;
} SRB_Stats;

/* The native scene (srb_RenderScene): SRDemoFMX's test scene. World units
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
} SRB_SceneParams;

typedef struct {
    float   leftEye[3];       /* the eyes drawn from, mm, display centre, x right, y up, z out */
    float   rightEye[3];
    float   windowCenterX;    /* the window on the display, mm */
    float   windowCenterY;
    float   windowWidth;
    float   windowHeight;
    int32_t nominalEyes;      /* 1: no tracked eyes yet; a default viewer was used */
    int32_t separationRebuilt;/* 1: tracked separation outside 45-85 mm, 63 mm used */
} SRB_SceneInfo;

/* Which GPUs are in use (srb_GetGpuCheck). Names are UTF-8. */
typedef struct {
    char    programAdapter[128];   /* the program's device (srb_SetProgramDevice / srb_SetExternalDevice); empty if none given */
    char    bridgeAdapter[128];    /* the bridge's device */
    char    srDisplayAdapter[128]; /* the GPU driving the SR display; empty if not found */
    int32_t programOnSRAdapter;    /* 1 yes, 0 NO (slow, may misbehave), -1 unknown */
    int32_t bridgeOnSRAdapter;     /* 1 yes, 0 no, -1 unknown */
    int32_t sharingProgramDevice;  /* 1: zero copy in use */
    int32_t sharedRefused;         /* 1: the program's device was offered but is not on the SR display's GPU */
    int32_t programSoftware;       /* 1: the program renders in software (WARP / Basic Render Driver) */
    int32_t srRefreshHz;           /* the SR display's refresh rate, 0 if unknown */
    int32_t reserved[2];
} SRB_GpuCheck;

/* Create SR context (retrying up to timeoutSeconds), D3D11 device, a child window
 * of parentWnd and the weaver. Safe to call again after srb_Finalize. */
SRB_API int32_t srb_Initialize(void* parentWnd, double timeoutSeconds);
/* Can SR start? Without a window or a device: loads the runtime, then
 * tries for an SR context and a ready display until timeoutMs has passed
 * (0: one try each), and deletes the context again. Meant to run on a
 * background thread, so the wait for a starting service or a display does
 * not freeze the program; nothing else in the bridge may be called until it
 * returns. Returns SRB_OK, SRB_E_SR_DLL_MISSING, SRB_E_NO_SERVICE or
 * SRB_E_NO_DISPLAY (message in srb_GetLastError). SRB_OK at once while
 * initialised. Added 5 November 2026. */
SRB_API int32_t srb_Probe(int32_t timeoutMs);
SRB_API void    srb_Finalize(void);
SRB_API int32_t srb_IsInitialized(void);
SRB_API int32_t srb_IsWeaving(void);            /* 1 if a weaver exists (else 2D fallback) */

/* Placement of the native child window, in physical pixels relative to the
 * parent's client area. Width/height also define the back-buffer size. */
SRB_API int32_t srb_SetBounds(int32_t x, int32_t y, int32_t width, int32_t height);
SRB_API void    srb_SetVisible(int32_t visible);

SRB_API int32_t srb_GetDisplayInfo(SRB_DisplayInfo* info);

/* The SR display's rectangle on the desktop, in physical pixels: rect[0..3] =
 * left, top, right, bottom. Taken from SR (SR::Display::getLocation) when
 * possible, otherwise by matching monitors' resolution and physical size.
 * Returns SRB_E_NO_DISPLAY if it could not be found. */
SRB_API int32_t srb_GetDisplayRect(int32_t* rect);

/* Physical rectangle of the child window on the SR display, in millimetres,
 * relative to the display centre (x right, y up) - the same frame the eye
 * tracker reports in. */
SRB_API int32_t srb_GetWindowRectMM(double* centerX, double* centerY, double* width, double* height);

/* Predicted eye positions in millimetres (display-centred, x right, y up,
 * z towards the viewer). left/right each point to float[3]. */
SRB_API int32_t srb_GetEyePositions(float* left, float* right);

/* Upload a side-by-side image (left view in the left half) and weave + present.
 * Returns SRB_OK (woven), SRB_S_2D_FALLBACK, SRB_S_OCCLUDED, or a negative error.
 * pixels: top-down rows, viewWidth*2 pixels wide, pitch bytes per row. */
SRB_API int32_t srb_SubmitViews(const void* pixels, int32_t viewWidth, int32_t viewHeight,
                                int32_t pitch, int32_t pixelFormat);

/* sizeof(SRB_SceneParams) in this bridge: 64. Bridges built before
   5 November 2026, 08:30 (32-byte params, the old wall/floor/cube/four
   spheres scene) do not have it, so a program can tell an old bridge from a
   new one. Added 5 November 2026, 08:40. */
SRB_API int32_t srb_SceneParamsSize(void);
/* Draws the bridge's own 3D scene (SRDemoFMX's: the grid of spheres, the
   columns of cubes, the back wall and the frame rate) for both eyes straight into
   a view texture on the GPU, with an off-axis projection per eye from the
   tracked eyes and the window's place on the display, then weaves and
   presents. No pixels pass through the caller. info (may be NULL) receives
   the eyes and window used. Returns as srb_SubmitViews. */
SRB_API int32_t srb_RenderScene(const SRB_SceneParams* params, SRB_SceneInfo* info);

/* Zero copy: share the program's own D3D11 device (FMX's
   TCustomDX11Context.SharedDevice) instead of making one. Call before
   srb_Initialize; NULL goes back to the bridge's own device. The bridge
   keeps its pipeline state in a D3D 11.1 state block of its own, swapped in
   around each call, so neither side disturbs the other's bindings. Falls
   back to its own device (and logs why) if the device has no 11.1 state
   blocks. */
SRB_API void    srb_SetExternalDevice(void* d3d11Device);
/* For the GPU check only: the program's own D3D11 device, not shared. */
SRB_API void    srb_SetProgramDevice(void* d3d11Device);
/* After srb_Initialize: which GPU the program, the bridge and the SR
   display are on. Returns SRB_E_NO_DISPLAY if the SR display's GPU was not
   found (the other fields are still filled in). */
SRB_API int32_t srb_GetGpuCheck(SRB_GpuCheck* check);
/* Zero copy: copies one eye's rendered texture (an ID3D11Texture2D or its
   ID3D11Resource on the shared device; multisampled is resolved) into that
   eye's half of the view texture, on the GPU. eye 0 left, 1 right. */
SRB_API int32_t srb_CopyEyeTexture(int32_t eye, void* texture, int32_t viewWidth, int32_t viewHeight);
/* Zero copy: weaves and presents the views copied with srb_CopyEyeTexture.
   Returns as srb_SubmitViews. */
SRB_API int32_t srb_PresentViews(int32_t viewWidth, int32_t viewHeight);
/* 1 (default): with vsync on, wait for the SR display's vertical blank
   after each Present (DwmFlush if its output is unknown), so no more frames
   are drawn than the display shows. */
SRB_API void    srb_SetFrameCap(int32_t enabled);
SRB_API void    srb_SetVSync(int32_t enabled);
SRB_API void    srb_SetLatencyInFrames(uint64_t frames);
SRB_API void    srb_SetLens(int32_t enabled);   /* lens on/off hint; before srb_Initialize it also
                                                   sets the lens the SR context starts with */
/* The lens as it actually is (SR's isLensEnabled): 1 on, 0 off, -1 not known
   (not initialised, or a runtime without isLensEnabled). Not in bridges
   built before 7 November 2026, 17:00. */
SRB_API int32_t srb_GetLensState(void);

/* The bridge's ID3D11Device (its own, or the program's when shared), for a
   program that makes its eye textures on it for srb_CopyEyeTexture (an
   OpenGL program through WGL_NV_DX_interop2). Not AddRef'd: valid until
   srb_Finalize; NULL while not initialised. Not in bridges built before
   7 November 2026, 21:00. */
SRB_API void*   srb_GetDevice(void);

/* Pops one queued system event. Returns 1 if an event was written, 0 if none. */
SRB_API int32_t srb_PollSystemEvent(SRB_SystemEvent* ev);

/* Last error text (UTF-8, valid until next call). */
SRB_API const char* srb_GetLastError(void);
SRB_API const char* srb_GetPlatformVersion(void);

SRB_API int32_t srb_GetStats(SRB_Stats* stats);

/* Diagnostic log. The callback receives zero-terminated UTF-8 lines, from any
 * thread (SR calls back on its own threads), so it must be thread-safe and
 * quick. Setting it also installs last-gasp handlers for abort(),
 * std::terminate, pure virtual calls and CRT invalid parameters, which log a
 * FATAL line before the process ends. Pass NULL to stop logging. */
typedef void (__cdecl *SRB_LogCallback)(const char* line);
SRB_API void srb_SetLogCallback(SRB_LogCallback callback);

/* Optional: extra folder to search for the SR runtime DLLs. Call before srb_Initialize. */
SRB_API void srb_SetDllDirectory(const wchar_t* path);

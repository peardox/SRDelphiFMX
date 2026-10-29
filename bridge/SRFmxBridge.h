/*
 * SRFmxBridge - flat C wrapper around the LeiaSR (Simulated Reality) DX11 weaver,
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

#ifdef SRFMXBRIDGE_EXPORTS
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

/* Create SR context (retrying up to timeoutSeconds), D3D11 device, a child window
 * of parentWnd and the weaver. Safe to call again after srb_Finalize. */
SRB_API int32_t srb_Initialize(void* parentWnd, double timeoutSeconds);
SRB_API void    srb_Finalize(void);
SRB_API int32_t srb_IsInitialized(void);
SRB_API int32_t srb_IsWeaving(void);            /* 1 if a weaver exists (else 2D fallback) */

/* Placement of the native child window, in physical pixels relative to the
 * parent's client area. Width/height also define the back-buffer size. */
SRB_API int32_t srb_SetBounds(int32_t x, int32_t y, int32_t width, int32_t height);
SRB_API void    srb_SetVisible(int32_t visible);

SRB_API int32_t srb_GetDisplayInfo(SRB_DisplayInfo* info);

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

SRB_API void    srb_SetVSync(int32_t enabled);
SRB_API void    srb_SetLatencyInFrames(uint64_t frames);
SRB_API void    srb_SetLens(int32_t enabled);   /* lens on/off hint */

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

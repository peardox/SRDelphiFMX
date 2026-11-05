# SimulatedReality: handover notes

This shows FMX `TViewport3D` scenes on a LeiaSR eye-tracked lenticular display from Delphi. Read `README.md` first, especially "Notes for Claude", then this file. The day-by-day history of how it got here (the full-screen fault hunt, the projection fixes, the zero-copy work) is in the git log up to commit `d42c73a`; this file keeps only what is true now.

## Where to pick up (5 November 2026, 09:00)

**Tidy-up after the demo scene work (owner, 08:54: "yep, that did it. Tidy up?").** Both demos now show the same scene with the same controls and both run at the display's 60 fps cap. The step-by-step history of 06:44 to 08:54 is in the git log; what it left is below. Next: the owner's test, then the push; after that, from "Offered, not done".

The demo scene (SRDemoFMX in FMX objects, SRDemoVCL drawn by the bridge's `srb_RenderScene`, in the same world units):
- An 11 x 11 grid of spheres (r 0.7, 3 units apart in X and Z, Y = 0), one colour per depth (white on the glass, blue behind, yellow to red in front), the green main sphere at the origin; two columns of three cubes (3 units, Y = +-(4.5 + 4.5k)), turning a turn in 8 s; a back wall 60 x 40 at Z = 18. The viewport is 16.5685 units high on the glass (camera 20 back, 45 degrees).
- FMX: objects under `FSceneRoot` (wheel, tilt, roll), the grid under `FGridRoot` inside it (R spin, `FGridSpin`, 20 s a turn the other way to the cubes, paused at start). The FPS is a `TPlane` with a texture redrawn once a second (a `TText3D` came out garbled), at depth 0 top left, half see-through.
- Bridge: `SRB_SceneParams` is 64 bytes (`fps`, `sceneZ`, `tiltDeg`, `rollDeg`, `gridSpinDeg`); world to mm `Scaling(U, -U, -U) * Translation(cx, cy, 0)`; the FPS as seven-segment digits. `srb_SceneParamsSize` lets SRDemoVCL refuse an older bridge (which draws the old scene).
- Controls in both: wheel or Page Up / Page Down move the scene in depth (+-20), left-drag tilts (X, +-85) and rolls (Z, +-180), Home resets, R toggles the grid spin. The status bar gives the depth row's mm from the glass. Tilt and roll directions might differ between the two (not reported).
- Settings...: `lib/SRSettingsDialog.pas`, a Windows dialog built in memory for the eye separation (0..90 mm, 0 = tracked), lens off while it is open. The Depth slider is gone; `EyeSeparationScale` is always 1 (SRDemoFMX puts back a saved other value and logs it).

Speed: `TSRViewport3D` (in `FMX.SRStereoViewport`) skips FMX's own, unseen paint of the viewport while frames run and the bridge's window shows (`SkipViewportPaint`, default True); that took SRDemoFMX from 33 to 60 fps in Release (33 was frames just over one refresh, halved by the vertical-blank cap). Risk not yet seen: a resize while skipping (full screen) if `TViewport3D` set up its context only in `Paint`.

Full screen hides the taskbar: the window is made topmost by `ApplyTopmost` from the frame loop 1 s after full screen came on (topmost at the moment of the resize raised `ECannotCreateSwapChain` for `TCanvasD2D`). `FullScreenTopmost` (default True) turns it off. Not yet confirmed that the delayed version never raises it.

Removed in this tidy-up: SRDemoFMX's `/notopmost` and `/fmxpaint` test switches (the properties stay). `/warp` stays (tests the GPU-problem path).

## State (verified on the owner's hardware)

- **3D in a window and full screen** works: correct off-axis projection (`corner` (1, 1)), look-around, no drift; full screen (F11 / Esc) no longer breaks (the fault went away once the bridge's device was on the GPU driving the SR display).
- **Zero copy**: the bridge shares FMX's DX11 device; eyes copied on the GPU (MSAA resolved). 210-250 fps uncapped; the **frame cap** on the SR output's vertical blank gives 60 fps.
- **GPU check**: the SR display's GPU is found before any device is made; FMX on the wrong GPU or in software is detected (`/warp` tested).
- **Start-problem policy**: no SR runtime is silent (controls hidden); with the runtime, `useGlassesFree3D` in the settings decides; on a problem the program carries on without glasses-free 3D and the task dialog offers continue without / try again / anyway (GPU problems only) / exit. The wording is "glasses-free 3D", never plain "3D".
- **Asynchronous start** (06:24 log): background check 64 ms, `srb_Initialize` 225 ms, first woven frame 2.2 s after the program started (run without the debugger).
- Lens off over the controls, wait for the eyes before 3D, off-display detection, SR display placement on multi-monitor desktops, stereo images from `media/` (left view in 2D while SR is off).
- SRDemoVCL: the bridge draws SRDemoFMX's scene itself (`srb_RenderScene`), 60 fps capped (the old, smaller scene ran at 440 fps uncapped full screen); same settings, controls, start-problem dialog (no "anyway" choice) and background check, start-problem and background-check answers posted to a hidden window.
- SRDemoFMX: 60 fps capped in Release with the demo scene (about 130 objects) since `SkipViewportPaint`.
- The frame watchdog (posts a frame when OnIdle has been starved for 25 ms) kept frames going on a power-limited GPU.

## Offered, not done

- A "frames too slow" warning (e.g. a laptop in low-power mode ran 31-58 fps even on the right GPU).
- An FMX `Multisample` setting (FMX renders 4x MSAA; at 4K per eye that costs a lot).
- Creating the SR context on the background check's thread and keeping it, to save the ~200 ms left on the main thread (unknown whether SR minds the thread change).
- Moving the GPU eye copy (`CopyEyeOnGpu`) into its own `lib/` unit.
- Switching the projects' default configuration to Release (owner: later).
- Offsetting the grid's depth column slightly, if spheres hide each other seen straight on.
- Known: in `lmIdle` mode under WARP, frames are starved (OnIdle comes only when the queue is empty); moot now that software rendering stops SR by default.

## How the owner works

The same as GDEM: Delphi 13 FMX on Windows.

The stop hook's "commit and push" prompt: do not answer it with an explanation; the owner knows changes are left for them to apply and push. Say nothing more than "Noted." if a reply is needed.

The compiled bridge is committed in `dll/SRBridge.dll`. Building the bridge with CMake overwrites that file (a post-build step in `bridge/CMakeLists.txt`), and every project's post-build step copies it next to the exe. Whenever a delivery changes anything in `bridge/`, say plainly that the bridge must be rebuilt. Supply whole files in a zip of changed files only, with paths from the repository root: only the files changed since the previous zip delivered (owner, 06:22, 5 November 2026), never a cumulative set since some earlier version, and never a bridge file unless that delivery changed the bridge. Logs are the main evidence, so make log lines say exactly what happened.

Start-up times are judged without the debugger: under F9 the NVIDIA driver's DLL loads made SRDemoFMX take ~20 s to its first frame (it looked like an FMX problem; it was not).

## Design notes

- The weaver is C++ only (`SR::CreateDX11Weaver`, `SR::IDX11Weaver1`, with virtual inheritance), hence `bridge/`, an MSVC DLL with a flat C API. The SR DLLs are loaded at run time. `CreateDX11Weaver` is found by its decorated name, or by scanning the exports.
- The C context handle (`newSRContext`) is passed to `CreateDX11Weaver` as `SR::SRContext*`. This isn't documented, but it matches how the C API wraps every other object.
- The bridge owns a child window over the viewport (`WM_NCHITTEST` returns `HTTRANSPARENT`, so the mouse reaches FMX) and a bitblt-model swap chain on it (DISCARD, one sRGB buffer, as Leia's samples). Views are uploaded through typeless textures with sRGB views, and the back buffer's render target view is sRGB too, so the weaver does no sRGB conversion in its shader.
- Start order in `srb_Initialize`: SR context, display, events, lens hint, display rectangle and the GPU driving it (`CreateSRContext`); then the device (FMX's if it is on that GPU, else the bridge's own there); then the weaver (`CreateSRWeaver`). `srb_Probe` does the context and display part alone, on a background thread, before it.
- On FMX's shared device the bridge keeps its own pipeline state in an `ID3DDeviceContextState`, swapped in by `CtxGuard` around every export that touches the context.
- `TSRStereoRenderer` renders the viewport's 3D children into the viewport's own `TContext3D` (`RenderInternal`), once per eye, setting the lights itself from `IViewport3D.Lights`. With zero copy it hands the bound render target (`OMGetRenderTargets` between BeginScene and EndScene; `ResourceToTexture` is private) to `srb_CopyEyeTexture`; otherwise it reads each eye back with `CopyToBits`.
- The off-axis projection is built into the view matrix passed to `SetCameraMatrix`: `RefView * Translation(-eye) * OffAxis` (a shear plus a zoom). FMX's projection is left as it is. The axis signs are measured in view space every frame, and the viewport corner is checked against NDC (1, 1) with the shaders' own formula.
- The eye frame is millimetres from the display centre, x right, y up, z towards the viewer. The window rectangle in mm comes from the child window's screen rectangle, the SR display's desktop rectangle (`FindSRDisplayRect`; the window's monitor only if that is unknown), and the SR display's physical size.
- Full screen is the renderer's own (Raymond Chen's method on the existing window, held at the SR display's rectangle by a `WM_WINDOWPOSCHANGING` subclass), never FMX's `FullScreen`, which re-creates the window.
- Anything that must run soon from the frame loop or a start (the start-problem event, the background check's answer) is posted to the renderer's hidden window (`AllocateHWnd`): posted messages come ahead of paints and timers, while `TThread.ForceQueue` and OnIdle wait until FMX is idle.

## Lessons learned

- `MonitorFromWindow`, `GetMonitorInfo`, `TMonitorInfo` and `MONITOR_DEFAULTTONEAREST` are in `Winapi.MultiMon`, not `Winapi.Windows` (GDEM's `GDEMFetch/ui/GDEMDisplays.pas`, cut down from Sprite3D's `DisplayData`, uses them the same way).
- The IDE rewrites a multi-line post-build event into one line joined with `&&`. An `if exist ... (...) else (...)` followed by `&&` makes the next command part of the `else` branch. Write each step as a parenthesised `(command || echo warning)` instead.
- FMX 3D (`FMX.Types3D`): `SetCameraMatrix` takes the **view** matrix (world to view; `TCamera.CameraMatrix` is a `CreateLookAtDirRH` one). The shaders get `Model * CurrentCameraMatrix * Projection`, and `CurrentCameraInvMatrix` is only used for picking. The projection is cached and rebuilt only on context create or resize, so `SetCameraAngleOfView` and `SetRenderToMatrix` do nothing mid-frame. Put any field of view or off-axis change into the view matrix.
- A self-check built on the same wrong assumption as the code proves nothing. Check against the formula the GPU uses, or against the picture: the owner's OBS recording found what the log could not.
- The SR weaver reports both eyes at one point (0, 100, 600) before the tracker locks on.
- `SR::Display`'s base `WorldObject` has no virtual functions, so its vtable can be mirrored (`DisplayMirror` in the bridge) to call `getLocation` without including `display.h`, which includes OpenCV.
- The SDK's `sr/management/srcontext.h` includes OpenCV through the network headers. Don't include it in the bridge; the stub in `bridge/sr_stub` stands in.
- In Delphi 13, `TContext3D.Width` and `Height` are `Single`.
- `dcc32` in the build output means a 32-bit build, which can't load the 64-bit bridge. `SRBridgeLastError` says so.
- Delphi 11 and earlier leave floating-point exceptions unmasked; driver and SR code expect them masked, so every bridge export masks them (`SRB_ENTRY`).
- `DwmFlush` paces to the compositor, which follows the fastest monitor (the laptop panel, 240 Hz); pace on the SR display's own output (`WaitForVBlank`).
- WM_PAINT and WM_TIMER come only when nothing else is waiting, and OnIdle only when the queue is empty; a constantly repainting FMX (WARP above all) starves all three. Use a posted message.
- FMX's `TDialogService` dialog came up behind the window and with the lens on (unreadable): use a Windows dialog owned by the form, with the lens off.
- Windows' per-exe GPU preference is keyed by the full exe path, so Debug and Release builds have separate settings.
- `HWND_TOPMOST` in the same `SetWindowPos` as the full-screen resize made FMX's D2D canvas fail (`ECannotCreateSwapChain`); apply it later, z-order only.
- `TText3D` with a changing string rendered as streaks; text on a `TPlane` texture works.
- A `TViewport3D` keeps painting itself (a whole render of the scene per repaint) under the bridge's window; skipping that paint doubled SRDemoFMX's frame rate.
- `GetDlgItemInt`'s third parameter is a `var BOOL` in Winapi.Windows; a module-level `var` must come before the code that uses it; when an anonymous method passed to `TThread.Queue`/`ForceQueue` fails to compile, the error is "no overloaded version", not the real one.
- An old bridge DLL reads only the part of a grown record it knows and carries on: add an export that reports the size, and check it.

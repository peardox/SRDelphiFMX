# SimulatedReality: LeiaSR 3D displays from Delphi FireMonkey

This shows an ordinary FMX `TViewport3D` on a LeiaSR (Simulated Reality) eye-tracked lenticular display, in 3D without glasses. The scene, camera and lights stay as designed. A `TSRStereoRenderer` is pointed at the viewport and switched on.

```
 FMX TViewport3D (your scene)
        |  rendered twice per frame, once per tracked eye,
        |  with an off-axis ("window") projection
        v
 TSRStereoRenderer  --CopyToBits-->  side-by-side BGRA buffer
        |
        v  srb_SubmitViews()
 SRFmxBridge.dll (C++, MSVC)
   - child window placed exactly over the viewport (mouse passes through)
   - its own Direct3D 11 device and flip-model swap chain
   - SR::IDX11Weaver1: weave(), then Present()
        |
        v
 SR Platform runtime (SimulatedRealityCore / Displays / DirectX .dll, SR service)
```

## Repository layout

| Path | What |
|---|---|
| `SimulatedReality.groupproj` | Project group; open this in the IDE |
| `SRDemo/` | Test program: `SRDemo.dproj`, `SRDemo.dpr`, and its form in `ui/` |
| `lib/` | Units shared by every project (test and real) |
| `lib/FMX.SRStereoViewport.pas` | `TSRStereoRenderer`, the component |
| `lib/FMX.SRStereoViewport.Reg.pas` | Registers the component for a design-time package |
| `lib/SRFmxBridge.Api.pas` | Delphi imports for the bridge DLL |
| `lib/SimulatedReality.Api.pas` | The SDK's C API (context, display, lens, eye/head/weaver trackers, system events) |
| `lib/SRDiagLog.pas` | Crash-proof log file, plus handlers that record native crashes and the bridge's own log lines in it |
| `FastMM5/` | FastMM5 memory manager (submodule, never changed); full debug mode in Debug builds |
| `bridge/` | C++ source of `SRFmxBridge.dll` and its CMake build |
| `bridge/sr_stub/` | Stand-in for the SDK's `srcontext.h` that keeps OpenCV out of the bridge |
| `dll/` | The compiled `SRFmxBridge.dll`. CMake copies it here, and each project's post-build step copies it next to the exe |
| `tools/pasdoc_check.py` | Checks the Pascal units follow the PasDoc and layout rules |
| `tools/enable_crashdumps.reg`, `disable_crashdumps.reg` | Turn Windows crash dumps for SRDemo.exe on and off |

New programs go in their own folder beside `SRDemo/`, with their forms in a `ui/` folder inside it. Add `..\lib` to the unit search path, copy the post-build event from `SRDemo.dproj`, and add the project to the group.

## Why there is a C++ bridge

The SDK has two layers:

| Layer | Headers | From Delphi |
|---|---|---|
| C API: context, display, eye and head trackers, system events, lens hint | `core_c.h`, `displays_c.h`, `facetrackers_c.h`, ... | Directly, through `lib/SimulatedReality.Api.pas` |
| Weaver, which interlaces the left and right views for the lens | `weaver/dx11weaver.h` (`SR::CreateDX11Weaver`, `SR::IDX11Weaver1`) | No: it is C++ only, uses MSVC virtual inheritance and has no C entry point |

`WeaverC.h` exposes only the lens parameters, not the weaving itself. So a small MSVC DLL does the weaving.

The SDK zip has no `lib/` folder and no DLLs; the runtime DLLs come with the installed SR Platform. The bridge loads them with `LoadLibrary` and finds `SR::CreateDX11Weaver` by its decorated name, scanning the export table if that fails. No SR import libraries are needed.

## Building

### 1. The bridge (Visual Studio 2022, x64)

```bat
cd bridge
cmake -S . -B build -G "Visual Studio 17 2022" -A x64 -DLEIASR_SDKROOT=C:\path\to\simulatedreality-SDK-1.34.5.6862-win64-Release
cmake --build build --config Release
```

This builds `SRFmxBridge.dll` and copies it to `dll\`. It must be built with MSVC, because the weaver interface depends on the MSVC C++ ABI. `LEIASR_SDKROOT` is the unzipped SDK; its `Install.bat` sets it as an environment variable. If CMake's include paths change, delete `bridge\build` first, because CMake caches them.

### 2. Delphi (13, FMX, Windows 64-bit)

Open `SimulatedReality.groupproj` and build SRDemo. The project targets Windows 64-bit only, because the SR runtime is 64-bit only. The project's manifest is Per-Monitor v2 DPI aware; without that, Windows scales the window and the woven pattern no longer lines up with the panel's pixels. After each build, `dll\SRFmxBridge.dll` is copied next to the exe. If it isn't there, the build output shows a warning.

The SR Platform runtime must be installed, with its service running, and the display connected in extended mode at its native resolution.

## Using it in a program

```pascal
uses FMX.SRStereoViewport;

procedure TfrmMain.FormCreate(Sender: TObject);
begin
  FStereo := TSRStereoRenderer.Create(Self);
  FStereo.Viewport := Viewport3D1;
  FStereo.FocusDistance := 20;    // world units from the camera to the "glass"
  FStereo.OnError := StereoError; // e.g. no SR runtime: the viewport stays 2D
  FStereo.OnLog := StereoLog;     // diagnostics, see below
  FStereo.Active := True;         // starts once the form is shown
end;

procedure TfrmMain.FormClose(Sender: TObject; var Action: TCloseAction);
begin
  FStereo.Active := False;        // shut SR down while the window still exists
end;
```

| Property | Meaning |
|---|---|
| `FocusDistance` | The plane this many units in front of the viewport's camera lies on the display glass. Nearer objects come out of the screen and farther ones go behind it. The default, 20, suits FMX's usual camera at Z = -20 looking at the origin. |
| `EyeSeparationScale` | 1 is physically correct. Less is gentler; more exaggerates depth. |
| `LoopMode` | `lmIdle`: continuous and paced by the vertical blank; it chains any existing `Application.OnIdle`. `lmTimer`, or `lmManual` where the program calls `RenderFrame`. |
| `VSync`, `LatencyFrames` | Present pacing, and the latency hint for SR's eye prediction. |
| `LogInterval` | Milliseconds between summary lines on `OnLog` (default 1000; 0 for none). |
| `OnLog`, `OnEyesUpdated`, `OnSystemEvent`, `OnError` | Diagnostics, eye positions in mm, SR events (UserFound/Lost, LensOn/Off, ContextInvalid...), failures. |

### How the projection works

The bridge reports where the viewport sits on the panel, in millimetres, in the same display-centred frame the eye tracker uses. Each eye's camera is the reference camera moved by the eye's offset. A view-space shear, passed through `TContext3D.SetCameraMatrix`, turns FMX's symmetric frustum into the asymmetric "window" frustum. This is Kooima's generalised perspective projection, the same as the SDK's DX11 sample. A zoom in the same matrix gives each eye its true field of view. FMX's own projection is never changed, because `SetCameraAngleOfView` turned out to have no effect on `CurrentProjectionMatrix`. The code measures FMX's axis and handedness conventions from the context's own matrices every frame instead of assuming them, and checks the result against the viewport's corner.

## The log

With `OnLog` set (SRDemo shows it under the toolbar, with **Copy log** and **Clear log** buttons), the renderer reports:

- **At start:** the SR platform version; the display's resolution, physical size and recommended view size; where the viewport sits on the display in mm; and the settings.
- **Every `LogInterval`, three lines:**
  1. **Frames and eyes:** frames per second and the worst frame time; how many frames were woven, 2D or hidden; the eye positions and their separation, with `NOMINAL` when there was no valid tracking; and the reference camera's position.
  2. **Projection:** the viewport rectangle in mm and the view size in pixels; the measured axis signs, the reference field of view and the world-to-mm scale; and for each eye the zoom, the shear, and where the viewport's top-right corner lands in normalised device coordinates. That last value should be (1.0000, 1.0000); anything else means the projection is wrong.
  3. **Bridge:** frames presented, woven, 2D and hidden; context re-creations; caught exceptions; the weaver's latency; the last `Present` result; and the back buffer size.
- **Also:** every SR system event, and every error.

## Finding crashes

A Debug build of SRDemo writes these files beside the exe:

| File | Contents |
|---|---|
| `SRDemo.log` | Everything SRDemo logs, written line by line so it survives a crash: the renderer's log; the bridge's own steps (prefixed `[bridge tNNNN]` with the thread id), including SR system events as they arrive on SR's threads; `FIRST CHANCE` lines for serious hardware exceptions (access violation, stack overflow, heap corruption...) with the module and offset where they happened; `UNHANDLED` for the exception that ended the program; and `FATAL` lines from the bridge for `abort()`, `std::terminate`, pure virtual calls and CRT invalid parameters. A run that ended normally finishes with `Log closed normally`. |
| `oldlogs\` | Earlier runs' `SRDemo.log` and `SRDemo_FastMM.log`, named with the time they were last written; the newest 20 of each are kept |
| `SRDemo_FastMM.log` | FastMM5's reports: corrupted, double-freed or freed-then-used blocks of Delphi memory, with stack traces of where each block was allocated and freed, and leaks at exit. Present only if FastMM found something. |

How the pieces help:

- **FastMM5 runs in full debug mode in Debug builds.** The project defines `FastMM_FullDebugModeWhenDLLAvailable`, and the build copies `FastMM_FullDebugMode64.dll` from the submodule next to the exe. The map file is Detailed, so stack traces show units and lines. SRDemo also scans every debug block for corruption every 30 frames, so damage is caught close to when it happens. FastMM5 covers only Delphi's memory, not the bridge's or SR's C++ heaps.
- **Stage tracing.** The renderer traces its first 5 frames stage by stage (`TraceFrames`), so the last line before a crash shows the stage it died in.
- **Skip switches.** The **Diagnostics** row in SRDemo skips eye tracking, rendering or weaving, to find which stage is at fault without rebuilding.
- **Stereo images.** **Show:** in the same row weaves one of the side-by-side images from `media/` (left view in the left half) exactly as given, testing the weaving apart from the 3D rendering. **Fixed 63 mm eye separation** (on by default in SRDemo) uses 63 mm, keeping the tracked head position, instead of the tracker's measured separation. Images are letterboxed or pillarboxed in black to keep their shape.
- **When the log simply stops**, with no `FIRST CHANCE`, `UNHANDLED` or `FATAL` line, the program ended in a way no handler sees (a fail-fast). Windows still records it: *Event Viewer > Windows Logs > Application*, as an "Application Error" naming the faulting module, exception code and offset. With `tools/enable_crashdumps.reg` imported, Windows also keeps a full dump in `%LOCALAPPDATA%\CrashDumps`.

## Constraints of this version

- 2D controls must not overlap the viewport. The woven image is a native child window above the FMX surface. Mouse input passes through to FMX, but FMX controls drawn over that area are hidden.
- One GPU-to-CPU-to-GPU copy per frame. `CopyToBits` reads each eye back and the bridge uploads it again. A zero-copy path is possible later: render into a DXGI-shared texture on FMX's DX11 device and open it in the bridge.
- One SR viewport per process.
- The lens covers the whole panel. While it is on, everything outside the woven viewport (other windows, the desktop, the program's own 2D controls) is seen through it unwoven, and looks blurred. That's the hardware, not the program; the SDK's own windowed samples behave the same way. A full-screen viewport avoids it.
- Starting blocks for up to `InitTimeout` seconds (default 5) while it waits for the SR service.
- After an SR context loss (a service restart), the bridge shows the left view in 2D and retries every 3 seconds.
- Every bridge export masks floating-point exceptions while it runs and catches C++ exceptions, so neither reaches Delphi.
- In `lmIdle` mode, if other code replaces `Application.OnIdle` after the renderer starts and keeps chaining to it, don't free the renderer before that code unhooks. Otherwise use `lmTimer` or `lmManual`.

## Checks on the hardware

1. The status line shows **Weaving**, with eyes at roughly (+-32, 0, 500-700) mm that follow head movement.
2. **Depth:** the spheres on the right (negative Z) come out of the screen, and the back wall sits behind it. If depth is inverted everywhere, swap the two `RenderEye` destinations in `RenderFrame`.
3. **Parallax:** moving the head left makes near objects slide right against the back wall, as through a window. If an axis goes the wrong way, the log's `cal R U F` signs show what was measured.
4. Moving or resizing the window, or going full screen (F11), keeps the image locked to the viewport.
5. Unplugging the USB cable, or stopping the SR service, shows events in the log and a 2D fallback, then recovery.

## Notes for Claude

These are the working rules for this project, as in GDEM. Read this README, then `CLAUDE.md`.

### Delivering work

- Supply whole files, never patches or diffs, in a zip of only the new and changed files, with paths relative to the repository root.
- Don't mention that changes are uncommitted or unpushed, or being unable to compile.
- The owner's working copy may be ahead of GitHub; build on the files most recently supplied.
- Update this README when features or requirements change.

### Code

- Delphi 13, FMX, Windows 64-bit (the SR runtime exists only there). `lib/` units still compile for Win32, so a design-time package loads in the IDE.
- Shared units go in `lib/`; a program's forms go in its own `ui/` folder; the bridge DLL goes in `dll/`.
- Document all Pascal in PasDoc format (`@abstract`, `@param`, `@returns`, `@link`), with private fields included. Before delivering, run `python3 tools/pasdoc_check.py` from the root; it should print `No problems found`.
- Source files are ASCII only. Keep the UTF-8 byte order mark on `.dproj` and `.groupproj` files.
- The bridge must build with MSVC x64. Every export masks floating-point exceptions (`SRB_ENTRY`) and catches C++ exceptions.

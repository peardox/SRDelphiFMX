# Lenticular: glasses-free 3D displays from Delphi FireMonkey

This shows an ordinary FMX `TViewport3D` on an eye-tracked lenticular (glasses-free 3D) display, in 3D without glasses. The scene, camera and lights stay as designed. A `TLenticularStereoRenderer` is pointed at the viewport and switched on.

```
 FMX TViewport3D (your scene)
        |  rendered twice per frame, once per tracked eye,
        |  with an off-axis ("window") projection
        v
 TLenticularStereoRenderer  --lnb_CopyEyeTexture (GPU to GPU, per eye)-->  bridge's view texture
        |              (fallback: CopyToBits -> CPU buffer -> lnb_SubmitViews)
        v  lnb_PresentViews()
 LenticularBridge.dll (C++, MSVC)
   - child window placed exactly over the viewport (mouse passes through)
   - FMX's own Direct3D 11 device (zero copy), with a pipeline state of its own, or a device of its own
   - its own swap chain (bitblt model, as the vendor's samples)
   - the runtime's weaver: weave(), then Present()
        |
        v
 The display runtime (its DLLs, loaded only by the bridge, and the display service)
```

The repository also holds two component sets in packages, **Spritely** (camera components for Gorilla3D) and **Lenticular** (`TLenticularDisplay`: the display started for any renderer), with **StereoModel**, which shows a Gorilla3D model on the display through both, and **ProjectionTest**, the Spritely projection's test bed. They came from peardox/StereoModel; see [Spritely, Lenticular and StereoModel](#spritely-lenticular-and-stereomodel) and `StereoModel/README.md`.

## Repository layout

| Path | What |
|---|---|
| `Lenticular.groupproj` | Project group; open this in the IDE |
| `LenticularDemoFMX/` | Test program: `LenticularDemoFMX.dproj`, `LenticularDemoFMX.dpr`, and its form in `ui/` |
| `LenticularDemoVCL/` | The demo as a VCL program: VCL controls, and a 3D scene drawn by the bridge itself on the GPU (`lnb_RenderScene`), with no read-back; its form in `ui/` |
| `StereoModel/` | StereoModel (Gorilla3D, through the Spritely and Lenticular packages): `StereoModel.dproj`, its form in `ui/`, helpers in `common/`, and its own `README.md` (the components, the packages, the program) |
| `ProjectionTest/` | The test bed of `TSpritelyProjection`: `ProjectionTest.dproj`, its form in `ui/`, the measuring in `common/` |
| `MoviePlayerFMX/` | The 3D film player, so far showing one side-by-side frame (half side-by-side, as films are encoded, or full): `MoviePlayerFMX.dproj`, `MoviePlayerFMX.dpr`, and its form in `ui/` |
| `lib/` | Units shared by every project |
| `lib/Lenticular.StereoViewport.pas` | `TLenticularStereoRenderer`, the component |
| `lib/Lenticular.StereoFrame.pas` | One side-by-side frame, full or half side-by-side, as raw pixels: decides the layout, fits the two views for weaving and gives the 2D left view; no FMX or VCL |
| `lib/Lenticular.MovieRenderer.pas` | `TLenticularMovieRenderer`, a `TLenticularStereoRenderer` that weaves an `Lenticular.StereoFrame` frame instead of the scene (`SupplyViews`) |
| `lib/Lenticular.VideoDecoder.pas` | Plays a film with FFmpeg: a reader and picture and sound decoders on threads, pictures to BGRA, sound to `Lenticular.AudioOutput`, the pictures timed by the sound; loads FFmpeg once, checking each DLL; no FMX or VCL |
| `lib/Lenticular.AudioOutput.pas` | Plays sound on the default output device through WASAPI (shared, event driven, float) from a ring buffer, and gives the film time of the sound being heard as a clock; no FMX or VCL |
| `lib/Lenticular.StartProblem.pas` | What went wrong when starting the display, and the ready-made dialog that asks the user what to do; no FMX or VCL |
| `lib/Lenticular.GpuPreference.pas` | Windows' per-program GPU preference (Settings > System > Display > Graphics); no FMX or VCL |
| `lib/Lenticular.StereoImage.pas` | Loads a side-by-side image (or draws a numbered test pattern) and fits it into views of any size, for LenticularDemoVCL; no FMX |
| `lib/Lenticular.StereoViewport.Reg.pas` | Registers the component for a design-time package |
| `lib/LenticularBridge.Api.pas` | Delphi imports for the bridge DLL, used by the demos and by the Lenticular package; it compiles on every platform, the imports themselves only on Windows |
| `lib/Spritely.*.pas` | The Spritely set (Gorilla3D): `TSpritelyOrbitalCamera`, `TSpritelyProjection`, and `Spritely.Reg` (design time) |
| `lib/Lenticular.Display*.pas`, `Lenticular.Storage.pas`, `Lenticular.Reg.pas` | The Lenticular set: `TLenticularDisplay`, its settings (`%APPDATA%\Peardox\Lenticular.json`), the JSON storage, and the registration (design time) |
| `lib/icons/`, `lib/*.Reg.dcr` | The two sets' palette icons and the resources made from them |
| `packages/` | `Spritely` / `dclSpritely` and `Lenticular` / `dclLenticular`, written by `tools/gen_packages.py` |
| `models/` | Test models for StereoModel and ProjectionTest (`models/licensed/`, ignored by git, for any that may not be published) |
| `lib/Lenticular.Settings.pas` | Saved settings (`%APPDATA%\Peardox\LenticularDemos.json`), read and written with the RTL's System.JSON |
| `ffmpeg-headers/` | FFmpeg 8.1 Delphi headers from DelphiFFmpeg.com (BSD-style licence, see CREDITS.md), with every import marked `delayed`; MoviePlayerFMX only |
| `dll/ffmpeg/` | FFmpeg's 64-bit GPL shared DLLs, supplied by each developer (git ignores them) |
| `CREDITS.md` | Licences of everything used |
| `lib/Lenticular.DiagLog.pas` | Crash-proof log file, plus handlers that record native crashes and the bridge's own log lines in it |
| `FastMM5/` | FastMM5 memory manager (submodule, never changed); full debug mode in Debug builds |
| `bridge/` | C++ source of `LenticularBridge.dll` and its CMake build |
| `bridge/sdk_stub/` | Stand-in for the SDK's `srcontext.h` that keeps OpenCV out of the bridge |
| `media/hsbs/` | Half side-by-side frames for MoviePlayerFMX (kept out of `media/` itself, whose images LenticularDemoFMX lists) |
| `dll/` | The compiled `LenticularBridge.dll`. CMake copies it here, and each project's post-build step copies it next to the exe |
| `tools/pasdoc_check.py` | Checks the Pascal units follow the PasDoc and layout rules |
| `tools/pasdoc.bat` | Builds the PasDoc reference: `docs/html/` and `docs/chm/`, each with `api/` and a folder per program (git ignores both) |
| `tools/pasdoc-dark.css`, `pasdoc-chm-dark.css` | Dark colours that `pasdoc.bat` adds to the HTML (when the system is dark) and the `.chm` files (always) |
| `tools/gen_packages.py`, `gen_icons.py`, `gen_icon_res.py` | Write the four packages, the palette icons and the `.dcr` files |
| `tools/gen_demo_scene.py`, `gen_dolly_hallway.py` | Write the test models `DemoScene*.glb` and `DollyHallway.glb` |
| `tools/enable_crashdumps.reg`, `disable_crashdumps.reg` | Turn Windows crash dumps for LenticularDemoFMX.exe on and off |

New programs go in their own folder beside `LenticularDemoFMX/`, with their forms in a `ui/` folder inside it. Add `..\lib` to the unit search path, copy the post-build event from `LenticularDemoFMX.dproj`, and add the project to the group. A program built on the Spritely or Lenticular packages (as StereoModel is) needs no `..\lib` path: their DCUs come from Delphi's Dcp folder.

## Why there is a C++ bridge

The SDK has two layers:

| Layer | Headers | From Delphi |
|---|---|---|
| C API: context, display, eye and head trackers, system events, lens hint | the SDK's C headers | Could be, but is not: the bridge uses what is needed, so the runtime's names stay in the bridge |
| Weaver, which interlaces the left and right views for the lens | the SDK's DX11 weaver header | No: it is C++ only, uses MSVC virtual inheritance and has no C entry point |

The SDK's C weaver header exposes only the lens parameters, not the weaving itself. So a small MSVC DLL does the weaving.

The SDK zip has no `lib/` folder and no DLLs; the runtime DLLs come with the installed display runtime. The bridge loads them with `LoadLibrary` and finds the weaver's factory function by its decorated name, scanning the export table if that fails. No import libraries are needed.

## Building

### 1. The bridge (Visual Studio 2022, x64)

```bat
cd bridge
cmake -S . -B build -G "Visual Studio 17 2022" -A x64 -DLENTICULAR_SDKROOT=C:\path\to\the-runtime-SDK
cmake --build build --config Release
```

This builds `LenticularBridge.dll` and copies it to `dll\`. It must be built with MSVC, because the weaver interface depends on the MSVC C++ ABI. `LENTICULAR_SDKROOT` is the unzipped SDK; its `Install.bat` sets it as an environment variable. If CMake's include paths change, delete `bridge\build` first, because CMake caches them.

### 2. Delphi (13, FMX, Windows 64-bit)

Open `Lenticular.groupproj` and build LenticularDemoFMX. The project targets Windows 64-bit only, because the display runtime is 64-bit only. The project's manifest is Per-Monitor v2 DPI aware; without that, Windows scales the window and the woven pattern no longer lines up with the panel's pixels. After each build, `dll\LenticularBridge.dll` is copied next to the exe. If it isn't there, the build output shows a warning.

The display runtime must be installed, with its service running, and the display connected in extended mode at its native resolution.

### 3. The reference (PasDoc, optional)

`tools\pasdoc.bat` (run from anywhere) writes the PasDoc reference as HTML in `docs\html\` and as HTML Help in `docs\chm\`, each with one folder for the API and one per program:

| Folder | What |
|---|---|
| `api\` | Every unit in `lib/` except the design-time registration units (`*.Reg`) and the Spritely set. Start at `docs\html\api\index.html`. |
| `spritely\` | The Spritely set (`lib/Spritely.*`, without `Spritely.Reg`). |
| `LenticularDemoFMX\`, `LenticularDemoVCL\`, `MoviePlayerFMX\`, `StereoModel\`, `ProjectionTest\` | One program: its `.dpr`, its forms and helpers and the `lib/` units it uses, all read from the `.dpr`'s uses clause, so the `@link`s in its comments resolve. StereoModel and ProjectionTest take the components from the packages, so theirs hold only their own units. |

The programs are found, not listed: any folder in the root holding `<folder>\<folder>.dpr` gets its own reference. It needs `pasdoc` on the PATH (or `PASDOC` set to its full path; releases at https://github.com/pasdoc/pasdoc/releases/), and, for the `.chm` files, Microsoft HTML Help Workshop's `hhc.exe` (or `HHC` set to its full path); without `hhc.exe` the HTML Help projects are written but not compiled. `docs\html` and `docs\chm` are deleted first, so nothing from an earlier run is left. The view is Windows 64-bit (`MSWINDOWS`, `WIN64`, `CPUX64` defined), Release (FastMM5's full debug mode undefined).

Dark colours are added after each run, appended to the `pasdoc.css` PasDoc wrote (so PasDoc's own stylesheet is used as it is, and no copy of it, GPL, is kept here). `tools/pasdoc-dark.css` is for the HTML: dark only when the browser or system asks for it, light otherwise. `tools/pasdoc-chm-dark.css` is for the `.chm` files: always dark, because the HTML Help viewer (the old Internet Explorer engine) can neither ask nor read CSS custom properties. Both cover PasDoc 1.0 (Bootstrap) and 0.16 and earlier. `set PASDOC_DARK=0` leaves them out.

## Using it in a program

```pascal
uses Lenticular.StereoViewport;

procedure TfrmMain.FormCreate(Sender: TObject);
begin
  FStereo := TLenticularStereoRenderer.Create(Self);
  FStereo.Viewport := Viewport3D1;
  FStereo.FocusDistance := 20;    // world units from the camera to the "glass"
  FStereo.OnError := StereoError; // e.g. no display runtime: the viewport stays 2D
  FStereo.OnStartProblem := StereoStartProblem; // ask: no glasses-free 3D, try again, or it anyway
  FStereo.OnLog := StereoLog;     // diagnostics, see below
  FStereo.Active := True;         // starts once the form is shown
end;

procedure TfrmMain.FormClose(Sender: TObject; var Action: TCloseAction);
begin
  FStereo.Active := False;        // shut the display down while the window still exists
end;
```

| Property | Meaning |
|---|---|
| `FocusDistance` | The plane this many units in front of the viewport's camera lies on the display glass. Nearer objects come out of the screen and farther ones go behind it. The default, 20, suits FMX's usual camera at Z = -20 looking at the origin. |
| `EyeSeparationScale` | 1 is physically correct (the demos always use 1). Less is gentler; more exaggerates depth. |
| `LoopMode` | `lmIdle`: continuous and paced by the vertical blank; it chains any existing `Application.OnIdle`. OnIdle comes only when the message queue is empty, so a watchdog thread posts a frame message whenever none has started for 25 ms (FMX repainting without a break, as with a heavy scene in a Debug build, would otherwise stop the frames); the log notes it every 5 s while it happens. `lmTimer`, or `lmManual` where the program calls `RenderFrame`. |
| `VSync`, `LatencyFrames` | Present pacing, and the latency hint for the runtime's eye prediction. |
| `LookAround` | On (the default) draws from where the head is, so you can look around objects. Off draws from a fixed viewer in front of the viewport: depth, but no motion with the head. |
| `EyeSeparationMM` | Use this separation (63 mm, say) instead of the tracker's measured one, keeping the tracked head position; 0 uses the tracked eyes as they are |
| Bridge's device | `lnb_GetDevice` gives the bridge's `ID3D11Device` (not AddRef'd, valid until `lnb_Finalize`), so a program that draws with OpenGL can make its eye textures on it, draw into them through `WGL_NV_DX_interop2`, and weave them with `lnb_CopyEyeTexture` and `lnb_PresentViews`: zero copy without sharing a device. From bridges built 7 November 2026, 21:00 on |
| Lens at start, actual lens | The bridge makes the runtime's context with the lens as last asked with `lnb_SetLens` (the runtime's `newSRContextLensPreference`, where the runtime has it), so a program that asks for the lens off before `lnb_Initialize` is never blurred while the display starts; `lnb_GetLensState` gives the lens as it actually is (the runtime's `isLensEnabled`: 1 on, 0 off, -1 not known). Both from bridges built 7 November 2026, 17:00 on; the demos are unchanged (they ask for the lens on) |
| `LensMode`, `LensSwitchDelay` | `lensOffOverControls` (the default) turns the display's lens off while the pointer is over anything on the 3D display other than the viewport (the program's controls, drop-down lists, other programs), so they are sharp; the viewport is drawn flat meanwhile. The pointer must stay on one side for `LensSwitchDelay` ms (250) first, and nothing switches while a mouse button is held. In `FullScreen` the lens stays on. `lensAlwaysOn`, `lensAlwaysOff` force it. |
| `SettleTime` | Milliseconds (300) the tracked eyes must be found and steady before 3D is shown, at start and after tracking is lost for over a second. Until then the viewport is drawn flat from a fixed viewer, so nothing slides while the tracker searches; the lens is not switched for this. 0 shows 3D at once. |
| `FullScreen` | Covers the whole 3D display with the form, borderless, on the form's existing window in physical pixels, topmost so the taskbar stays hidden. The window is held there from its window procedure, because FMX re-sizes it from rounded logical bounds (at 150% it put it at x = -1, one pixel onto the next monitor, and the weave went wrong). Use this, not the form's own `FullScreen`: FMX re-creates the window for that and, at display scaling above 100%, sizes it in steps, and the weaver the display restarts with wove for the wrong size. Set before the form is shown, it is applied when the display starts. |
| `ViewportOn3DDisplay` | Read only. While the viewport's centre is on another monitor, the lens is off and the viewport is drawn flat; each change is logged. |
| `PlaceFormOnSRDisplay` | On (the default) moves the form onto the 3D display at start-up if it opened on another monitor |
| `ZeroCopy` | On (the default): each eye is copied on the GPU into the bridge's view texture; see "Constraints" below. |
| `InitTimeout` | Seconds (5) to wait for the display service and display when starting; the wait is on a background thread. |
| `LogInterval` | Milliseconds between summary lines on `OnLog` (default 1000; 0 for none). |
| `RuntimeInstalled`, `StopWhenDegraded`, `AcceptDegraded`, `OnStartProblem`, `StartProblem` | See "Starting glasses-free 3D" below. |
| `OnLog`, `OnEyesUpdated`, `OnSystemEvent`, `OnError` | Diagnostics, eye positions in mm, runtime events (UserFound/Lost, LensOn/Off, ContextInvalid...), failures. |

### How the projection works

The bridge reports where the viewport sits on the panel, in millimetres, in the same display-centred frame the eye tracker uses. FMX draws with `Model * CameraMatrix * Projection`, where the camera matrix is the view matrix. Its projection is fixed while a frame is drawn, because it is rebuilt only when the context is resized. So each eye's view is the reference camera's view, moved to the eye, followed by a shear and a zoom. The shear turns FMX's symmetric frustum into the asymmetric "window" frustum, and the zoom gives the eye's true field of view. This is Kooima's generalised perspective projection, the same as the SDK's DX11 sample. Every frame checks that the viewport's corner lands on the image's corner, using the GPU's own formula.

## Starting glasses-free 3D

### Computers without the display, and the user's choice

`TLenticularStereoRenderer.RuntimeInstalled` (or `LenticularRuntimeInstalled` in `lib/LenticularBridge.Api.pas`) says, quickly, whether this computer has the display runtime: it asks the bridge (`lnb_RuntimeInstalled`), which looks for the runtime's DLLs without running them, so without `LenticularBridge.dll` beside the executable the answer is no. Where it has not, starting does nothing and raises no event, not even `OnError` (`StartProblem` is `spNotInstalled`, and the log says so): a program can hide everything to do with glasses-free 3D and run as if it had no glasses-free 3D support. Where it has, whether to use it is the user's choice, kept as `useGlassesFree3D` in the settings file (default true): on, the program starts the display and anything that goes wrong is handled as below; off, the display is not started until the user turns it on. Both demos work this way: LenticularDemoFMX's "Glasses-free 3D" box and LenticularDemoVCL's Weave box are the choice and are saved when the user changes them (a failed start unticks them without changing the saved choice), and both are hidden where the display runtime is not installed.

### Starting without a freeze

`lnb_Initialize` waits on the calling thread for the display service and display, up to `InitTimeout` (5 s), which would freeze the window. So the waiting is done first, on a background thread: `lnb_Probe` in the bridge loads the runtime, tries for an runtime context and a ready display until `InitTimeout`, and deletes the context again (about a quarter of a second when all is well). Meanwhile the program runs normally without glasses-free 3D. When the answer comes (posted to the renderer's hidden window), the display is started on the main thread, which is then quick: the service and display are known to be there and the runtime is loaded. So the program may appear flat for a moment and then switch to glasses-free 3D. With the service not running (`spNoService`) or no 3D display (`spNoDisplay`) the start-problem dialog comes up when the check gives up. LenticularDemoVCL does the same.

### When the display cannot start, or would run badly

If the display cannot start (`LenticularBridge.dll` missing, no 3D display, the display service not running), or it starts but FMX is drawing in software, on a GPU that does not drive the 3D display, or not with Direct3D 11, the program carries on without glasses-free 3D: FMX draws the viewport itself, as an ordinary 3D view on a flat screen, at full speed. Only the display weaving is lost, not the 3D scene. For the GPU cases the display is started, checked and stopped again at once (`StopWhenDegraded`, on by default), because 3D through a software renderer or across two GPUs slows the whole program down, not only the picture. `StartProblem` says what happened (`TLenticularStartProblem` in `lib/Lenticular.StartProblem.pas`).

`OnStartProblem` is then called from the message queue, with the display off, so a dialog shown from it is readable. The handler chooses `scContinueWithout3D` (the default; also what happens with no handler), `scRetry` (start again, for when the cause has been fixed) or, for the GPU cases only, `scContinueDegraded`, which sets `AcceptDegraded` and starts again with the problem accepted (`OnGpuWarning` is raised then); or `scExit`, which ends the program (`Application.Terminate`) so the display set-up can be fixed first. `AskStartProblem` in `lib/Lenticular.StartProblem.pas` is a ready-made dialog for it, usable from FMX or VCL: a Windows task dialog, modal and centred on the program's window, with a button for each choice and, when the Windows GPU preference would fix it (`CanFixGpu`), a check box to set the high-performance GPU. Exit is always offered. Where task dialogs are not available it falls back to a message box: Abort = exit, Retry, Ignore = without glasses-free 3D; or, when glasses-free 3D anyway is possible, Cancel = without, Try Again, Continue = anyway (a message box has only three buttons, so no Exit there). The wording is about glasses-free 3D, not 3D in general: a 3D scene is still shown, flat, without it.

A stereo image has no single view to fall back on, so it needs one picked: `CopyLeftView` gives the left eye's half of the image set with `ShowStereoImage`. LenticularDemoFMX shows it over the viewport whenever the display is off (also when Glasses-free 3D is unticked). LenticularDemoVCL asks only "without glasses-free 3D" or "try again", since its scene is drawn by the bridge. `LenticularDemoFMX /warp` shows the whole path on any machine; renaming `LenticularBridge.dll`, or unplugging the 3D display, shows the start-failure version.

## The log

With `OnLog` set (LenticularDemoFMX shows it under the toolbar, with **Copy log** and **Clear log** buttons), the renderer reports:

- **At start:** the display runtime version; the display's resolution, physical size and recommended view size; where the viewport sits on the display in mm; and the settings.
- **Every `LogInterval`, three lines:**
  1. **Frames and eyes:** frames per second and the worst frame time; how many frames were woven, 2D or hidden; the eye positions and their separation, with `NOMINAL` when there was no valid tracking; and the reference camera's position.
  2. **Projection:** the viewport rectangle in mm and the view size in pixels; the measured axis signs, the reference field of view and the world-to-mm scale; and for each eye the zoom, the shear, and where the viewport's top-right corner lands in normalised device coordinates. That last value should be (1.0000, 1.0000); anything else means the projection is wrong.
  3. **Bridge:** frames presented, woven, 2D and hidden; context re-creations; caught exceptions; the weaver's latency; the last `Present` result; and the back buffer size.
- **Also:** every runtime event, and every error.

## Settings

Both demos keep their settings in `%APPDATA%\Peardox\LenticularDemos.json` (written with the RTL's System.JSON): whether to use glasses-free 3D (`useGlassesFree3D`, on by default), the eye separation (63 mm by default; 0 = as tracked), the focus distance, look-around, the weaver's latency, when the lens is on, the last image shown and full screen. Every change is saved straight away. A missing setting keeps its default. (`eyeSeparationScale` is still in the file for older versions; the demos keep it at 1.) In both demos **Settings...** sets the eye separation, in a small dialog centred on the window, with the lens off while it is open. In LenticularDemoFMX the second row has **Look-around**, **Latency** (the runtime's default or 1 to 4 frames), **Lens** and **Show:** (the 3D scene or a side-by-side image from `media/`).

## Multiple monitors

At start-up the bridge finds where the 3D display is on the desktop and logs it, with the method it used. It asks the runtime first (its display location, called without including the SDK's OpenCV-dependent header, and checked against the C API before being trusted). If that fails, it matches monitors by resolution and physical size; every monitor it saw is logged. If the window opened on another monitor, it is moved onto the 3D display (still maximised if it was). Millimetre positions are measured against the 3D display, wherever the window is.

## Finding crashes

A Debug build of LenticularDemoFMX writes these files beside the exe:

| File | Contents |
|---|---|
| `LenticularDemoFMX.log` | Everything LenticularDemoFMX logs, written line by line so it survives a crash: the renderer's log; the bridge's own steps (prefixed `[bridge tNNNN]` with the thread id), including runtime events as they arrive on the runtime's threads; `FIRST CHANCE` lines for serious hardware exceptions (access violation, stack overflow, heap corruption...) with the module and offset where they happened; `UNHANDLED` for the exception that ended the program; and `FATAL` lines from the bridge for `abort()`, `std::terminate`, pure virtual calls and CRT invalid parameters. A run that ended normally finishes with `Log closed normally`. |
| `oldlogs\` | Earlier runs' `LenticularDemoFMX.log` and `LenticularDemoFMX_FastMM.log`, named with the time they were last written; the newest 20 of each are kept |
| `LenticularDemoFMX_FastMM.log` | FastMM5's reports: corrupted, double-freed or freed-then-used blocks of Delphi memory, with stack traces of where each block was allocated and freed, and leaks at exit. Present only if FastMM found something. |

How the pieces help:

- **FastMM5 runs in full debug mode in Debug builds.** The project defines `FastMM_FullDebugModeWhenDLLAvailable`, and the build copies `FastMM_FullDebugMode64.dll` from the submodule next to the exe. The map file is Detailed, so stack traces show units and lines. LenticularDemoFMX also scans every debug block for corruption every 30 frames, so damage is caught close to when it happens. FastMM5 covers only Delphi's memory, not the bridge's or the runtime's C++ heaps.
- **Stereo images.** **Show:** weaves one of the side-by-side images from `media/` (left view in the left half) exactly as given, testing the weaving apart from the 3D rendering. **A fixed eye separation** (63 mm by default, set with Settings...) is used instead of the tracker's measured one, keeping the tracked head position; 0 uses the tracker's. Images are letterboxed or pillarboxed in black to keep their shape.
- **When the log simply stops**, with no `FIRST CHANCE`, `UNHANDLED` or `FATAL` line, the program ended in a way no handler sees (a fail-fast). Windows still records it: *Event Viewer > Windows Logs > Application*, as an "Application Error" naming the faulting module, exception code and offset. With `tools/enable_crashdumps.reg` imported, Windows also keeps a full dump in `%LOCALAPPDATA%\CrashDumps`.

## Spritely, Lenticular and StereoModel

Two component sets, each a runtime and a design-time package in `packages/`, each on its own palette page. **Neither uses the other**, so either may be installed alone; StereoModel uses both.

| Set | Palette page | Components | Needs |
|---|---|---|---|
| Spritely | Spritely (green icons) | `TSpritelyOrbitalCamera` (an orbit camera for a Gorilla3D viewport: fits, subject, target depth), `TSpritelyProjection` (any projection drawn: lens, dolly zoom, shift and rise, orthographic, oblique and the isometric family) | rtl, fmx, Gorilla3D 1.5.3 |
| Lenticular | Lenticular (blue icons) | `TLenticularDisplay` (finds and starts the display without a freeze, follows the eyes and weaves frames or eye textures a renderer hands it) | rtl, fmx |

To install, in `Lenticular.groupproj`: build **Spritely** and **Lenticular** for every platform you build programs for and always for Win32 (the IDE's), then build and **Install** **dclSpritely** and **dclLenticular** (Win32). Their DCUs go to `$(BDSCOMMONDIR)\Dcp\<platform>`, so programs need no search path. After a change in `lib/` to one of these units, rebuild its package for each platform used; after a change to a `*.Reg` unit or the icons, reinstall its design package too.

`TLenticularDisplay` is not `TLenticularStereoRenderer`: the renderer draws an FMX `TViewport3D` for the display itself (the demos), while `TLenticularDisplay` only starts the display and weaves what it is given (StereoModel draws its eyes with Gorilla3D). Both talk to the same `LenticularBridge.dll` through `LenticularBridge.Api`; StereoModel's post-build copies it from `dll\` as the demos' do.

StereoModel, ProjectionTest, the components and the packages are described in full in `StereoModel/README.md`.

## MoviePlayerFMX

A 3D film player. 3D films are usually encoded **half side-by-side** (HSBS): each eye's view squeezed to half its width, the two side by side in a normal 16:9 frame, left eye on the left, usually with nothing in the file to say so but its name. **Open...** (or **Ctrl+O**, also in full screen) plays a film (`.mkv`, `.mp4`, `.mov`, `.ts` and the like, through FFmpeg) or shows a single frame (PNG or JPEG), woven at its proper shape. `media/hsbs/BigBuckBunny.hsbs.jpg` is a frame to try; films are kept out of git (`media/**/*.mkv` and so on are ignored), so put your own beside it. A file given on the command line (`MoviePlayerFMX.exe ..\..\..\media\hsbs\BigBuckBunny.hsbs.jpg`) is opened at start.

- **Films** play with their **sound**, on Windows' default output device (WASAPI, shared mode, at the device's own rate and channels, 32-bit float; FFmpeg's swresample converts the film's sound, downmixing 5.1 to stereo where the device is stereo). **Space** pauses and resumes both. Three threads work ahead: a reader sorts the film's packets into a picture queue and a sound queue, so neither can starve the other; a picture decoder converts each picture to BGRA with the film's own colour matrix (BT.709 for HD, BT.601 for SD, as tagged or by size when untagged) and range into a queue of four; a sound decoder fills a one-second buffer, and the sound starts once a quarter of a second is ready. **The sound is the clock**: every the display frame weaves the newest picture due by the sound being heard, so a 24 fps film shows each picture for 2 or 3 refreshes at 60 Hz, and a picture whose time passes unseen is dropped and counted. Without a sound track or an output device the film plays silent on a wall clock, and the log says why; a wall clock also carries on if the pictures outlast the sound. The first picture shows at once. At the end the last picture stays. The log gives the film (codec, size, pixel format, frame rate, length), its sound and the device, both conversions, a progress line every 5 seconds (pictures shown, decoded, dropped late, sound shortfalls) and a summary at the end. A film advances only while glasses-free 3D runs; with it off, the 2D view shows the picture it had reached.
- **Layout** is *Auto* (the default), *Full side-by-side* or *Half side-by-side*. Auto reads the file name first (the words `hsbs`, `h-sbs`, `half-sbs` mean half; `fsbs`, `full-sbs` mean full). Without a tag, a **film** is taken as half side-by-side, since 3D films almost always are; its shape is not used, because a cinema-scope film cropped to 1920 x 804 is more than twice as wide as high. A **still** without a tag goes by its shape: at least twice as wide as high is full, anything narrower is half. The log says which it chose and why. A film takes a change from its next picture; a frame is loaded again.
- **How it is shown.** Each view keeps its stored width (960 pixels for a 1080p film) in a view of half the viewport's aspect, letterboxed or pillarboxed in black; the weaver's stretch to the viewport then gives it back its 16:9 shape. With the lens off the left view goes to both eyes. While the display is off the left view is shown in 2D, stretched to its proper width.
- The rest is as in LenticularDemoFMX: **Glasses-free 3D**, **Lens**, **Full screen** (F11, Esc), **Settings...** (the eye separation), the start-problem dialog, `MoviePlayerFMX.log` beside the exe, and the same settings file. It has no 3D scene: the viewport is black until something is opened. Open... starts in the folder last opened from, also after a restart (`playerFolder` in the settings file), else `media\hsbs`. It always starts in a window, so Open... is on screen: the settings file's `fullScreen` is LenticularDemoFMX's, and the player neither uses nor changes it.

**FFmpeg** is a 64-bit GPL shared build of FFmpeg 8.x, matching the headers in `ffmpeg-headers/` (8.1). Its DLLs go in `dll\ffmpeg\`, which git ignores, so each developer supplies their own copy; MoviePlayerFMX's post-build step copies them beside the exe (the demos do not get them). The player needs `avutil-60`, `swresample-6`, `avcodec-62`, `avformat-62` and `swscale-9`. It starts without them: the headers' imports are marked `delayed` (the only other change is `{$WARN SYMBOL_PLATFORM OFF}` at the end of `FFCompilerDefines.inc`, since Delphi warns at every `delayed` import), and the DLLs are loaded once, when the first film is opened, each checked and loaded by its full path, so a missing DLL, a 32-bit one or one from a different build is named in the log, and the player carries on with stills. The headers' `sws_getCoefficients` returns a pointer as an `Integer`, which loses its upper half on Win64, so it is not used; `Lenticular.VideoDecoder` keeps FFmpeg's colour tables itself.

The work is split so VCL can share it: `lib/Lenticular.StereoFrame.pas` does everything to frames with raw pixels and Windows Imaging Component, `lib/Lenticular.VideoDecoder.pas` decodes films with FFmpeg, and `lib/Lenticular.AudioOutput.pas` plays their sound and keeps the clock, none of them using FMX or VCL; their views go straight to `lnb_SubmitViews`. `lib/Lenticular.MovieRenderer.pas` is the FMX side, a `TLenticularStereoRenderer` subclass that moves the current picture from the decoder to the frame (swapping buffers, no copy) and supplies the views each frame through the `SupplyViews` hook. That hook supplies nothing in `TLenticularStereoRenderer` itself, so LenticularDemoFMX is unchanged.

## LenticularDemoVCL

VCL has no 3D, so LenticularDemoVCL's scene, the same as LenticularDemoFMX's (the 11 x 11 grid of spheres, the two columns of cubes and the back wall, in the same world units, so the same size on the display), is drawn by the bridge: `lnb_RenderScene` renders both eyes with Direct3D 11 straight into the view texture, with an off-axis projection per eye from the tracked eyes and the window's place on the display, and weaves it. Nothing is read back to the CPU in either demo (LenticularDemoFMX copies its eyes on the GPU), but the bridge draws the scene in C++ with one shared mesh per shape, while FMX prepares and draws each of its 130 or so objects separately for each eye, so the bridge has more to spare; both reach the display's 60 fps cap on the owner's machine (LenticularDemoFMX since it stopped drawing the scene a third time, see `SkipViewportPaint`). The shaders are compiled when the scene is first drawn (`d3dcompiler_47.dll`, part of Windows 10 and 11). LenticularDemoVCL needs a bridge built on 5 November 2026 at 08:40 or later (it has `lnb_SceneParamsSize`); with an older one it says the bridge must be rebuilt instead of drawing the old scene.

The toolbar has: Weave (start or stop the display), Show (the 3D scene, the test pattern or a side-by-side image from `media/`), Rotate, Look-around, Settings... (the eye separation), Views (the viewport's size or half of it) and Lens (off over the controls, always on or always off). F11 is full screen on the 3D display, Esc leaves it. The wheel, Page Up, Page Down, Home, a left-button drag and R work as in LenticularDemoFMX, and the frame rate is drawn on the glass at the top left as digits, so the two demos can be compared side by side. The choices are saved with LenticularDemoFMX's in `%APPDATA%\Peardox\LenticularDemos.json`; `LenticularDemoVCL.log` and the log panel record what happened, with a summary every 5 seconds.

New scenes for the VCL route are written in the bridge (or would be loaded from a model file there); LenticularDemoFMX remains the way to show scenes designed in FMX.

## Constraints of this version

- 2D controls must not overlap the viewport. The woven image is a native child window above the FMX surface. Mouse input passes through to FMX, but FMX controls drawn over that area are hidden.
- **FMX's own drawing left out (the default, `SkipViewportPaint = True`).** While frames are being drawn and the bridge's window covers the viewport, FMX's own paint of it (a third render of the scene, at every repaint an animation asks for) is never seen, so a `TLenticularViewport3D` (a `TViewport3D` with `SkipPaint`) leaves it out; it draws again as soon as the display stops or the viewport is hidden. A plain `TViewport3D` still works, drawing the scene a third time. With it LenticularDemoFMX went from 33 to 60 fps (Release, capped to the display's refresh) on the owner's machine.
- **Zero copy (the default, `ZeroCopy = True`).** The bridge shares FMX's Direct3D 11 device (`TCustomDX11Context.SharedDevice`). While FMX draws each eye, the renderer hands the bound render target to the bridge (`lnb_CopyEyeTexture`), which copies it on the GPU into its view texture (resolving it if multisampled); `lnb_PresentViews` then weaves it. Nothing goes through the CPU. The bridge keeps its own pipeline state in a D3D 11.1 state block, swapped in around each call, so FMX and the weaver never disturb each other's bindings. If FMX is not on DX11, the bridge is too old, or a copy fails, the renderer falls back by itself to reading each eye back with `CopyToBits` and uploading it, and the log says why. Stereo images from `media/` always take the upload path.
- **GPU check.** On laptops with an integrated GPU beside a discrete one, Windows starts programs on the integrated GPU unless told otherwise, and FMX cannot be told which to use. The bridge finds the GPU that drives the 3D display before it makes any device: its own device goes there, and FMX's device is shared only if it is on that GPU. After starting, the renderer logs which GPU FMX, the bridge and the 3D display are on (`lnb_GetGpuCheck`), and if FMX is on the wrong one, or drawing in software, reports it as a start problem (see "When the display cannot start, or would run badly"; `OnGpuWarning` is raised only if the display is kept running with the problem). `SetHighPerformanceGpu` (through `lib/Lenticular.GpuPreference.pas`) sets the program's Windows GPU preference, the same setting as Settings > System > Display > Graphics, from the next start; LenticularDemoFMX offers to do it. `LenticularDemoFMX /warp` makes FMX draw in software, to see the warning on any machine.
- **Start-up under the debugger.** Started from the IDE with the debugger (F9), LenticularDemoFMX took about 20 s to show its first frame on the RTX 5090; started without it, about 2 s. The debugger handles every DLL that loads, and the NVIDIA driver loads many when FMX makes its Direct3D device. Judge start-up times without the debugger (Run Without Debugging, or from Explorer).
- **Frame cap.** With vsync on, the bridge waits for the 3D display's vertical blank after each present (`IDXGIOutput::WaitForVBlank`; the compositor, `DwmFlush`, if the display's output is unknown), so no program draws more frames than the display shows (`lnb_SetFrameCap(0)` turns it off).
- One 3D viewport per process.
- The lens covers the whole panel and switches only as a whole. While it is on, everything outside the woven viewport (other windows, the desktop, the program's own 2D controls) is seen through it unwoven, and looks blurred. That's the hardware, not the program. `LensMode = lensOffOverControls` (the default) turns it off while the pointer is away from the viewport; a full-screen viewport avoids the question.
- Starting the display itself, once the background check has found it ready, takes about a quarter of a second on the main thread (the runtime context, the device and the weaver).
- After an runtime context loss (a service restart), the bridge shows the left view in 2D and retries every 3 seconds.
- Every bridge export masks floating-point exceptions while it runs and catches C++ exceptions, so neither reaches Delphi.
- In `lmIdle` mode, if other code replaces `Application.OnIdle` after the renderer starts and keeps chaining to it, don't free the renderer before that code unhooks. Otherwise use `lmTimer` or `lmManual`.

## Checks on the hardware

1. The status line shows **Weaving**, with eyes at roughly (+-32, 0, 500-700) mm that follow head movement.
2. **Depth:** the spheres on the right (negative Z) come out of the screen, and the back wall sits behind it. If depth is inverted everywhere, swap the two `RenderEye` destinations in `RenderFrame`.
3. **Parallax:** moving the head left makes near objects slide right against the back wall, as through a window. If an axis goes the wrong way, the log's `cal R U F` signs show what was measured.
4. Moving or resizing the window, or going full screen (F11), keeps the image locked to the viewport.
5. Unplugging the USB cable, or stopping the display service, shows events in the log and a 2D fallback, then recovery.
6. **How far out of the screen:** across the middle of LenticularDemoFMX's scene, between two columns of three spinning cubes (one going up, one going down; the outer ones come into view when the scene is tilted), is a grid of 11 x 11 spheres, the same gap across and in depth (3 world units, about 50 mm in a maximised window), centred on the green main sphere on the glass. One colour per depth: white on the glass, five rows behind it (blue, darker further away) and five in front of it towards you (yellow to red, red nearest). The depth gaps and the gaps across look the same, as the eye separation is used as it is (the demos no longer scale it); Settings... sets it (0 = as tracked). The mouse wheel moves the whole scene away (forwards) or towards you (backwards), Shift for quarter steps; Page Up and Page Down do the same. Dragging with the left mouse button over the viewport turns the scene about the green sphere: up and down tilts it about the horizontal axis (as standing up or sitting down would show it), left and right rolls it about the depth axis. Home puts it all back. R starts and stops the grid spinning about the vertical axis through the green sphere. P writes a snapshot to the log, one block between `=== SNAPSHOT ===` lines: the scene's move, tilt, roll and spin with the depth row in mm, the display, the viewport on it, the eyes, the settings, the reference camera, each eye's field of view, zoom, shear and corner check, the world-to-mm scale and the frame rate (`TLenticularStereoRenderer.LogSnapshot`), for comparing a view that looks right with another program's (StereoModel logs the same quantities). The frame rate is shown at the top left as flat text on the glass (depth 0, so it is equally sharp to both eyes), also in full screen. The status bar gives the depth row's distances from the glass in mm and yours from it, and each move is logged, so the point where a sphere stops fusing, doubles or strains the eyes can be read off and noted. The usual comfort guideline for glasses-free 3D is a pop-out of a fraction of the viewing distance; the grid is there to find this display's real limit.

## Notes for Claude

These are the working rules for this project, as in GDEM. Read this README, then `CLAUDE.md`.

### Delivering work

- Supply whole files, never patches or diffs, in a zip of only the files new or changed since the previous zip, with paths relative to the repository root. Say plainly when a delivery changes `bridge/`, which means the bridge must be rebuilt.
- Don't mention that changes are uncommitted or unpushed, or being unable to compile.
- The owner's working copy may be ahead of GitHub; build on the files most recently supplied.
- Update this README when features or requirements change.

### Code

- The rules differ by area; `CLAUDE.md` says which apply where. In short: the Spritely and Lenticular sets (the units in the packages) and StereoModel and ProjectionTest are cross-platform, documented with `//**` comments, and delivered with a package-rebuild line; the demos, their `lib/` units and the bridge follow the rules below.
- Delphi 13, FMX, Windows 64-bit. The owner normally wants cross-platform code, but the demos are Windows only: the display runtime is Windows only, apart from an Android version of the runtime, which there is no device to test on. `lib/` units still compile for Win32, so a design-time package loads in the IDE.
- Shared units go in `lib/`; a program's forms go in its own `ui/` folder; the bridge DLL goes in `dll/`.
- Document all Pascal in PasDoc format (`@abstract`, `@param`, `@returns`, `@link`), with private fields included. Before delivering, run `python3 tools/pasdoc_check.py` from the root; it should print `No problems found`.
- Source files are ASCII only. Keep the UTF-8 byte order mark on `.dproj` and `.groupproj` files.
- The bridge must build with MSVC x64. Every export masks floating-point exceptions (`LNB_ENTRY`) and catches C++ exceptions.
- Names (owner, 8 November 2026): our units, types and constants are `Lenticular...` (`Lenticular.StereoViewport`, `TLenticularStereoRenderer`, `LNB_...` in the bridge); the bridge is `LenticularBridge.dll` with `lnb_...` exports. They must not clash with the Lenticular package's (`Lenticular.Display`, `Lenticular.Display.Settings`, `Lenticular.Storage`, `Lenticular.Reg`, `TLenticularDisplay...`, `TLenticularStorage`), so one program can use both; `LenticularBridge.Api` is shared by both (it is in the package, and the demos compile it from source).
- No trademarks in names, UI, logs, comments or docs (owner, 8 November 2026): not the display maker's name, nor its runtime's product name or that name's two-letter abbreviation. Say "the display", "the display runtime", "the 3D display", "glasses-free 3D", "lenticular". The runtime's DLL names, SDK headers and C++ classes appear only inside the bridge's code, which needs them; never in its exported names, header names, log or error text. The only place a trademark is named is the Trademarks notice below. The repository's own name, SRDelphiFMX, stays until the owner renames it.
- Settings are read and written with the RTL's `System.JSON` (no Neon).

## Trademarks

These components are not affiliated with or endorsed by any display
manufacturer. Leia, Samsung and other names are trademarks of their
respective owners.

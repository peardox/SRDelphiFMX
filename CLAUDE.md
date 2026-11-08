# Lenticular (SRDelphiFMX): handover notes

This shows FMX `TViewport3D` scenes on an eye-tracked lenticular (glasses-free 3D) display from Delphi. Read `README.md` first, especially "Notes for Claude", then this file. The day-by-day history of how it got here (the full-screen fault hunt, the projection fixes, the zero-copy work) is in the git log up to commit `d42c73a`; this file keeps only what is true now.


## Rename for Lenticular (8 November 2026, zip LenticularRename1)

Asked by the owner (from the StereoModel session that split its components into Spritely and Lenticular): the display maker's trademark out of every place, the runtime's two-letter abbreviation no longer our name for anything, the bridge renamed to match what StereoModel now imports, the Delphi library and demos renamed, and Neon replaced by System.JSON. On branch `refactor` (main 2c4a2f1 plus the notes commit c9e8548); the notes folder `LenticularNotes1-NOT-FOR-ANY-REPO` from that session is deleted, and this section replaces it.

- **The bridge**: `bridge/SRBridge.cpp/.h` -> `bridge/LenticularBridge.cpp/.h`, CMake project and target `LenticularBridge` (so `LenticularBridge.dll`, `LENTICULARBRIDGE_EXPORTS`), the SDK path variable is now `LENTICULAR_SDKROOT`, `bridge/sr_stub` -> `bridge/sdk_stub`, child window class `LenticularBridgeChildWindow`. Every export `srb_` -> `lnb_`, public names `SRB_` -> `LNB_` (`LNB_API`, `LNB_ENTRY`, `LNB_E_RUNTIME_MISSING` for the old "DLL missing", `LNB_DisplayInfo` and the other records; `LNB_GpuCheck`'s fields `displayAdapter`, `programOnDisplayAdapter`, `bridgeOnDisplayAdapter`, `displayRefreshHz`). Layouts and values unchanged; `static_assert`s added for `LNB_Stats` (96) and `LNB_GpuCheck` (416). Internal helpers lost "SR" (`LoadRuntimeApi`, `CreateRuntimeContext`, `CreateRuntimeWeaver`, `StartRuntime`, `TearDownRuntime`, `RecoverRuntime`, `FindDisplayRect`, `g.runtimeContext`). NEW export `lnb_RuntimeInstalled` (the runtime's DLLs looked for as data, `LoadLibraryExW` with `LOAD_LIBRARY_AS_DATAFILE`, from the one list `kRuntimeDlls` the loader also uses). Every log and error text reworded: no maker, runtime or SDK names reach the Delphi side. The vendor's DLL names, SDK headers, C++ names and the mangled factory name stay in the bridge's code only.
- **`lib/LenticularBridge.Api.pas`** (was `SRBridge.Api.pas`): the same names as StereoModel's `Lenticular.Display.Api` (`LenticularBridgeDll`, `LenticularBridgeAvailable`, `LenticularBridgeHasExport`, `LenticularBridgeLastError`, `LenticularRuntimeInstalled` through `lnb_RuntimeInstalled`, `TLNB...` / `PLNB...`, `LNB_...`), plus `LenticularEventTypeName` (moved here). The unit that translated the vendor's C API into Pascal (named after the runtime) is DELETED: only its event-name function was used.
- **The library** (`lib/`): `FMX.SRStereoViewport` -> `Lenticular.StereoViewport` (+ `.Reg`, palette page **Lenticular**), `FMX.SRMovieRenderer` -> `Lenticular.MovieRenderer`, `SRStereoFrame`, `SRStereoImage`, `SRVideoDecoder`, `SRAudioOutput`, `SRSettings`, `SRSettingsDialog`, `SRStartProblem`, `SRGpuPreference`, `SRDiagLog` -> `Lenticular.<Name>`; every `TSR...` / `PSR...` -> `TLenticular...` / `PLenticular...`; `WM_SR_*` -> `WM_LENTICULAR_*`, `scContinueWithoutSR` -> `scContinueWithout3D`, `SRVideoRowAlign` / `SRVideoQueueSize` -> `LenticularVideo...`; fields and helpers lost "SR" (`FDisplayRect`, `FRuntimeInstalled`, `RuntimeInstalled`, `DisplayRect`, `MoveFormTo3DDisplay`, `GlassesFreeOnly`, ...). None clash with StereoModel's Lenticular package. `TLenticularStereoRenderer.Start` now checks the bridge before the runtime (the runtime check needs the bridge).
- **Settings**: `Lenticular.Settings` reads and writes with System.JSON and RTTI (public properties, camel-case members as before, read without regard to case). The file is `%APPDATA%\Peardox\LenticularDemos.json` (was `%APPDATA%\SRDelphiFMX\settings.json`; same members, not migrated: the owner renames the old file by hand to keep his). The `delphi-neon` submodule is removed and out of every search path.
- **Programs**: `SRDemoFMX` -> `LenticularDemoFMX`, `SRDemoVCL` -> `LenticularDemoVCL` (folders, `.dpr`, `.dproj`, `.res`), the group is `Lenticular.groupproj`; MoviePlayerFMX keeps its name. New exe names: Windows' per-exe GPU preference must be set again once; the crash-dump `.reg` files name `LenticularDemoFMX.exe`.
- **Text**: every comment, log line, UI string and doc reworded ("the display", "the display runtime", "the 3D display", "glasses-free 3D", "lenticular"); README has the Trademarks notice (the only place a mark is named) and the naming rules in "Notes for Claude"; CREDITS no longer names the maker. The repository's name, SRDelphiFMX, is kept until the owner renames it.
- THE BRIDGE MUST BE REBUILT (MSVC x64, `-DLENTICULAR_SDKROOT=...`), and the new `dll/LenticularBridge.dll` committed with `git add -f` (the old `dll/SRBridge.dll` is removed). Then StereoModel's `refactor` branch takes this commit as its submodule.

## Bridge device for StereoModel (7 November 2026, 21:00)

Asked by the owner from peardox/StereoModel: zero copy for Gorilla3D, which draws with OpenGL. New export `lnb_GetDevice` (`bridge/LenticularBridge.cpp`, `LenticularBridge.h`, `lib/LenticularBridge.Api.pas`): the bridge's `ID3D11Device` (`g.dev`), not AddRef'd, nil until initialised. StereoModel makes its two eye textures on it, registers them with OpenGL (WGL_NV_DX_interop2), blits Gorilla3D's framebuffer into them, then calls the existing `lnb_CopyEyeTexture` (which accepts any texture on `g.dev`) and `lnb_PresentViews`. Nothing else changed. THE BRIDGE MUST BE REBUILT. Not yet built.

## Snapshot for StereoModel (7 November 2026, 18:30)

Owner: LenticularDemoFMX's view is excellent; log its settings while it looks right, to compare with StereoModel's. `TLenticularStereoRenderer.LogSnapshot(Note)` (public, in `lib/Lenticular.StereoViewport.pas`) logs one SNAPSHOT block (display, viewport mm and px, eyes, settings, reference camera, scale and what it makes of the eyes' and glass's distances, each eye's zoom / field of view / shear / corner, fps since the last periodic line, bridge counters); LenticularDemoFMX's key P (`TfrmMain.Snapshot`, through its keyboard hook, no repeats) calls it with the scene's state and `DepthText`. Nothing else changed; no bridge change.

## Bridge change for StereoModel (7 November 2026, 17:00)

Asked by the owner from peardox/StereoModel (its Lenticular package uses this bridge). `bridge/LenticularBridge.cpp`: the context is made through `NewContext()`, which makes the runtime context with the lens preference `g.lensOn` when the runtime has that function (looked up, optional; else the plain context as before), for both `lnb_Initialize` and `lnb_Probe`, so the lens starts as last asked with `lnb_SetLens` (StereoModel asks for off: its panel was blurred through the whole start); and a new export `lnb_GetLensState` (the runtime's own lens state on the bridge's lens hint, optional: 1 on, 0 off, -1 not known). `bridge/LenticularBridge.h` and `lib/LenticularBridge.Api.pas` declare it. Nothing else changed; the demos ask for the lens on (`g.lensOn` defaults to true), so they behave as before. THE BRIDGE MUST BE REBUILT. Not yet built.

## Session handover (5 November 2026, 17:23)

**Where this session ended.** GitHub's head is `e6ca440` ("Working SBS player", 13:12). That push has the sound step, and the README describes film sound as working. The "Step 3, sound" note below still says it was not built or tested; the owner hasn't confirmed either way in this session, so ask before relying on it. This session worked from `e6ca440` and changed no Pascal, `.dproj` or `bridge/` file, so nothing needs rebuilding.

**What the session did** (17:01 to 17:23):
- `tools/pasdoc.bat` (new, ASCII, CRLF), adapted from TSteamAPI's. It writes the PasDoc reference as HTML to `docs\html\` and as HTML Help to `docs\chm\`, each with `api\` (every `lib` unit except `Lenticular.StereoViewport.Reg`) and one folder per program.
- Programs are found, not listed: any root folder holding `<folder>\<folder>.dpr`. Each program's sources are its `.dpr` plus the units its uses clause names `in '...'`: `ui\` forms and `..\lib` units, with FastMM5 left out. That way the `@link`s in the `.dpr` comments resolve.
- Win64 Release view only (`MSWINDOWS`, `WIN64`, `CPUX64`); no FPC runs, unlike TSteamAPI. `docs\html` and `docs\chm` are deleted whole before each run. The `.chm` names are `Lenticular.chm` and `<program>.chm`.
- Dark colours (17:11 to 17:14): `tools/pasdoc-dark.css` (HTML, inside `prefers-color-scheme: dark`, Bootstrap 5.3's own dark palette plus `--pasdoc-*`) and `tools/pasdoc-chm-dark.css` (always dark, plain colours with `!important`, as the HTML Help viewer is IE 7 mode: no `var()`, `:root` or `rgba()`). `pasdoc.bat`'s `:dark` appends one to each run's `pasdoc.css` (`PASDOC_DARK=0` skips it), so PasDoc's GPL `pasdoc.css` is never copied into this repository, which may go MIT. PasDoc 1.0.x pages are Bootstrap 5.3.8 with no `data-bs-theme`, hence no dark mode of their own. The HTML overlay was checked in headless Chrome on PasDoc's own test output (dark, light unchanged, narrow screen, notes and warnings); the `.chm` one was not, as there is no HTML Help viewer here.
- `README.md`: a layout row and "3. The reference (PasDoc, optional)" under Building. `.gitignore`: `docs/html/`, `docs/chm/`, `/pasdoc.log`.
- TSteamAPI (17:16 to 17:18, another repository): the same dark colours added to its `tools/pasdoc.bat` (all four runs) and `tools/pasdoc.sh` (`docs/html/fpc`), as zip Doc5 following its push `a0c0e2c`. Its README and `CLAUDE.md` record it ("Zip Doc5"), and its own checks reported 0 problems. `pasdoc.sh` was tested there with a stand-in pasdoc; its `.bat` and `.chm` look are untested, like this repository's.

**Waiting on the owner:**
- A first run of `tools\pasdoc.bat`. It was written without a Windows shell or pasdoc. The source lists it builds were checked by simulating its parsing (MoviePlayerFMX 14 files, LenticularDemoFMX 10, LenticularDemoVCL 8, all present). The first thing to watch is whether pasdoc parses the `.dpr` files cleanly, since TSteamAPI only ever gave it units. If it doesn't, drop the `.dpr` from `SRCS` in `:program`.
- How the `.chm` files look with `pasdoc-chm-dark.css`, here and in TSteamAPI.
- Whether the sound step (below) is verified, so this file can say so.

**Delivered:** the zip of `tools/pasdoc.bat`, `README.md` and `.gitignore` (17:06); then this file alone (17:08); then the dark colours with `tools/pasdoc.bat`, `tools/pasdoc-dark.css`, `tools/pasdoc-chm-dark.css`, `README.md` and this file (17:14); then this file alone (17:23). The next zip holds only files changed after this one.

## MoviePlayerFMX (5 November 2026, from 09:50)

The new direction: playing 3D films. The owner's rules for it: assume half side-by-side (HSBS), left eye on the left, for all video for now (swapping eyes and top-and-bottom later); a new project, MoviePlayerFMX, in the group; the new code is an extension, never a replacement; the base library must stay functionally intact, with both demos working as before; and the new library must use no framework, so FMX and VCL can both use it.

Verified on the owner's hardware (10:50): a single HSBS frame is woven correctly at its proper shape. The player starts in a window (the shared `fullScreen` setting is LenticularDemoFMX's: starting full screen hid Open... and showed only black), Ctrl+O opens in full screen, and a frame file on the command line opens at start. What was delivered:
- `lib/Lenticular.StereoFrame.pas` (no FMX or VCL): `TLenticularStereoFrame` holds one side-by-side frame as BGRA bytes, from a file (WIC) or memory (`SetFrame`, for a decoder); `TLenticularStereoLayout` (auto: name tag, then shape, less than 2:1 is half); `RenderViews` fits the views at the stored width in a view of viewport aspect / squeeze, cached; `LeftView` stretches an HSBS half 2x (linear) for 2D.
- `lib/Lenticular.MovieRenderer.pas`: `TLenticularMovieRenderer = class(TLenticularStereoRenderer)`, owns a `TLenticularStereoFrame` (`Frame`, `ShowFrameFile`, `ClearFrame`, `CopyFrameLeftView`), supplies the views through `SupplyViews`, logs each new fit once.
- The only base change, in `lib/Lenticular.StereoViewport.pas`: the protected virtual `SupplyViews` (supplies nothing by default; when a subclass supplies views, `RenderFrame` uploads them with `lnb_SubmitViews` in place of the scene or `ShowStereoImage`'s image, in its own variables so W and H are untouched otherwise), and `Log` moved from private to protected. Nothing else in the base, `bridge/` or the demos changed.
- `MoviePlayerFMX/`: `.dproj` derived from LenticularDemoFMX's (new GUID, same post-build steps), `.res` copied from LenticularDemoFMX's, `ui/PlayerForm.pas` (the demo's patterns: start-problem dialog, F11/Esc key hook, lens held off under dialogs, 2D left view while the display is off; no scene), in the group as the third project.
- `media/hsbs/BigBuckBunny.hsbs.jpg`: frame 6 s of the owner's sample, kept out of `media/` because LenticularDemoFMX lists `media/` and would refuse it. Big Buck Bunny is CC BY 3.0 (credit in CREDITS.md), not CC0 as first said.

The owner's sample (`.hsbs.hvec.mkv`, 6.7 s Big Buck Bunny): HEVC Main 1920 x 1080, 30 fps, no B-frames, limited range, untagged colour (BT.709), Vorbis 48 kHz stereo, no stereo metadata. Measured disparity confirms left-right order (near -1, far +17 half-width pixels, right minus left).

Step 2, film pictures (verified 11:14 on the owner's hardware with the full Big Buck Bunny HSBS film: FFmpeg 62.28 loaded with GPL v3, 16 decoding threads, BT.709 limited, fitted right windowed and full screen, no drops for 18 s then 16 dropped in 10 s of full screen, none after; lens off over the controls works as in the demos, and the owner is happy with it): the owner's choices were FFmpeg (their 64-bit GPL 8.x DLLs in `dll\ffmpeg\`, git-ignored, copied beside the exe by MoviePlayerFMX's post-build step only) loaded once, when the first film is opened; pictures first, sound next. The headers are in `ffmpeg-headers/` (DelphiFFmpeg.com, BSD-style licence, not CC0; "tested Win32 only"), changed only by adding `delayed` to all 913 imports and `{$WARN SYMBOL_PLATFORM OFF}` at the end of `FFCompilerDefines.inc` (W1002 at every import otherwise). First build (11:10) succeeded after one fix, `Ord(SWS_BILINEAR)` (the headers' swscale flags are an enum). `lib/Lenticular.VideoDecoder.pas` (no FMX or VCL): `LoadLibraries` checks and loads avutil, swresample, avcodec, avformat, swscale by full path and logs versions and licence; `TLenticularVideoDecoder` opens a film, decodes on a thread into a 4-slot BGRA queue (swscale with the film's matrix and range; the headers' `sws_getCoefficients` returns a pointer as Integer, broken on Win64, so the coefficient tables are kept in the unit), keeps the clock (starts at the first picture; pause), `TakeFrame` swaps buffers. `TLenticularStereoFrame.SwapFrame` takes pictures without copying. `TLenticularMovieRenderer`: `PlayFile`, `StopVideo`, `TogglePause`, `VideoLayout`; `SupplyViews` pulls the due picture each the display frame (so a film advances only while the display runs) and logs colour, errors, progress every 5 s and the end. The player opens films and frames (by extension), Space pauses, status shows the time. Films under `media/` are git-ignored (the owner put the full film at `media/hsbs/bbb.hsbs.hvec.mkv`). Untested risks: the headers on Win64, the WIC and FFmpeg declarations' exact parameter types.

Step 3, sound (delivered 12:40, not yet built or tested): `lib/Lenticular.AudioOutput.pas` (no FMX or VCL) declares the few WASAPI interfaces itself (IMMDeviceEnumerator, IMMDevice, IAudioClient, IAudioRenderClient; Delphi's RTL has none), opens the default output device in shared mode at its mix rate and channels as 32-bit float (EVENTCALLBACK, AUTOCONVERTPCM), all calls on its own MTA thread, fed from a 1 s ring buffer; its clock is the start time plus real frames handed over less the device's padding, smoothed by a stopwatch between reports and never past what was handed over. `TLenticularVideoDecoder` now runs three threads (reader into two packet queues, resting while both hold 60 packets or 64 MB; pictures; sound through swresample to the device format, starting the device once 0.25 s is buffered); times are film times from the format's `start_time`; the sound is the clock until drained, then a wall clock carries on; without sound (no track, no decoder, no device) a wall clock from the first picture, and the log says why. The first picture shows at once. The adapter logs the sound line, the conversion and sound shortfalls (underruns). Untested risks: the hand-written WASAPI interface declarations (method order), and the clock's behaviour on underruns.

## Earlier session handover (5 November 2026, 09:00)

**What the session did** (06:28 to 09:00; details in the git log):
- Tidy-up of the full-screen hunt's diagnostics; SRFullScreenTest removed.
- The demo scene for finding the depth limits (below), the same in both demos, with the same controls.
- Full screen hides the taskbar (topmost a second later; see below).
- The Depth slider replaced by a Settings... dialog for the eye separation; depth always 1.
- LenticularDemoVCL's compile fixes, and a bridge size check against an old LenticularBridge.dll.
- LenticularDemoFMX from 33 to 60 fps by skipping FMX's own, unseen paint of the viewport.

**Waiting on the owner:**
- Not yet confirmed: full screen and back with FMX's paint skipped (eye views should stay right), and that the delayed topmost step never raises `ECannotCreateSwapChain`.
- The question the scene was built for: which sphere (mm in front of the glass, from the status bar) is the last that fuses comfortably, windowed and full screen.
- Whether tilt and roll go the same way in LenticularDemoVCL as in LenticularDemoFMX (flip the sign in the bridge's `sceneM` if not).

**Next, if the owner wants more:** "Offered, not done" below, and for a release (owner, 09:02): `media\` goes beside the exes (found already); offered, not done: logs to `%LOCALAPPDATA%\Peardox\logs` when the exe's folder is not writable (Program Files), and a shared media location for an installer. The owner tests every delivery before the push, so keep deliveries small.

## The demo scene, speed and full screen

The scene (LenticularDemoFMX in FMX objects, LenticularDemoVCL drawn by the bridge's `lnb_RenderScene`, in the same world units):
- An 11 x 11 grid of spheres (r 0.7, 3 units apart in X and Z, Y = 0), one colour per depth (white on the glass, blue behind, yellow to red in front), the green main sphere at the origin; two columns of three cubes (3 units, Y = +-(4.5 + 4.5k)), turning a turn in 8 s; a back wall 60 x 40 at Z = 18. The viewport is 16.5685 units high on the glass (camera 20 back, 45 degrees).
- FMX: objects under `FSceneRoot` (wheel, tilt, roll), the grid under `FGridRoot` inside it (R spin, `FGridSpin`, 20 s a turn the other way to the cubes, paused at start). The FPS is a `TPlane` with a texture redrawn once a second (a `TText3D` came out garbled), at depth 0 top left, half see-through.
- Bridge: `LNB_SceneParams` is 64 bytes (`fps`, `sceneZ`, `tiltDeg`, `rollDeg`, `gridSpinDeg`); world to mm `Scaling(U, -U, -U) * Translation(cx, cy, 0)`; the FPS as seven-segment digits. `lnb_SceneParamsSize` lets LenticularDemoVCL refuse an older bridge (which draws the old scene).
- Controls in both: wheel or Page Up / Page Down move the scene in depth (+-20), left-drag tilts (X, +-85) and rolls (Z, +-180), Home resets, R toggles the grid spin. The status bar gives the depth row's mm from the glass. Tilt and roll directions might differ between the two (not reported).
- Settings...: `lib/Lenticular.SettingsDialog.pas`, a Windows dialog built in memory for the eye separation (0..90 mm, 0 = tracked), lens off while it is open. The Depth slider is gone; `EyeSeparationScale` is always 1 (LenticularDemoFMX puts back a saved other value and logs it).

Speed: `TLenticularViewport3D` (in `Lenticular.StereoViewport`) skips FMX's own, unseen paint of the viewport while frames run and the bridge's window shows (`SkipViewportPaint`, default True); that took LenticularDemoFMX from 33 to 60 fps in Release (33 was frames just over one refresh, halved by the vertical-blank cap). Risk not yet seen: a resize while skipping (full screen) if `TViewport3D` set up its context only in `Paint`.

Full screen hides the taskbar: the window is made topmost by `ApplyTopmost` from the frame loop 1 s after full screen came on (topmost at the moment of the resize raised `ECannotCreateSwapChain` for `TCanvasD2D`). `FullScreenTopmost` (default True) turns it off. Not yet confirmed that the delayed version never raises it.

LenticularDemoFMX's only test switch left is `/warp` (FMX in software, to see the GPU-problem path); `FullScreenTopmost` and `SkipViewportPaint` stay as properties.

## State (verified on the owner's hardware)

- **3D in a window and full screen** works: correct off-axis projection (`corner` (1, 1)), look-around, no drift; full screen (F11 / Esc) no longer breaks (the fault went away once the bridge's device was on the GPU driving the 3D display).
- **Zero copy**: the bridge shares FMX's DX11 device; eyes copied on the GPU (MSAA resolved). 210-250 fps uncapped; the **frame cap** on the display output's vertical blank gives 60 fps.
- **GPU check**: the 3D display's GPU is found before any device is made; FMX on the wrong GPU or in software is detected (`/warp` tested).
- **Start-problem policy**: no display runtime is silent (controls hidden); with the runtime, `useGlassesFree3D` in the settings decides; on a problem the program carries on without glasses-free 3D and the task dialog offers continue without / try again / anyway (GPU problems only) / exit. The wording is "glasses-free 3D", never plain "3D".
- **Asynchronous start** (06:24 log): background check 64 ms, `lnb_Initialize` 225 ms, first woven frame 2.2 s after the program started (run without the debugger).
- Lens off over the controls, wait for the eyes before 3D, off-display detection, 3D display placement on multi-monitor desktops, stereo images from `media/` (left view in 2D while the display is off).
- LenticularDemoVCL: the bridge draws LenticularDemoFMX's scene itself (`lnb_RenderScene`), 60 fps capped (the old, smaller scene ran at 440 fps uncapped full screen); same settings, controls, start-problem dialog (no "anyway" choice) and background check, start-problem and background-check answers posted to a hidden window.
- LenticularDemoFMX: 60 fps capped in Release with the demo scene (about 130 objects) since `SkipViewportPaint`.
- The frame watchdog (posts a frame when OnIdle has been starved for 25 ms) kept frames going on a power-limited GPU.

## Offered, not done

- A "frames too slow" warning (e.g. a laptop in low-power mode ran 31-58 fps even on the right GPU).
- An FMX `Multisample` setting (FMX renders 4x MSAA; at 4K per eye that costs a lot).
- Creating the runtime context on the background check's thread and keeping it, to save the ~200 ms left on the main thread (unknown whether the display minds the thread change).
- Moving the GPU eye copy (`CopyEyeOnGpu`) into its own `lib/` unit.
- Offsetting the grid's depth column slightly, if spheres hide each other seen straight on.
- Known: in `lmIdle` mode under WARP, frames are starved (OnIdle comes only when the queue is empty); moot now that software rendering stops the display by default.

## How the owner works

The same as GDEM: Delphi 13 FMX on Windows.

The stop hook's "commit and push" prompt: do not answer it with an explanation; the owner knows changes are left for them to apply and push. Say nothing more than "Noted." if a reply is needed.

The compiled bridge is committed in `dll/LenticularBridge.dll`. Building the bridge with CMake overwrites that file (a post-build step in `bridge/CMakeLists.txt`), and every project's post-build step copies it next to the exe. Whenever a delivery changes anything in `bridge/`, say plainly that the bridge must be rebuilt. Supply whole files in a zip of changed files only, with paths from the repository root: only the files changed since the previous zip delivered (owner, 06:22, 5 November 2026), never a cumulative set since some earlier version, and never a bridge file unless that delivery changed the bridge. Logs are the main evidence, so make log lines say exactly what happened.

Start-up times are judged without the debugger: under F9 the NVIDIA driver's DLL loads made LenticularDemoFMX take ~20 s to its first frame (it looked like an FMX problem; it was not).

## Design notes

- The weaver is C++ only (a factory function and a weaver interface with virtual inheritance; their names are in the bridge's code), hence `bridge/`, an MSVC DLL with a flat C API. The runtime's DLLs are loaded at run time. The factory is found by its decorated name, or by scanning the exports.
- The C API's context handle is passed to the weaver factory as the C++ context pointer. This isn't documented, but it matches how the C API wraps every other object.
- The bridge owns a child window over the viewport (`WM_NCHITTEST` returns `HTTRANSPARENT`, so the mouse reaches FMX) and a bitblt-model swap chain on it (DISCARD, one sRGB buffer, as the vendor's samples). Views are uploaded through typeless textures with sRGB views, and the back buffer's render target view is sRGB too, so the weaver does no sRGB conversion in its shader.
- Start order in `lnb_Initialize`: runtime context, display, events, lens hint, display rectangle and the GPU driving it (`CreateRuntimeContext`); then the device (FMX's if it is on that GPU, else the bridge's own there); then the weaver (`CreateRuntimeWeaver`). `lnb_Probe` does the context and display part alone, on a background thread, before it.
- On FMX's shared device the bridge keeps its own pipeline state in an `ID3DDeviceContextState`, swapped in by `CtxGuard` around every export that touches the context.
- `TLenticularStereoRenderer` renders the viewport's 3D children into the viewport's own `TContext3D` (`RenderInternal`), once per eye, setting the lights itself from `IViewport3D.Lights`. With zero copy it hands the bound render target (`OMGetRenderTargets` between BeginScene and EndScene; `ResourceToTexture` is private) to `lnb_CopyEyeTexture`; otherwise it reads each eye back with `CopyToBits`.
- The off-axis projection is built into the view matrix passed to `SetCameraMatrix`: `RefView * Translation(-eye) * OffAxis` (a shear plus a zoom). FMX's projection is left as it is. The axis signs are measured in view space every frame, and the viewport corner is checked against NDC (1, 1) with the shaders' own formula.
- The eye frame is millimetres from the display centre, x right, y up, z towards the viewer. The window rectangle in mm comes from the child window's screen rectangle, the 3D display's desktop rectangle (`FindDisplayRect`; the window's monitor only if that is unknown), and the 3D display's physical size.
- Full screen is the renderer's own (Raymond Chen's method on the existing window, held at the 3D display's rectangle by a `WM_WINDOWPOSCHANGING` subclass), never FMX's `FullScreen`, which re-creates the window.
- Anything that must run soon from the frame loop or a start (the start-problem event, the background check's answer) is posted to the renderer's hidden window (`AllocateHWnd`): posted messages come ahead of paints and timers, while `TThread.ForceQueue` and OnIdle wait until FMX is idle.

## Lessons learned

- A film's shape cannot tell its layout: scope films cropped to 1920 x 800-808 are about 2.4:1, which the stills' 2:1 rule took for full side-by-side (Alita showed at half width). For films, Auto is the name's tag, else half side-by-side (`TLenticularMovieRenderer.DecideVideoLayout`); stills keep the shape rule. The owner's 40 films: all 8-bit yuv420p, mostly H.264 at 23.976 fps, widths 1888 to 3840; Titanic.3D.1997.H-OU is top-and-bottom (not yet supported).

- swscale writes rows with SIMD and runs past the end of a row whose length in bytes is not a multiple of 64: a 1916-wide film (Avatar, 7664 bytes a row) overwrote FastMM's footer after each picture, while 1920 (7680 bytes) was fine. Converted rows are padded to `LenticularVideoRowAlign` (64) with 64 spare bytes after the last, and the pitch is carried through `TLenticularVideoDecoder.TakeFrame` and `TLenticularStereoFrame.SwapFrame`; never assume `Width * 4` for a decoded picture.

- `MonitorFromWindow`, `GetMonitorInfo`, `TMonitorInfo` and `MONITOR_DEFAULTTONEAREST` are in `Winapi.MultiMon`, not `Winapi.Windows` (GDEM's `GDEMFetch/ui/GDEMDisplays.pas`, cut down from Sprite3D's `DisplayData`, uses them the same way).
- The IDE rewrites a multi-line post-build event into one line joined with `&&`. An `if exist ... (...) else (...)` followed by `&&` makes the next command part of the `else` branch. Write each step as a parenthesised `(command || echo warning)` instead.
- FMX 3D (`FMX.Types3D`): `SetCameraMatrix` takes the **view** matrix (world to view; `TCamera.CameraMatrix` is a `CreateLookAtDirRH` one). The shaders get `Model * CurrentCameraMatrix * Projection`, and `CurrentCameraInvMatrix` is only used for picking. The projection is cached and rebuilt only on context create or resize, so `SetCameraAngleOfView` and `SetRenderToMatrix` do nothing mid-frame. Put any field of view or off-axis change into the view matrix.
- A self-check built on the same wrong assumption as the code proves nothing. Check against the formula the GPU uses, or against the picture: the owner's OBS recording found what the log could not.
- The weaver reports both eyes at one point (0, 100, 600) before the tracker locks on.
- The SDK's C++ display class's base has no virtual functions, so its vtable can be mirrored (`DisplayMirror` in the bridge) to call `getLocation` without including the SDK's display header, which includes OpenCV.
- The SDK's context header includes OpenCV through the network headers. Don't include it in the bridge; the stub in `bridge/sdk_stub` stands in.
- In Delphi 13, `TContext3D.Width` and `Height` are `Single`.
- `dcc32` in the build output means a 32-bit build, which can't load the 64-bit bridge. `LenticularBridgeLastError` says so.
- Delphi 11 and earlier leave floating-point exceptions unmasked; driver and the display code expect them masked, so every bridge export masks them (`LNB_ENTRY`).
- `DwmFlush` paces to the compositor, which follows the fastest monitor (the laptop panel, 240 Hz); pace on the 3D display's own output (`WaitForVBlank`).
- WM_PAINT and WM_TIMER come only when nothing else is waiting, and OnIdle only when the queue is empty; a constantly repainting FMX (WARP above all) starves all three. Use a posted message.
- FMX's `TDialogService` dialog came up behind the window and with the lens on (unreadable): use a Windows dialog owned by the form, with the lens off.
- Windows' per-exe GPU preference is keyed by the full exe path, so Debug and Release builds have separate settings.
- `HWND_TOPMOST` in the same `SetWindowPos` as the full-screen resize made FMX's D2D canvas fail (`ECannotCreateSwapChain`); apply it later, z-order only.
- `TText3D` with a changing string rendered as streaks; text on a `TPlane` texture works.
- A `TViewport3D` keeps painting itself (a whole render of the scene per repaint) under the bridge's window; skipping that paint doubled LenticularDemoFMX's frame rate.
- `GetDlgItemInt`'s third parameter is a `var BOOL` in Winapi.Windows; a module-level `var` must come before the code that uses it; when an anonymous method passed to `TThread.Queue`/`ForceQueue` fails to compile, the error is "no overloaded version", not the real one.
- An old bridge DLL reads only the part of a grown record it knows and carries on: add an export that reports the size, and check it.

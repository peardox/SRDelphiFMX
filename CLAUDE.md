# SimulatedReality: handover notes

This shows FMX `TViewport3D` scenes on a LeiaSR eye-tracked lenticular display from Delphi. Read `README.md` first, especially "Notes for Claude", then this file.

## Where to pick up (29 October 2026, 22:00)

**SRDemo now crashes very quickly** (the owner's report after pushing the
repository with the compiled bridge in `dll/` and FastMM5 as a submodule). The
cause isn't known. Delivered to find it:

- FastMM5 full debug mode in Debug builds, with its event log in
  `SRDemo_FastMM.log`.
- `lib/SRDiagLog.pas`: `SRDemo.log`, plus first-chance and unhandled native
  exception logging, with the module and offset.
- Bridge logging (`srb_SetLogCallback`), with FATAL handlers for abort,
  terminate, pure virtual calls and invalid parameters.
- Stage tracing of the first 5 frames.
- Skip switches for tracking, rendering and weaving.
- `tools/enable_crashdumps.reg`.

See "Finding crashes" in the README. Next step: the owner rebuilds the bridge
and SRDemo (Debug), runs it until it crashes, and sends `SRDemo.log`,
`SRDemo_FastMM.log` if it exists, and the Event Viewer entry if the log just
stops.

The drift problem below is still open; it may share a cause with the crash.

## Earlier: the drift (29 October 2026, 21:30)

**First run on the hardware.** SRDemo ran and *almost* worked: the weave looked right. But after about one full turn of the cube (the spin lasts 8 s), the image "splits into two and each part drifts off to a new location". The window was small, so the owner wasn't sure.

The cause isn't known yet. Ideas, none confirmed:

- **Eye prediction running away.** The weaver's `getPredictedEyePositions` extrapolates; if tracking stalls or the user is lost, predicted eyes could drift. That would move both the rendered views and the weave phase. The log now shows the eyes each second, `NOMINAL` when they are invalid, and `UserLost`/`UserFound` events.
- **A stale projection matrix.** If FMX recalculates `CurrentProjectionMatrix` only lazily, the calibration in `RenderEye` (`TanRef`, the bisection in `SetVerticalTanHalf`) could read an old matrix and feed back. The log's `focal` ratio should stay at 1.0000, and `tanRef`/`scale` should stay constant.
- **SR context loss and re-creation.** Look for `reinit n/m` and `exceptions` in the bridge line, and `ContextInvalid` events.
- **Something tied to the animation.** The demo now has **Pause rotation**: does the drift still happen with the cube stopped?
- **Frame pacing or latency** (the readback stalls the pipeline). The log shows fps, the worst frame, and the weaver's latency.

Next step: the owner runs SRDemo maximised or full screen (F11), reproduces the problem, then uses **Copy log** and pastes it.

## State

- Delivered on 29 October 2026:
  - the layout (group project at the root, `SRDemo/` with `ui/`, shared `lib/`, `dll/`, `bridge/`, `tools/`);
  - PasDoc on every unit;
  - `OnLog` diagnostics in the renderer;
  - `srb_GetStats` in the bridge;
  - in SRDemo, the log panel, Pause rotation and Full screen.
- The bridge builds with MSVC (owner, 29 October). The first build failed to link with `cv::String::deallocate`: `srcontext.h` pulls in OpenCV. `bridge/sr_stub/sr/management/srcontext.h` replaces it with a forward declaration of `SR::SRContext`.
- Delphi compile fixes so far: `TContext3D.Width` and `Height` are `Single` in Delphi 13, so they are rounded. The first runs were a Win32 build (`dcc32`), which can't load the 64-bit bridge, so the project now targets Win64 only.

## How the owner works

The same as GDEM: Delphi 13 FMX on Windows.

The compiled bridge is committed in `dll/SRFmxBridge.dll`. Building the bridge
with CMake overwrites that file (a post-build step in `bridge/CMakeLists.txt`),
and SRDemo's post-build step copies it next to the exe. Whenever a delivery
changes anything in `bridge/`, say plainly that the bridge must be rebuilt. Supply whole files in a zip of changed files only, with paths from the repository root. Logs are the main evidence, so make log lines say exactly what happened.

## Design notes

- The weaver is C++ only (`SR::CreateDX11Weaver`, `SR::IDX11Weaver1`, with virtual inheritance), hence `bridge/`, an MSVC DLL with a flat C API. The SR DLLs are loaded at run time. `CreateDX11Weaver` is found by its decorated name, or by scanning the exports.
- The C context handle (`newSRContext`) is passed to `CreateDX11Weaver` as `SR::SRContext*`. This isn't documented, but it matches how the C API wraps every other object.
- The bridge owns a child window over the viewport (`WM_NCHITTEST` returns `HTTRANSPARENT`, so the mouse reaches FMX), plus its own D3D11 device and flip-model swap chain. Views are uploaded through typeless textures with sRGB views, and the render target view on the back buffer is sRGB too, so the weaver does no sRGB conversion in its shader.
- `TSRStereoRenderer` renders the viewport's 3D children into the viewport's own `TContext3D` (`RenderInternal`), once per eye. It sets the lights itself from `IViewport3D.Lights`, and reads each eye back with `CopyToBits` into one side-by-side buffer.
- The off-axis projection is a view-space shear passed through `SetCameraMatrix` (FMX uses the inverse as the view). The angle of view is found by measuring `CurrentProjectionMatrix.m22`, so FMX's angle convention doesn't matter. The axis signs are measured against the reference camera every frame.
- The eye frame is millimetres from the display centre, x right, y up, z towards the viewer. The window rectangle in mm comes from the child window's screen rectangle, the monitor it is on, and the SR display's physical size.

## Lessons learned

- The SDK's `sr/management/srcontext.h` includes OpenCV through the network headers. Don't include it in the bridge; the stub in `bridge/sr_stub` stands in.
- In Delphi 13, `TContext3D.Width` and `Height` are `Single`.
- `dcc32` in the build output means a 32-bit build, which can't load the 64-bit bridge. `SRBridgeLastError` now says so.
- Delphi 11 and earlier leave floating-point exceptions unmasked; driver and SR code expect them masked, so every bridge export masks them (`SRB_ENTRY`).

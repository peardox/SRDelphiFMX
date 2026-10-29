# SimulatedReality: handover notes

This shows FMX `TViewport3D` scenes on a LeiaSR eye-tracked lenticular display from Delphi. Read `README.md` first, especially "Notes for Claude", then this file.

## Where to pick up (29 October 2026, 22:15)

**First full log from the hardware (21:51), Debug build, maximised on a
3840 x 2160, 596.7 x 335.7 mm panel; SR platform 1.36.4.35453.**

- **No crash:** the earlier crash did not happen again. The run ended
  normally after 23 s at 60 fps, with a 3840 x 1700 view per eye, a 52 MB
  side-by-side buffer, worst frame 27-40 ms, no re-creations and no
  exceptions.
- **The drift's cause:** `SetCameraAngleOfView` does not change
  `CurrentProjectionMatrix`. The bisection in the old `SetVerticalTanHalf` ran
  down to its 0.1 degree limit, and the measured focal ratio stayed at
  0.40-0.53. That is exactly 2.414 (cot 22.5, FMX's 45-degree default) divided
  by the wanted focal length: the matrix never moved off 45 degrees. So each
  eye was drawn with a field of view about 2.5 times too wide for the real
  geometry, while the shear assumed the real one. The two views did not match
  what the lens shows each eye, so they split and slid as the head moved.
- **Fix, delivered:** FMX's projection stays at the reference camera's. The
  eye's field of view comes from a zoom built into the view matrix together
  with the shear (`Zoom = TanRef / TanEye`). Each frame checks that the
  viewport's top-right corner lands at NDC (1, 1); the log shows it as
  `corner`.
- **Bad eye pairs at start-up:** the first frames had L = R = (0, 100, 600),
  before tracking locked on, and one second showed an eye separation of
  16 mm. Separations outside 45-85 mm are now rebuilt around their midpoint
  with 63 mm, logged as `IPD-REBUILT`.
- **FastMM5's debug mode was off** in that run. The dpr now logs which
  condition was missing: the define not compiled in (do a Build, not a
  Compile, after options change), or the DLL not beside the exe.
- **Measured conventions:** `cal R+ U+ F-`, so the FMX camera looks down its
  local -Z axis; `tanRef 0.4142`; scale 0.0627 world units per mm at
  FocusDistance 20.

Next: the owner runs the new build, checks the `corner` values and whether the
image now holds together, and reports the smaller issues they have noticed.

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

The stop hook's "commit and push" prompt: do not answer it with an
explanation; the owner knows changes are left for them to apply and push. Say
nothing more than "Noted." if a reply is needed.

The compiled bridge is committed in `dll/SRFmxBridge.dll`. Building the bridge
with CMake overwrites that file (a post-build step in `bridge/CMakeLists.txt`),
and SRDemo's post-build step copies it next to the exe. Whenever a delivery
changes anything in `bridge/`, say plainly that the bridge must be rebuilt. Supply whole files in a zip of changed files only, with paths from the repository root. Logs are the main evidence, so make log lines say exactly what happened.

## Design notes

- The weaver is C++ only (`SR::CreateDX11Weaver`, `SR::IDX11Weaver1`, with virtual inheritance), hence `bridge/`, an MSVC DLL with a flat C API. The SR DLLs are loaded at run time. `CreateDX11Weaver` is found by its decorated name, or by scanning the exports.
- The C context handle (`newSRContext`) is passed to `CreateDX11Weaver` as `SR::SRContext*`. This isn't documented, but it matches how the C API wraps every other object.
- The bridge owns a child window over the viewport (`WM_NCHITTEST` returns `HTTRANSPARENT`, so the mouse reaches FMX), plus its own D3D11 device and flip-model swap chain. Views are uploaded through typeless textures with sRGB views, and the render target view on the back buffer is sRGB too, so the weaver does no sRGB conversion in its shader.
- `TSRStereoRenderer` renders the viewport's 3D children into the viewport's own `TContext3D` (`RenderInternal`), once per eye. It sets the lights itself from `IViewport3D.Lights`, and reads each eye back with `CopyToBits` into one side-by-side buffer.
- The off-axis projection is a view-space shear and zoom passed through `SetCameraMatrix` (FMX uses the inverse as the view). FMX's projection is left at the reference camera's angle: `SetCameraAngleOfView` does not change `CurrentProjectionMatrix`. The axis signs are measured against the reference camera every frame, and the viewport corner is checked against NDC (1, 1).
- The eye frame is millimetres from the display centre, x right, y up, z towards the viewer. The window rectangle in mm comes from the child window's screen rectangle, the monitor it is on, and the SR display's physical size.

## Lessons learned

- `TContext3D.SetCameraAngleOfView` does not change `CurrentProjectionMatrix`, so a field of view cannot be set through it. Build the field of view into the camera matrix instead (a zoom in view space).
- The SR weaver reports both eyes at one point (0, 100, 600) before the tracker locks on.

- The SDK's `sr/management/srcontext.h` includes OpenCV through the network headers. Don't include it in the bridge; the stub in `bridge/sr_stub` stands in.
- In Delphi 13, `TContext3D.Width` and `Height` are `Single`.
- `dcc32` in the build output means a 32-bit build, which can't load the 64-bit bridge. `SRBridgeLastError` now says so.
- Delphi 11 and earlier leave floating-point exceptions unmasked; driver and SR code expect them masked, so every bridge export masks them (`SRB_ENTRY`).

# StereoModel: handover notes for Claude

`README.md` describes the program; this file is for Claude: how the owner
works, the rules for the code, and where the work has got to. Read both.
Keep this file up to date when the rules or the state of the work change.

## Merged into SRDelphiFMX (8 November 2026)

This file came from peardox/StereoModel, which stays where it is but is no
longer worked on. The repository's root `CLAUDE.md` ("Areas and rules")
says which rules apply where and takes precedence; the rules below are
those of the Spritely and Lenticular sets and of StereoModel and
ProjectionTest. Paths in the history below are StereoModel's; here they
are:

| In StereoModel | Here |
|---|---|
| `src/StereoModel.*`, `src/ui/StereoModelMain.*`, `src/common/StereoModel*`, `src/common/FmxLinuxMenu.pas` | `StereoModel/`, `StereoModel/ui/`, `StereoModel/common/` |
| `src/ProjectionTest.*`, `src/ui/ProjectionTestMain.*`, `src/common/ProjectionTest*` | `ProjectionTest/`, `ProjectionTest/ui/`, `ProjectionTest/common/` |
| `lib/Lenticular.Display.Api.pas` | gone: `lib/LenticularBridge.Api.pas`, the unit the demos use, made cross-platform |
| the `SRDelphiFMX` submodule, its `dll\LenticularBridge.dll` | this repository: `bridge/`, `dll/LenticularBridge.dll` |
| SRDemoFMX, SRDelphiFMX's stereo renderer | `LenticularDemoFMX/`, `lib/Lenticular.StereoViewport.pas` |
| `StereoGroup.groupproj`, `tools/pasdoc.bat` | `Lenticular.groupproj`, the root's `tools/pasdoc.bat` |
| `lib/`, `packages/`, `models/`, `tools/gen_*.py` | the same, at this repository's root |

The bridge is no longer a submodule: a change the work here needs goes
into `bridge/` directly (saying THE BRIDGE MUST BE REBUILT), instead of
notes for another session. The pasdoc checker is this repository's
`tools/pasdoc_check.py`, which knows both comment styles.

## How the owner works

- Delphi 13, FireMonkey, Gorilla3D. Develops on Windows (the 32-bit IDE),
  also builds for macOS, Linux 64-bit, Android and iOS.
- Tests promptly and pastes back logs; make log and status lines say
  exactly what happened.
- **Package rebuilds** (as in TSteamAPI): whenever a delivery changes
  anything a package compiles (`lib/`, `packages/`), say so IN CAPITALS on
  a line of its own, naming the packages and platforms, e.g.
  `====> REBUILD RUNTIME PACKAGE SPRITELY (WIN32 AND WIN64) AND REINSTALL
  DCLSPRITELY <====`, and `====> NO PACKAGE REBUILD <====` when nothing
  needs it.
- **Deliver whole files, never patches**, in a zip of only the new and
  changed files with paths from the repository root; name them, and say
  which earlier zip it replaces or follows. Do not commit or push. Files
  to delete or rename are listed for the owner (with the git commands).
- Do not mention being unable to compile.
- When a hook asks to commit and push, answer "Noted." and do nothing.
- Never change a submodule from here (FastMM5). The bridge is part of
  this repository now (see the top of this file).
- No paths, user names, machine names or credentials in tracked files.

## Rules (owner, 7 and 8 November 2026)

- **Peardox is the owner, not a product.** The components are two
  products, each its own set (owner, 8 November 2026):
  - **Spritely**: the Gorilla3D camera components. Types `TSpritely...`
    (`TSpritelyOrbitalCamera`, `TSpritelyProjection`, ...), units
    `lib/Spritely.<Name>.pas`, constants `SPRITELY_...`, packages
    `Spritely` / `dclSpritely`, palette page **Spritely**, icon tiles green.
  - **Lenticular**: the glasses-free 3D (lenticular display) components.
    Types `TLenticular...` (`TLenticularDisplay`, ...), units
    `lib/Lenticular.<Name>.pas`, constants `LENTICULAR_...`, packages
    `Lenticular` / `dclLenticular`, palette page **Lenticular**, icon
    tiles blue. Its runtime package needs only rtl and fmx.
  - **The two sets never need each other**: no Spritely unit uses a
    Lenticular one or the reverse, and neither package requires the other,
    so either may be installed alone. Something that needs both (such as
    TPeardoxGorillaEyes, if it becomes a component) goes in the program or
    in a third package that requires both. `tools/gen_packages.py` stops if
    a unit is in the other set's package or a package requires the other
    set's.
  - The programs' own types keep the owner's prefix, `TPeardox...`
    (`TPeardoxGorillaEyes`, `TPeardoxProjectionTestForm`, ...); the
    settings folder is still `Peardox` in the user's application data.
- **No trademarks in names, UI, logs, comments or README** (owner, 8
  November 2026; extends the 15:10 rule on game names): not the display
  maker's name, nor its runtime's product name or that name's two-letter
  abbreviation: say "the display", "the display runtime",
  "the 3D display", "glasses-free 3D", "lenticular"). Vendor DLL and SDK
  names stay inside the bridge (SRDelphiFMX), never here. The only place a
  trademark is named is the README's Trademarks notice. The repository's
  name, SRDelphiFMX, stays until the owner renames it; its demo is now
  LenticularDemoFMX.
- **Reusable components go in `lib/` at the repository root**, not under
  `src/`; other projects use them. They must not know about this program.
- **Components are registered on their set's palette page**, with a
  palette icon (`lib/icons`, packaged by `tools/gen_icon_res.py` into
  `lib/Spritely.Reg.dcr` or `lib/Lenticular.Reg.dcr`, linked by
  `lib/Spritely.Reg.pas` or `lib/Lenticular.Reg.pas`).
- **Cross-platform**: Windows, macOS, Linux 64-bit, Android and iOS. No
  platform-specific unit or call without `{$IF}` alternatives, as in
  Sprite3D.
- **Settings are kept in the OS's per-user location** (AppData on Windows,
  Application Support on macOS, `$XDG_CONFIG_HOME` / `~/.config` on Linux,
  the documents folder on mobile), never beside the executable, read and
  written with the RTL's `System.JSON` (no Neon, owner, 8 November 2026),
  as `TLenticularStorage` in `lib/Lenticular.Storage.pas` does. If
  Spritely ever needs settings it gets its own `Spritely.Storage` (the
  sets share no unit).
- A new component is first made in code to test it; once it works it is
  put on the form in the `.fmx`.
- PasDoc on everything (`//**` comments, private members too), ASCII-only
  sources, two-space indent, as in Sprite3D. Check with this repository's
  checker, `python3 tools/pasdoc_check.py` from the root (lib and every
  program folder; it accepts the `//**` style).
- A new unit goes in both the `.dpr` and the `.dproj` (UTF-8 with BOM).
  A new component unit also goes in its set's list in
  `tools/gen_packages.py` (the demos' library units are its `SOURCE_ONLY`).

## Handover (8 November 2026, Rename1)

### This session: Peardox split into Spritely and Lenticular (Rename1)

Asked by the owner (8 November 2026, 17:25 - 17:41): the components
renamed into two independent products, the display maker's trademark
removed everywhere, JSON settings without Neon. On branch `refactor`;
zip Rename1 follows ProjHandover1 (the branch at cc39655).

- Spritely: `Peardox.OrbitalCamera` -> `Spritely.OrbitalCamera`,
  `Peardox.Projection` -> `Spritely.Projection`, `Peardox.Reg` ->
  `Spritely.Reg` (+ `.dcr`); every `TPeardox...` there -> `TSpritely...`
  (`TPeardoxProjection` -> `TSpritelyProjection`, not "...Camera": it
  rewrites a camera's projection, it is not one), `IPeardoxProjectionFocus`
  -> `ISpritelyProjectionFocus`, `PEARDOX_ORBITAL_/PROJECTION_/MATRIX_/
  COMPONENT_PLATFORMS` -> `SPRITELY_...`. Packages `Peardox` /
  `dclPeardox` -> `Spritely` / `dclSpritely` (the IDE's .dproj copies
  edited, GUIDs kept).
- Lenticular: the old glasses-free 3D units and `Peardox.Storage` -> `Lenticular.Display`,
  `Lenticular.Display.Settings`, `LenticularBridge.Api`,
  `Lenticular.Storage`; the component is `TLenticularDisplay` (its enums
  `ldp*` problems, `lds*` states, `ldl*` lens), settings
  `TLenticularDisplaySettings`, `TLenticularStorage`, constants
  `LENTICULAR_...`. NEW: `Lenticular.Reg` (palette page Lenticular, icon:
  a screen under lens ridges, blue tile), package `dclLenticular`; the
  component is safe to drop on a form (its constructor already skipped the
  settings file, the timer and the window at design time). Package
  the old glasses-free 3D package -> `Lenticular`, requiring rtl and fmx only (dbrtl was
  Neon's).
- JSON settings: `Lenticular.Storage` rewritten on System.JSON and
  System.TypInfo (published integer, Int64, float, Boolean, enum by name,
  string; camel-case member names as Neon wrote; read case-blind, unknown
  or unsuitable members ignored). The settings file is now
  `Lenticular.json` (same folder, same members): the owner renames the old
  file by hand to keep his settings. The `delphi-neon` submodule is
  removed (`git rm delphi-neon`).
- The bridge (renamed in SRDelphiFMX by its own session, from the notes
  delivered with Rename1 - assumed done): `LenticularBridge.dll`
  (`dll\LenticularBridge.dll` in the submodule; StereoModel's post-build
  copies it), exports `lnb_...`, records `TLNB...`, constants `LNB_...`
  (`LNB_E_RUNTIME_MISSING` for the old "DLL missing"), Pascal helpers
  `LenticularBridgeAvailable`, `LenticularBridgeHasExport`,
  `LenticularBridgeLastError`, `LenticularRuntimeInstalled`,
  `LenticularEventTypeName`. NEW export `lnb_RuntimeInstalled` (the bridge
  looks for the runtime's DLLs as data): their names no longer appear
  here. So `Installed` now also needs the bridge beside the executable,
  and `Start` reports a missing bridge before a missing runtime.
- Demos: `PeardoxOrbitalCamera1` -> `SpritelyOrbitalCamera1` in both
  forms; the form's display field is `FDisplay`, its handlers `Display...`,
  and `TPeardoxGorillaEyes.Display`; the demo scene models are
  `DemoScene*.glb` and `tools/gen_srdemo_scene.py` ->
  `gen_demo_scene.py` (made again). The orphan
  `src/common/ProjectionTestAccess.pas` deleted.
- Tools: `gen_packages.py` (four packages, the two sets checked apart),
  `gen_icons.py` / `gen_icon_res.py` (two .dcr), `pasdoc.bat` (a reference
  per set), `StereoGroup.groupproj`.
- PACKAGE REBUILD: all four, all platforms used; uninstall dclPeardox and
  install dclSpritely and dclLenticular; delete the old Peardox,
  glasses-free 3D and dclPeardox .bpl and .dcp (and their DCUs in the Dcp
  folders) so no program picks up the old units.
- Names in the history below are the present ones (rewritten in Rename1);
  zip names are as they were.

## Handover (8 November 2026, 15:54)

Read this section first; "Where the work is" below is the full history,
for when a detail is needed.

### This session (8 November 2026, 12:30 - 15:54): projection access SOLVED

The long-standing "Gorilla3D takes no projection of ours" problem is
solved, generally, as a component: **TSpritelyProjection**
(lib/Spritely.Projection.pas, Spritely package, palette icon a cavalier cube
behind a camera). It finds FMX's private TContext3D.FProjectionMatrix by
VALUE in the drawing context (never a hard-coded offset) from an empty
3D object first in the viewport (TSpritelyRenderHook, called inside each
frame), and writes its own projection there every frame, made from FMX's
own (so resizes and lens changes are followed); FMX's goes back when
nothing is changed or Active is False. What it draws:

- Perspective with any lens (FieldOfView; 0 = the camera's own) and the
  DOLLY ZOOM (Dolly: the Focus camera moves so the target plane keeps
  its size).
- Lens SHIFT and RISE (ShiftX / ShiftY, NDC) - the pan / rise asked for
  since StereoCam10.
- Parallel views at the target plane: pjOrthographic; obliques
  pjCavalier, pjCabinet, pjMilitary, pjPlanOblique, pjOblique (free angle
  / scale); and orthographic camera presets pjTrueIsometric (45 /
  35.264), pjDimetric (2:1, 45 / 30), pjTrimetric (35 / 45).
  CameraPreset (default on) turns the Focus camera to a kind's angles
  (PresetAngles, through ISpritelyProjectionFocus.ProjectionViewAngles).
- ManageCulling: Gorilla3D's FrustumCulling off while changed (it culls
  by its own camera).
- TSpritelyOrbitalCamera.Projection links the two: the camera is the
  projection's Focus (target distance, dolly, presets), and its fits
  (FitToBounds / FitToBoundsMax / ProjectToView) follow the projection
  actually drawn (shift, lens and parallel views; checked in Python).
- RULE (owner, 15:10): no game or trademark names in identifiers, UI or
  README.
- Facts learned (ProjTest1-5 logs): the projection is cached in the
  context and a written one stays until FMX remakes it; SetCameraMatrix
  with a shear also works but only inside the frame; SetRenderToMatrix
  does nothing; NDC y is up; FMX's perspective is D3D-style, depth 0..1;
  MAKESCREENSHOT IS ONE FRAME LATE (it shows the RenderManual before the
  last) - probably the cause of StereoCam58a's sign puzzle in
  StereoModelEyes' screenshot fallback.
- ProjectionTest (src/ProjectionTest.dpr) is now the component's test
  bed: model box (incl. models/DollyHallway.glb, tools/
  gen_dolly_hallway.py, near end open), Fit / Front, Shift / Rise /
  Centre / Active / Free Movement (camera may enter the model), Kind /
  Angle / Depth / Lens / Dolly; the measuring test only on Run test
  (AUTO_TEST = False). Owner (15:34-15:54): all working.

Zips of this session, in order (each follows the one before): ProjTest1,
2, 3, 4, 5, ProjComp1, 2, 3, 3b, 4, 5, 6, ProjHandover1 (this file). The
owner deletes src/common/ProjectionTestAccess.pas (moved into lib in
ProjComp1). PACKAGE REBUILD for ProjComp1 and ProjComp2 (Spritely, all
platforms; reinstall dclSpritely) - done by the owner.

Open: (1) a Windows chime on ProjectionTest's exit, no dialog, cause
unknown (asked for the IDE Event Log / Windows Event Viewer); an AV on
exit with TPopupBox (ProjComp3) went with TComboBox + explicit teardown
in FormClose. (2) "Depth 0" in the Front view taken as the target on the
model's centre - not confirmed. (3) SetTargetDepth changes a parallel
view's size (its size is the target plane's) - by design, not yet
discussed. (4) The wheel scales Distance, so it never passes the target
(Free Movement only lifts the keep-out); a fly / move-forward control
would need asking for.

### State

- GitHub `main` holds everything up to StereoCam58a (merge d84819d; the
  `stereo` branch is gone). The owner's copy is ahead: StereoCam59 to 62,
  delivered as zips, tested and working (owner, 23:17: "that's good now"),
  then StereoCam63 (8 November: the FBX leak fix, `LoadModel` and this
  file; owner, 12:22: "The fix works"). StereoCam63 was built on GitHub
  `main` at df67bde. Ask whether they have been pushed before building on
  GitHub.
- **FBX leak: fixed** (StereoCam63). `LoadModel` makes the model itself
  (`TGorillaModel.Create(GorillaViewport1)`) and loads with the instance
  method `LoadFromFile`, as Sprite3D does; never go back to the class
  function `TGorillaModel.LoadNewModelFromFile`, which leaks the FBX
  loader's parse tree (Gorilla3D 1.5.3). See Lessons learned.
- Submodule SRDelphiFMX at 2c4a2f1 (`lnb_GetDevice`, `lnb_SetFrameCap`,
  `lnb_CopyEyeTexture` / `lnb_PresentViews`). Never change it from here.
- StereoCam60 changed the Lenticular package (settings + `Flat`); the
  owner must have rebuilt it.

### How glasses-free 3D works now

- **Two windows.** The launcher (main form, lens off) and the 3D window
  (`FOutput`, borderless, full screen on the 3D display, named from its
  EDID). Stereo button / Esc. On the 3D display the launcher hides; on
  another monitor it stays, with a cover (`FStereoCover`) over the view
  that takes drags and the wheel. The viewport moves to the hidden
  `FRenderForm` while the launcher is in sight (Gorilla3D otherwise
  flashes in the launcher). The display starts on the hidden 3D window at program
  start; Stereo is enabled once it has.
- **Mouse.** The bridge's child window covers the 3D window;
  `DisplayStarted` subclasses it (`PassMouseThrough`, WM_NCHITTEST ->
  HTTRANSPARENT) so drags reach `FOutputHost`. The pointer is hidden over
  the 3D display while Stereo is on (`HideCursor`, `FCursorTimer`,
  `ShowCursor`).
- **Per-eye off-axis view** (`TPeardoxGorillaEyes`,
  src/common/StereoModelEyes.pas), SRDemoFMX's geometry done Gorilla3D's
  way. Per frame: `ViewScale` reads the orbit camera's projection through
  `ProjectToView` (FProjX / FProjY = 1 / tan of the half-angles) and sets
  the scale, units per mm, so the view's height on the display is what the
  field of view takes in at the MODEL's depth (`ModelDepth`: the camera's
  Subject's box centre along the line of sight). `EyeView` puts each eye's
  camera at the tracked eye (dx, -dy, -dz) * scale in the roll pivot's
  frame (X right, Y down, Z forward; the glass through the orbit centre at
  Z = 0), looking straight ahead, and projects the glass's corners to get
  `TPeardoxEyeView.Part` - the fractions of the picture the glass covers
  from that eye. The picture is rendered `RenderScale` (default 2) times
  the woven view's size; the part is cut out and scaled to the view
  (1920 x 1080) in the copy. Gorilla3D takes no projection or view matrix
  of ours (as far as tried - see Pan / rise), which is why the cut is in
  the copy and not in the camera.
- **Zero copy** (src/common/StereoModelGLInterop.pas,
  `TPeardoxGLInterop`): two B8G8R8A8 textures on the bridge's D3D11
  device, registered with OpenGL (WGL_NV_DX_interop2). After each eye's
  RenderManual, `CopyEye` binds FMX's multisampled RGBA8 framebuffer
  (`FindPicture`, by name), resolves it, and blits the part (GL_LINEAR,
  rows turned over, black outside) into the eye texture;
  `TLenticularDisplay.SubmitEyeTextures` weaves them. Every GL error is taken
  (`TakeErrors`) - FMX's next BeginScene fails on any pending one.
  Screenshots + a CPU copy (`CopyPart`) are the automatic fallback.
- **Speed** (owner's RTX 5090 laptop, demo scene): per-eye view at
  render scale 2: 46-48 fps (render 16 ms for both eyes, copy 0.5, submit
  0.2); per-eye view off or render scale 1: about 100 fps.
- **Right drag** = `SetTargetDepth`: the camera stays, the target (the
  glass) slides along the line of sight. The scale stays (it is set at
  the model's depth), so in the display the glass and the viewer move together and
  the model comes out of the screen or goes in without sliding. The 2D
  picture does not change. The wheel moves the camera (and so the scale).

### Settings and keys

All in Lenticular.json (`TLenticularDisplaySettings`, lib, shared by Spritely
programs), all saved when changed by key:

| Key | Setting | Meaning |
|---|---|---|
| L | LatencyFrames | weaver's eye prediction, 0 (the runtime's) .. 4 |
| [ ] | EyeSeparationMM | -/+ 5 mm (0 = as tracked) |
| C | FrameCap | bridge waits for vblank after each frame (off) |
| V | PerEyeView | off = full speed: eyes at the model's distance in the real eyes' directions, the whole picture woven, render scale 1 |
| , . | RenderScale | -/+ 0.25, 1 .. 2 (2) |
| M | HideCursor | pointer hidden over the 3D display (on) |
| W | Weave | off = flat: one view from the eyes' midpoint for both, lens off (`TLenticularDisplay.Flat`), for screen recordings |

Also P (snapshot block to the log), Home (view back), Esc (Stereo off).
Removed in StereoCam59: S T X R Z F (swap, toe-in, shift sign,
RenderManual, zero copy, row flip) and the old shift method.

### Next, in order

1. **TPeardoxGorillaEyes as a component** in lib (the owner will do this
   in its own session). It uses Spritely (orbit camera), Lenticular and
   Gorilla3D, so it needs a third package that requires both (never
   Lenticular requiring Spritely or the reverse: the sets stay apart, owner,
   8 November 2026); its name and prefix to ask; StereoModelGLInterop goes with it (Windows-only
   parts already under {$IFDEF MSWINDOWS}). Design package and palette
   icon as the others; first made in code, then on the form.
2. **TSpritelyProjection into use** (the component works - see "This
   session" above): first on ProjectionTest's form in the .fmx (it is
   still made in code, as the rule asks for a new component); then in
   StereoModel - shift / rise in the 2D view (control: ask - Shift+drag,
   middle drag or keys); then the PER-EYE VIEW'S OFF-AXIS CUT IN THE
   PROJECTION: each eye drawn with its own asymmetric frustum (shift +
   lens per eye, as SRDemoFMX's zoom and shear), so render scale 1, no
   overscan and no cut in the copy - sharper and ~2x faster than the 2x
   render. TPeardoxGorillaEyes must then use ProjectToView / ViewShape
   (which already follow) and write the projection per eye inside each
   eye's RenderManual. Settle the screenshot fallback's one-frame lag
   there too. "Pan / rise: where it stands" below is now history: route
   5 (writing FMX's private projection) is what worked.
3. Later: LensMode (lens off over the controls); two 3D displays (ask
   which); the old screenshot-route sign puzzle (StereoCam58a) only if it
   shows again.

### Pan / rise: where it stands

**What is meant.** A view camera's movements: SHIFT (sideways; the owner
says "pan") and RISE / FALL move the picture across the lens while the
camera stands still and looks the same way. Perspective is unchanged;
only the framing moves - e.g. a tall model's top brought into frame
without tilting, so verticals stay parallel. Not to be confused with
pan / tilt in the film sense (the camera TURNS: perspective changes,
verticals converge) or truck / pedestal (the camera MOVES: parallax
changes). Mathematically a shift is an asymmetric (off-axis) frustum:
the projection's window slides by (sx, sy) in normalised device units,
which is what `x_ndc += sx * w` does after the projection, or a shear
`x' = x - (sx / SX) z` in view space before it.

**What has been tried (StereoCam10-17), and why it failed:**
- Truck / pedestal (StereoCam10): moves the camera, so the view changes;
  not a shift. `TSpritelyOrbitalGorillaCamera.ShiftView` (lib) still does
  this, for sub-pixel nudges only.
- A lens shift in the PROJECTION (StereoCam13): overriding
  GetProjectionMatrix drew nothing different - Gorilla3D 1.5.3's context
  builds its projection itself from GetProjectionSettings, a record of
  Kind, OrthoHeight and OrthoWidth only. Changing the field of view while
  running is not drawn as expected either (dolly zoom, StereoCam15-17:
  plain zooming, then with ProjectionChanged a slow zoom).
- Moving the viewport control (StereoCam14): rejected by the owner ("it
  just moves the VP").
- Rendering larger and cropping, for the 2D view: rejected by the owner
  then (before zero copy existed).

**Not yet tried, most promising first:**
1. **Shear in the VIEW matrix, as SRDemoFMX does.** SRDemoFMX
   (SRDelphiFMX lib/FMX.SRStereoViewport.pas, `the stereo renderer's RenderEye`,
   around line 2694) gets its whole off-axis projection into FMX by
   multiplying the VIEW matrix: `OffAxis.m31 := -Zoom * ShearX`,
   `m32 := -Zoom * ShearY` (and m11 = m22 = Zoom), then
   `Ctx.SetCameraMatrix(EyeView * OffAxis)` - because FMX also ignores a
   changed projection between frames. Only the projection override was
   ever tried with Gorilla3D, never the view matrix. FIRST EXPERIMENT:
   find what view matrix Gorilla3D draws with (TCamera.CameraMatrix /
   GetCameraMatrix - is it virtual? - or something in TGorillaCamera /
   TGorillaViewport's render that calls Context.SetCameraMatrix) and try
   a shear there with a fixed test value. Check the lighting (Gorilla3D's
   deferred renderer may rebuild normals or positions from the view
   matrix; a shear may upset them) and the G-buffer passes (the HDR target
   FBO 3 etc. may use their own camera matrices).
   If it works, it is worth far more than pan / rise: the per-eye view
   could put its cut and zoom in the matrix too (no 2x overscan: render
   scale 1, sharp, ~100 fps), and the dolly zoom (Maybe later) becomes
   possible.
2. **In the 3D view only: an offset on the glass, nearly free.** The
   per-eye view already renders larger and cuts the glass's part out.
   A true shift / rise is the glass's rectangle moved in its own plane
   while the eyes stay where they are: in `EyeView`, add the offset
   (Sx, Sy, scene units = fraction * glass size * scale) to both corners
   before projecting (`-HalfW + Sx - E.X` and so on). It is exact for
   both eyes, so the depth is untouched. Limit: the part must stay inside
   the rendered picture, or that edge comes out black (CopyEye clears it):
   the slack each way is about (1 - part size) / 2 - about 0.26 of the
   picture at 85 cm with render scale 2 (the part was ~0.48 high), none
   at all with PerEyeView off (the part is the whole picture). More
   needs a wider field of view or a bigger render. NOTE: this alone
   gives the 3D view a shift the 2D window does not show; the owner
   should say whether that is acceptable.
3. **The 2D window by render and copy**: draw the 2D view off screen
   (as the eyes are) and blit the shifted part to the window - costs a
   render target, an overscan and a copy every frame, and was rejected
   for 2D before. Ask first.
4. **Gorilla3D's author**: an OffsetX / OffsetY in
   TGorillaProjectionSettings (added in ToMatrix as Offset times the w
   column to the x and y columns), or a way for a camera to supply its
   own projection. Already on the list of questions for him (with the
   field-of-view questions, and the LoadNewModelFromFile FBX leak as a
   bug report, not a question: worked round in StereoCam63); the owner
   relays.
5. **RTTI writes** to FMX's / Gorilla3D's private projection fields
   (the owner, 17:37: "some of the FMX3D fields for the projection matrix
   are strictly private", the source is there): fragile, and which field
   Gorilla3D draws with is not known. Last resort.

**Whatever route is taken, these must follow the offset:**
`TSpritelyOrbitalGorillaCamera.ProjectToView` and the fits
(FitToBounds / FitCorners / FitOnAxis, which assume a centred frustum),
`TPeardoxGorillaEyes.EyeView` (so the display and 2D agree), and the owner's
choice of control (no mouse button is free: left orbits, right moves the
depth, the wheel zooms - ask: Shift+drag, middle drag, or keys).

**First question for the owner** at the start of that session: shift /
rise in the 2D window, in the display, or both - it decides between route 2
(an hour) and route 1 (an experiment first).

### ProjectionTest (ProjTest1, 8 November 2026)

**Why.** Gorilla3D's author (owner, 8 November): the projection problem is
FMX's - TViewport3D does not expose the matrix; Gorilla3D draws with what
FMX gives it. The owner: the FMX source is in Delphi's source, so the
matrix can be reached, and a general solution has many uses (pan / rise,
the per-eye off-axis view without overscan, dolly zoom, ...). Asked for a
new test project in the main group to see if and how.

**Files** (zip ProjTest1, follows StereoCam63; program only, NO PACKAGE
REBUILD - it uses the installed Spritely package for the orbit camera):
src/ProjectionTest.dpr / .dproj / .res (the .res a copy of StereoModel's;
the .dproj made from StereoModel's without the LenticularBridge post-build and the
Deployment block, which the IDE makes again), src/ui/ProjectionTestMain
(.pas / .fmx, TPeardoxProjectionTestForm), src/common/ProjectionTestAccess,
ProjectionTestMeasure, ProjectionTestRunner; StereoGroup.groupproj lists
it (depends on Spritely) and builds it last. Its log is ProjectionTest.log
(own writer in the form; StereoModelLog's name is fixed).

**Method.** Nothing is assumed about FMX's or Gorilla3D's private fields
(StereoCam47's probe found no field RTTI in TGorillaViewport, so RTTI may
be off there):
- TSpritelyRenderHook: an empty TControl3D, inserted at index 0 of the
  viewport, overrides Render -> OnRenderBegin(Self, Context): inside the
  frame, after the viewport has set camera and projection, before the
  models. Gorilla3D culls by bounds, so the form gives it the model's box
  and the test turns FrustumCulling off. UNKNOWN until the first log:
  whether Gorilla3D calls Render on a plain TControl3D at all (the log
  says how many times the hook was drawn per RenderManual and per
  MakeScreenshot).
- TSpritelyProjectionAccess.Survey: one RenderManual; in the hook it reads
  CurrentProjectionMatrix / CurrentCameraMatrix / CurrentCameraInvMatrix
  and scans the raw memory (InstanceSize, 4-byte steps) of the render
  context, the viewport's context if different, the viewport, the cameras
  and, one level down, the non-FMX objects the contexts and viewport hold
  (where RTTI lists them) for 16 Singles equal to one of them, or shaped
  like a perspective (either layout). RTTI only names a find
  (Class.Field, +n inside a record). Each find is a TSpritelyMatrixSlot
  (holder, offset, kind) that can Apply a value and Restore FMX's
  (TSpritelyCleanTracker notices FMX making it again).
- Ways tried, each written once / before each frame / inside the frame:
  the PUBLIC TContext3D.SetRenderToMatrix (found in the docwiki: "the
  matrix used for the rendering of the objects"; if FMX applies it after
  the projection it is a public post-projection matrix: shift = identity
  with m41 = sx, m42 = sy; the transpose is tried too), the PUBLIC
  SetCameraMatrix with SRDemoFMX's shear (View * S, S.m31 = sx m34 / m11,
  S.m32 = sy m34 / m22), each projection slot (ShiftProjection: x column
  += sx * w column), each camera slot (sheared; its inverse slot too).
- Measured (ProjectionTestMeasure): MakeScreenshot -> greys; edge-strength
  profiles down the columns and along the rows; the best 1-D move of each
  (cost over both whole lengths, nought beyond the ends, so empty
  background cannot win; parabola for the fraction); then the picture
  moved back must match (residual <= 40% of the change) or it is "not a
  plain shift". Expected: 0.1 NDC = 0.05 of the width (96 px of 1920)
  right; rise 0.1 up = - 0.05 of the height in pixels. Checked in Python
  on synthetic pictures: shift 24 px -> 24.0, rise -13.5 -> -13.6, a 15%
  zoom -> residual 125%. Shift is tried first; rise only if it moved.
- The log ends "=== RESULT ===" with every WORKS line and "So:" lines.
- Live: MethodBox + Shift / Rise sliders (-0.5..0.5 NDC) apply one way
  continuously (in the frame, or between frames by a 5 ms timer for the
  projection slot); FrustumCulling off while a way in the frame is on.

**What the first log should settle:** (1) is the hook drawn; (2) does the
context's CurrentProjectionMatrix live in a field (an exact find) - a
cache - or is it made on every call (no exact find); (3) does a written
projection survive to the next frame (once) or is it made again each frame
(only in the frame works); (4) does SetRenderToMatrix work - then no
private access is needed at all; (5) does the shear work (and the
lighting); (6) the Y sign (rise WRONG WAY = FMX's NDC y is down there).
Known weak points (review, ProjTest1): SetRenderToMatrix is set from the
identity and put back to the identity, as its value cannot be read - if
FMX keeps its own there (a Y flip for render to texture) the test drops
it, the picture flips and is logged as "not a plain shift", and RestoreAll
would leave it so; the Survey reads the matrices at the hook's FIRST call
of the frame, and logs the projection at every later call (a shadow pass
would show as DIFFERENT). After a resize the live ways drop the slots
(Forget) rather than write into objects that may have been made again.
Then the general part (TSpritelyProjectionAccess) goes to lib with the way
that works, and StereoModel's per-eye view can put its cut in the
projection (render scale 1, no overscan).

**Owner's first log (ProjTest1, 13:44, 760 x 568 view, 1140 x 852
picture): IT WORKS.**
- The hook IS drawn: once per RenderManual, never by MakeScreenshot.
  Context TContextOpenGLWindows (Gorilla3D's TGorillaContext under it);
  the same context draws the frame; projection the same inside and after.
- The projection is CACHED in a field: TContext3D.FProjectionMatrix at
  +$60 of the context (FOV 45: m22 2.41421; near 0.1), RTTI there. Written
  ONCE it stays (the slot was still ours after the frames) and the
  public CurrentProjectionMatrix returns it; shift 57.0 px and rise
  -42.6 px exactly as expected, residual 0-4%. Also works before each
  frame and in the frame.
- Also works: SetCameraMatrix with the shear, in the frame only (the
  viewport sets the camera at the start of each frame), and
  FCurrentCameraMatrix (+$194, with FCurrentCameraInvMatrix +$1D4) in
  the frame only. The shear's residual equals the projection's, so the
  lighting did not visibly change in this test scene.
- Does NOT work: SetRenderToMatrix (any timing, either layout - no
  change at all), TGorillaContext.FOriginalCameraMatrix (+$3A0).
- Y: + rise moved the picture up: NDC y is up, as expected.
- MAKESCREENSHOT IS ONE FRAME LATE: in every working case the first
  look showed no change, the second the shift, and "put back" looked
  like the shift again - each screenshot showed the RenderManual before
  the last. ProjTest2 takes each look after two renders and checks the
  lag on its own (CheckScreenshotLag). THIS PROBABLY EXPLAINS
  StereoCam58a's puzzle: the screenshot route renders an eye then
  screenshots it, so each eye got the OTHER eye's picture (left / right
  swapped), hence the opposite shift sign to zero copy, which blits the
  framebuffer right after RenderManual. Check the screenshot fallback in
  StereoModelEyes before trusting it.
- False finds in ProjTest1, both harmless (put back, no effect):
  TGorillaViewport.FShadowStrength (+$880, settings that looked like a
  projection) and a window context's FCurrentCameraInvMatrix+20 (straddling
  two matrices). ProjTest2: a row-layout projection must also have m13 =
  m23 = 0 (column: m31 = m32 = 0), and a find that starts inside a
  TMatrix3D field (RTTI) is skipped.
- So the way: find FProjectionMatrix by value (Survey; never hard-code
  +$60, it moves with FMX's version), write a shifted / off-axis
  projection into it, and write it again whenever FMX makes it anew (a
  resize, a field-of-view change: TSpritelyCleanTracker sees that).
  ProjTest2 (follows ProjTest1): runner and access only, as above.
- ProjTest2's log (owner, 13:50): screenshot lag CONFIRMED by its own
  check ("after 1 render: NO CHANGE, after 2: SHIFTS"); every case now
  "put back"; the false finds gone; results as ProjTest1. Owner: "The
  Shift and Rise sliders have no effect". The log shows why for the ways
  tried: a resize made a new Survey, which frees the slots, and the live
  camera way then took the tester's BestCamera - a dangling pointer whose
  address a new slot (FOriginalCameraMatrix, which does nothing) had
  taken; the other two tried were "between frames" (unknown whether FMX
  remakes the projection in a normal paint) and SetRenderToMatrix (no
  effect in the test). Projection or shear IN THE FRAME were not tried.
  ProjTest3: the live ways take FirstSlot (never the tester's pointers),
  the box names the field, SetRenderToMatrix is marked "no effect in the
  test", and every 2 s while live the log says how often the hook was
  drawn and whether the slot holds ours or FMX's; the memo is 640 wide
  and goes back to the start of the last line after each add.
- Owner (14:00): "Bear in mind that this is a general solution we're
  looking for" - and oblique projections: cavalier, cabinet, military
  ("only orthographic and perspective are offered by the standard
  methods"). ProjTest4 (follows ProjTest3): TSpritelyProjectionAccess
  gains AdjustProjection (the general entry: any function from FMX's
  projection to the one drawn, written into the projection slot in the
  frame or by ApplyNow), DepthRange (FMX's perspective is D3D-style,
  right-handed, depth 0..1: m33 = f / (n - f), m43 = n f / (n - f); the
  log's -1.00001 / -0.1 give near 0.1, far ~10000), Orthographic (the
  perspective's view at a distance: m11 / D, m22 / D, linear depth
  1 / (n - f), n / (n - f), w = 1) and Oblique (a view-space shear about
  the target plane, d = -(z + D): x + k cos(a) d, y + k sin(a) d, then
  Orthographic; checked in Python - the target plane is unchanged and a
  point 10 deeper moves exactly k * 10 at angle a). RowLayout now tells
  an orthographic (w = 1) projection's layout right (it used m43, which
  an orthographic projection has as a depth term). Form: KindBox
  (perspective, orthographic, cavalier 1 / 45, cabinet 0.5 / 63.43,
  military 1 / 270 with the camera at azimuth 45, inclination 90, custom
  oblique), Angle (0..360) and Depth (0..1) sliders; cavalier / cabinet
  put the camera level (azimuth 0, inclination 0); a kind turns on
  "projection in the frame" if the live way cannot draw it; the shift and
  rise apply on top; distance = the orbit camera's Distance each frame, so
  the wheel zooms the parallel views too. Culling off while live.
  UNKNOWN: whether Gorilla3D's lighting or anything else in it assumes a
  perspective (e.g. rebuilds positions from depth) - watch the shading in
  the parallel views.
- Owner (14:15, ProjTest4): "Everything appears to be working well" -
  orthographic, cavalier, cabinet, military, free oblique, shift and rise
  all live at 60 fps, the projection holding ours throughout. "Another
  issue this probably solves is Dolly Zoom" - yes. One fault in that log:
  a resize while military was on made a new Survey whose frame did not
  draw the hook (read outside), and Forget had dropped the slots WITHOUT
  putting FMX's projection back, so the Survey took our oblique matrix for
  FMX's ("projection inside the frame [0.02309 ... | -0.5 2.58614 ...]");
  the oblique was then made from that and the shift added twice. ProjTest5
  (follows ProjTest4): Forget still restores the slots that lie in the
  viewport's present context (alive; Restore writes only where ours is
  still there, so a projection FMX remade for the new size is left).
  Dolly zoom: TSpritelyProjectionAccess.WithFieldOfView(P, Fov) (m11, m22
  scaled by (1 / tan(Fov / 2)) / m22: aspect, depth and shift kept) and
  FieldOfView(P); form Lens slider (5..120 deg, starts at the camera's
  FOV) applied before the kind (the parallel views take their size from
  it), and "Dolly (keep size)" (on): a lens change sets the orbit
  camera's Distance * tan(Fov / 2) unchanged, logged if the Subject stops
  the camera. Gorilla3D's camera keeps its own FOV, so the orbit camera's
  fits / ProjectToView do not know the lens yet - for the lib version.
- Owner (14:22): "yes create new components. Possibly place an oblique
  cube behind the camera in the icon to differentiate them. and yes the
  fit should follow." Gorilla3D's author "will likely want to add this to
  his own library anyway once he's seen what it does". Owner (14:27-14:29):
  how to test the dolly zoom (answered: cavalier for the level view, then
  perspective, Lens 45 -> 10 / 120 with Dolly; the wall scene shows it
  best) and "add model selection".
  ProjComp1 (follows ProjTest5): lib/Spritely.Projection.pas (NEW, in the
  Spritely runtime package): everything of ProjectionTestAccess
  (TSpritelyProjectionAccess, slots, hook, helpers; src/common/
  ProjectionTestAccess.pas DELETED, out of the .dpr / .dproj) plus the
  component TSpritelyProjection (Viewport: TControl that is an IViewport3D;
  Active; Kind pjPerspective / pjOrthographic / pjCavalier / pjCabinet /
  pjMilitary / pjOblique; FieldOfView (0 = own); Dolly; ShiftX / ShiftY;
  ObliqueAngle / ObliqueScale; Focus: TComponent with
  ISpritelyProjectionFocus (target distance, ProjectionLensChanged for the
  dolly); Distance without a Focus; ManageCulling (TGorillaViewport's
  FrustumCulling off while changing); OnLog). Its own TSpritelyRenderHook,
  first in the viewport (run time only); inside each frame: finds the
  projection in the drawing context by value (FindSlot: the context's
  instance memory, exact match to CurrentProjectionMatrix), then writes
  MakeMatrix(FMX's own) - lens, then orthographic / oblique at
  FocusDistance, then shift - or puts FMX's back when not Changing or not
  Active (also at once in Changed). ViewShape(SX, SY) describes it for
  fits (TSpritelyViewShape: Parallel, SX, SY, ShiftX/Y, ShearX/Y).
  Spritely.OrbitalCamera: TSpritelyOrbitalCamera implements
  ISpritelyProjectionFocus (focus = Distance; lens change moves Distance by
  tan(old / 2) / tan(new / 2)) and has published Projection (sets the
  projection's Focus, and the inner camera's Projection); the inner
  camera's FitCorners and ProjectToView use ShapeFor: perspective with
  shift (each axis' bounds AX..BX = (-Half - shift) / S ..(Half - shift)
  / S, eye = the tightest, centred in the slack; reduces to the old
  formula without a shift), parallel (corners sheared about the box's
  middle depth, Distance = picture size * S / 2 * margin, centre moved by
  shift * Distance / S, kept clear of the nearest corner), every-angle
  fits likewise (the narrowest side's room). Checked in Python: fitted
  corners land exactly at the margin, centred, with and without shift and
  shear. Gorilla3D's own orthographic mode keeps the old code.
  Spritely.Reg registers TSpritelyProjection; icon (tools/gen_icons.py
  projection(): a cavalier cube behind a white camera) and the .dcr
  (tools/gen_icon_res.py COMPONENTS); tools/gen_packages.py lists
  Spritely.Projection in Spritely (Spritely.dpk / .dproj). ProjectionTest's
  form rewritten on the component (made in code, the orbit camera's
  Projection): model box (models folder: glb, gltf, fbx, obj) + Open +
  Fit (FitToBounds in the projection drawn), Shift / Rise / Centre /
  Active, Kind / Angle / Depth / Lens / Dolly; the test turns the
  component off while it runs. PACKAGE REBUILD: Spritely (all platforms),
  dclSpritely (reinstall).
  Owner (14:41): "When trying DollyZoom in a previous session we had
  uvcube with a floor and a load of pillars - can you re-create that"
  (StereoCam15-17's test hallway, removed in StereoCam18) and "a button
  that resets the Inclination, Azimuth and Depth to 0 and additionally use
  those as the starting settings". tools/gen_dolly_hallway.py (stdlib,
  imports gen_demo_scene's Builder) writes models/DollyHallway.glb:
  uvcube.glb's mesh and texture copied in (2 units) on a 16 x 64 floor of
  2-unit squares (two greys), pillars 0.8 x 6 x 0.8 every 4 units at x =
  +-5 (every other pair red), end walls 16 x 8 (blue far, red near); FMX
  coordinates written as glTF (x, -y, -z) like the demo scene. Form:
  Front button = FrontView: azimuth 0, inclination 0, roll 0,
  FitToBoundsMax (the target on the model's centre: "Depth" taken as the
  model centre's depth against the target / glass = 0); LoadModel uses it,
  so it is the start view (StereoModel's 52 / 75 test view no longer
  used here). CHECK with the owner that "Depth 0" meant that.
  Owner (14:54, an Ultima VII map): "a hand-drawn Military/Cavalier
  projection?" - answered: a planometric oblique, the plan true shape and
  square to the screen (not military's 45-degree turn), height drawn
  up-left at 45 degrees (Exult shifts each lift equally left and up;
  scale not checked). Owner (14:56): "Add a camera called Ultima-Style
  that sets this automatically": TSpritelyProjectionKind pjUltima (angle
  SPRITELY_PROJECTION_ULTIMA_ANGLE 315 = depth down-right, so height
  up-left; scale 1); the form's box puts the camera at azimuth 0,
  inclination 90 for it.
  Owner (15:02, a Baldur's Gate 1 screenshot; "I have the others but
  they're the same I think"): not oblique - an orthographic camera
  (towers parallel across the picture) tilted about 45 degrees down,
  measured from the square fountain pools' foreshortening (rough, +-5),
  the scene turned ~30-40 degrees, each building its own way. pjInfinity:
  the same projection as pjOrthographic, a name for the look; the form
  puts the camera at azimuth 35, inclination 45. (Owner's "No, not BG1"
  at 15:03 was about which game, not a refusal - CHECK if unsure.)
  Owner (15:10): "What about Diablo 2's projection?" - answered: 2:1
  dimetric (pixel-art "isometric"; tile edges 2 across for 1 up), an
  orthographic camera at azimuth 45, inclination 30 (ArcSin 1/2); true
  isometric is 35.264. Owner: "Add it as TrueIsometric - Blizzard may get
  upset over trademarks (I guess EA may also over Ultima)". RULE: NO GAME
  OR TRADEMARK NAMES in identifiers, UI or README (the history here may
  name the games). ProjComp2 (follows ProjComp1): pjUltima -> pjPlanOblique
  (SPRITELY_PROJECTION_PLAN_OBLIQUE_ANGLE 315), pjInfinity -> pjTrimetric
  (azimuth 35, inclination 45 - trimetric, as the azimuth is not 45), new
  pjTrueIsometric (45 / 35.264, SPRITELY_PROJECTION_ISOMETRIC_INCLINATION)
  and pjDimetric (45 / 30, the Diablo II look); the three are orthographic.
  The camera presets moved from the form into the component:
  TSpritelyProjection.PresetAngles (class), ApplyCameraPreset, published
  CameraPreset (default True; SetKind turns the Focus, not while loading);
  ISpritelyProjectionFocus gains ProjectionViewAngles(Azimuth,
  Inclination) (new GUID), TSpritelyOrbitalCamera sets Azimuth, PolarAngle
  and Roll 0. The form's KindChange only sets Kind. PACKAGE REBUILD.
  Owner (15:16, a ProjComp1 screenshot, maximised): "FullScreen the
  projection dropdown opens in middle of scene" - FMX's TComboBox put its
  list far above the box, at the window's bottom edge. ProjComp3 (follows
  ProjComp2, program only): KindBox and ModelBox are TPopupBox (FMX.ExtCtrls; Items,
  ItemIndex, OnChange as before; the list is a popup menu placed at the
  box); FMX.ListBox out of the uses. CHECK it opens beside the box.
  3b: FMX.ExtCtrls added (E2003 TPopupBox). Owner (15:26): "First chance
  exception at $0000000000000000 ... ACCESS_VIOLATION" with the log of
  that run (Release, no FastMM5): it ends "Log closed normally", so the AV
  came during the form's destruction, after FormClose; a call through a
  nil pointer, cause not seen. ProjComp4 (follows ProjComp3b): TPopupBox
  dropped again (new since the last clean exit, a native popup menu) -
  KindBox / ModelBox are TComboBox, and ControlLayout is Align Top so the
  lists open downwards; FormClose now frees FProjection (camera's
  Projection nil first) and FAccess itself, logged, while everything is
  whole. If the AV stays, ask for the call stack (Debug build, the IDE's
  Call Stack window when it stops). Also (owner, 15:26): the hallway's
  near wall stopped the camera ("We can't get past it"):
  gen_dolly_hallway.py writes no near wall now, DollyHallway.glb made
  again.
  Owner (15:34, ProjComp4 log): no AV; the log ends "Projection component
  freed / Projection access freed / Log closed normally"; presets work
  (2:1 dimetric turned the camera to 45 / 30, plan oblique to 0 / 90);
  dolly 5..118.6 deg fine. But a Windows chime on exit, no dialog seen -
  cause unknown (asked: Debug build under the IDE, its Event Log for a
  first-chance exception at exit, or Windows' Event Viewer, Application).
  Owner (15:42): "remove the start-up tests ... pointless now ... leave
  the code just skip it". ProjComp5 (follows ProjComp4, program only):
  constant AUTO_TEST = False in ProjectionTestMain - the test no longer
  runs after the first load; the Run test button still runs it.
  Owner (15:48): a "Free Movement" checkbox - the camera kept out of the
  model "is causing issues with DollyHallway" (its box is the whole
  hallway). ProjComp6 (follows ProjComp5, program only): FreeCheck (row
  1, after Active): ticked, SpritelyOrbitalCamera1.Subject := nil
  (SubjectWanted; LoadModel too), unticked the model again; logged. The
  wheel still scales Distance, so it closes on the target but never
  passes it.
  Review of ProjComp1 (before delivery), fixed: (1) TSpritelyOrbitalCamera's
  destructor no longer calls FProjection.RemoveFreeNotification - it is
  two-way and would leave the projection's Focus pointing at the freed
  camera; it clears the projection's Focus instead; (2) likewise
  TSpritelyProjection.SetFocus keeps the old focus's notice; (3) FitOnAxis
  (FitToBounds' target slide) is skipped in a parallel view of ours, whose
  size follows Distance - SetTargetDepth still changes a parallel view's
  size (its size IS the target plane's); (4) the slot is only written in
  the viewport's present context (SlotAlive), never after the context
  was made again; (5) a projection not found is looked for (and logged)
  once per context until a property changes (FFailedContext), not every
  frame; (6) the camera's own field of view is read every frame, so the
  first dolly step starts from the real lens.
  DELIVERED as ProjComp1 (follows ProjTest5; src/common/
  ProjectionTestAccess.pas to be DELETED by the owner).

## Where the work is

- `TSpritelyOrbitalCamera` (`lib/Spritely.OrbitalCamera.pas`): a non-visual
  component wrapping Sprite3D's orbit camera (renamed
  `TSpritelyOrbitalGorillaCamera`), with `Headlight`, the projection
  properties, fits and `Subject`. Registration unit and icon done.
- Packages (StereoCam8, owner 7 November 2026, as TSteamAPI does them):
  `packages/Spritely` (runtime; DCUs to `$(BDSCOMMONDIR)\Dcp\$(Platform)`,
  `\Dcp` for Win32, so programs need no paths) and `packages/dclSpritely`
  (design; Win32 + Win64), written by `tools/gen_packages.py`. Spritely
  requires Gorilla3D's runtime package `Gorilla3D_Delphi_13_2_0_Florence`
  (the name from StereoModel's DCC_UsePackage; it has no WinARM64EC entry,
  so neither has Spritely). StereoGroup.groupproj shows StereoModel,
  Spritely, dclSpritely and builds Spritely, dclSpritely, StereoModel, with
  Dependencies; check they survive the IDE's re-saves (TSteamAPI's group
  lost its Dependencies three times). NOT YET BUILT.
- `src/ui/StereoModelMain` (StereoCam8): the component is on the form,
  `SpritelyOrbitalCamera1` in the `.fmx` with `Viewport = GorillaViewport1`
  (last in the file, so the viewport has loaded first); the `.dpr` /
  `.dproj` no longer list `lib` or search it. The program's WinARM64EC
  target cannot link Gorilla3D or Spritely (no packages there).
- StereoCam8 first install (owner): TSpritelyOrbitalCamera greyed out on
  the palette - no ComponentPlatformsAttribute; StereoCam9 adds it.
- Picture placement (owner, 7 November 2026): tried and REMOVED. Truck /
  pedestal (StereoCam10) moved the camera, so the view changed; a lens
  shift through a GetProjectionMatrix override (StereoCam13) drew nothing,
  because Gorilla3D's context builds the projection from
  GetProjectionSettings, a record of Kind, OrthoHeight and OrthoWidth only;
  moving the viewport control (StereoCam14) was rejected ("it just moves
  the VP"), and so was rendering larger and cropping. StereoCam15 removes
  it all. A true lens shift needs Gorilla3D: TO ASK ITS AUTHOR (owner
  relays) an offset in TGorillaProjectionSettings (OffsetX / OffsetY in
  normalised device units, applied in ToMatrix by adding Offset times the
  w column to the x and y columns), or a way for a camera to supply its
  own matrix. The stereo pair needs the same (off-axis frustum per eye for
  convergence without toe-in). Terms: shift and rise/fall (view camera);
  pan/tilt turn the camera; truck/pedestal move it.
- Dolly zoom: tried and REMOVED (StereoCam15 to 17, owner, 14:54: "take
  that out too - earlier was better"). The arithmetic was right (the
  owner's log: Distance * tan(FOV / 2) held at 2.00 from 45 degrees to 10),
  and FOV and FMX's AngleOfView both changed on the camera, but Gorilla3D
  1.5.3 did not draw with the new lens: first plain zooming (distance
  only), then, with ProjectionChanged called, a slow zoom. Changing the
  field of view at run time does not behave in Gorilla3D as expected -
  ask its author before trying again. StereoCam18 puts the component back
  to StereoCam9's file exactly, and the test form to left-drag orbit, wheel
  zoom, no click resets, right button unused; the test hallway went with
  it.
- StereoCam19 (owner, 15:03): `SetTargetDepth` moves the orbit centre
  along the line of sight with the camera fixed (Distance becomes the
  depth; for the 3D display's convergence plane later); test form:
  right-drag vertical, 1.01 per pixel, up deeper. Fit overloads on the
  component for the target space: `FitToBounds` / `FitToBoundsMax` with a
  model, an array of models (union of GetAbsoluteBoundingBox), a box in
  the scene's space, or a box in an object's space (part of a model);
  each sets target and distance from the current angles, FOV and
  projection.
- StereoCam20 (owner, 15:12): File, Open. The filter is built from
  TGorillaLoader.FileTypes (a dictionary keyed by extension, filled by each
  loader unit linked in), so it lists exactly what loads; loaders in
  StereoModelMain's uses: GLB, GLTF, OBJ, FBX, DAE, STL, PLY, USD (owner:
  USD is fine now; Sprite3D left it out for a problem in an earlier
  Gorilla3D), Babylon, G3D. Left out: Gorilla.Mayo.* and Gorilla.SKP
  (external libraries, as far as known) and Gorilla.Sketchfab (web). A new
  model replaces the old only once it has loaded. File menu hidden on
  Android / iOS. src/common/FmxLinuxMenu.pas: an UNCHANGED copy of
  TSteamAPI's (identical in its demos) - never edit it here, re-copy;
  its comments are TSteamAPI's PasDoc style, not ours, so pasdoc_check is
  not run on it. ReplaceMainMenu(Self, MainMenu1) is first in FormCreate.
- StereoCam21 (owner, 15:27, Mage.glb shown with its feet in the middle):
  fits now frame as Sprite3D does (FitCameraToSweep): FitToBounds = the
  box's corners through the inner camera's FitPointsOnAxis, centred, target
  on the turning axis (ASpace's Y through the centre of rotation);
  FitToBoundsMax = the ball round the corners centred ON THAT AXIS halfway
  up (not on RotationCenter itself, which was the cause: Mage's is at his
  feet), every angle safe. Boxes and groups take an optional rotation
  centre (TPoint3D overloads); without it a box or group turns about its
  middle, a box in an object's space about that object's RotationCenter.
- MEMORY LEAK opening several models (owner, 15:27, FastMM5 log): ALL in
  Gorilla3D 1.5.3, none of ours - the FBX loader's parse tree is never
  freed (6848 TFBXNode, 16036 TFBXProperty, 3709 + 6848 TObjectList, 6848
  TDictionary<string, TObjectList<TFBXNode>>, for the FBX files of that
  run), one Gorilla.Imaging.TGA.TTargaFileFormat, and two TStringList
  holding shader source (vertPos, return vec4). For Gorilla3D's author,
  with the projection-offset and field-of-view questions.
  CAUSE FOUND (8 November 2026): the leak comes with
  TGorillaModel.LoadNewModelFromFile, the class function LoadModel used.
  Sprite3D, with the same FBX loader, does not leak: it makes the model
  itself (TGorillaModel.Create(viewport)) and loads with the instance
  method LoadFromFile. StereoCam63 loads that way (LoadModel frees the new
  model if its load fails). Owner (8 November 2026, 12:22): "The fix
  works". Not reported separately: whether the TGA and shader TStringList
  leaks went too; if a later dump shows them, they are a separate
  Gorilla3D bug.
- Glasses-free 3D (owner, 7 November 2026, 15:53): the target is a lenticular display,
  through peardox/SRDelphiFMX's bridge. Step 0 (StereoCam22): a NEW
  PACKAGE, Lenticular, separate from the camera package (requires rtl,
  dbrtl, fmx; not Gorilla3D, not Spritely), for "a few" Lenticular components,
  made in code first and put on forms soon after (then they get a design
  package and icons). Persistent data as SRDemoFMX keeps it, with Neon.
  Units: Lenticular.Storage (Sprite3D's Sprite3DStorage, renamed:
  AppDataFolder, TLenticularStorage), Lenticular.Display.Settings
  (TLenticularDisplaySettings: UseGlassesFree3D, EyeSeparationMM, LookAround,
  LatencyFrames, LensMode, FullScreen; %APPDATA%\Peardox\Lenticular.json,
  shared by all Peardox programs; SRDelphiFMX's own settings.json is NOT
  shared, as saving it would drop its other members), LenticularBridge.Api
  (SRDelphiFMX's LenticularBridge.Api at 9530011, comments as //**, imports under
  {$IFDEF MSWINDOWS} so it compiles everywhere, lnb_RenderScene left out;
  keeps the bridge's C names lnb_*/TLNB*, like Winapi - keep in step with
  SRDelphiFMX), Lenticular.Display (TLenticularDisplay: Installed, Start with
  lnb_Probe on a thread and the answer posted to an AllocateHWnd window,
  lnb_Initialize with the bridge's own DX11 device (Gorilla3D is OpenGL,
  so no zero copy), bridge window hidden and lens off since nothing is
  woven yet, then a TTimer polls events, bounds, window mm and eyes, logs
  once a second; Stop; OnLog/OnStarted/OnStopped/OnProblem/OnEyes).
  Neon's 7 units the settings need are compiled into Lenticular (so
  their DCUs are in the Dcp folders), and StereoModel's search path no
  longer has delphi-neon (two builds of one unit otherwise). ONLY ONE
  PACKAGE MAY CONTAIN NEON: if the camera package ever needs settings,
  move Lenticular.Storage and Neon into a shared base package. (Rename1: Neon
  dropped for System.JSON, and the sets now share nothing.) SRDelphiFMX is
  a submodule at the root (the owner adds it:
  `git submodule add https://github.com/peardox/SRDelphiFMX SRDelphiFMX`),
  for its dll\LenticularBridge.dll, copied beside StereoModel's Win64 exe by its
  post-build step; never change it here. Test form: FDisplay made in
  FormCreate (Control = GorillaViewport1), Stereo button (StaysPressed)
  hidden unless Installed, pressed = Start, released = Stop, choice saved;
  auto-start after the first model load when UseGlassesFree3D; Stop in
  FormClose. Owner's first run (branch `stereo`, push 0c89b44, 16:21,
  under the debugger): works - background check 937 ms, then
  lnb_Initialize 9.2 s on the main thread (window frozen; SRDemoFMX
  measured ~0.2 s without the debugger and ~20 s to first frame under F9,
  so probably the debugger and NVIDIA's DLL loads: judge without it), the display
  1.36.4, display 3840 x 2160, 596.7 x 335.7 mm, view mm follows the
  window (maximise / restore), UserLost / UserFound / LensOff events
  arrive and the EYES TRACK (separation 63-72 mm) with nothing presented;
  Stop / Start again fine. No 3D, as expected. StereoCam23 (owner: "Log
  to file please"): src/common/StereoModelLog.pas, StereoModel.log beside
  the exe (documents folder on macOS / mobile), the previous run's kept
  as StereoModel.prev.log, every ShowStatus line timed and flushed, ends
  "Log closed normally"; opened first in FormCreate, closed in FormClose.
  Owner's Release run (16:26, still from the IDE: its Event Log shows the
  debugger attached): lnb_Initialize again 9.2 s, and the UI was BLURRED -
  the bridge creates its lens hint inside lnb_Initialize in the state last
  set with lnb_SetLens, which starts as ON (bridge g.lensOn = true), so the
  lens was on through the whole start until our lnb_SetLens(0) after it.
  StereoCam23 also calls lnb_SetLens(0) before lnb_Initialize.
  Owner (16:29): without the debugger "much faster". StereoCam23's log
  (16:31, Debug build, debugger not known): no blur reported; start
  8.9 s (D3D11 device 3.4 s, weaver 4.4 s), and lnb_Finalize took 9.3 s
  (7 s of it AFTER "runtime context deleted": the bridge releasing its D3D
  objects / child window) - the window freezes for both; to look at if
  it holds without the debugger. A second start was stopped at once
  (clicks queued during the freeze). StereoCam24 (owner, 16:35: "Need
  some indicator to inform when Lens is on"): TLenticularDisplay.LensState
  (ldlUnknown / ldlOn / ldlOff, from the display LensOn / LensOff events,
  LNB_EVENT_LENS_ON = 14 / _OFF = 15 in the Api unit; unknown after
  Stop) and OnLensChange; the form's FLensLabel left of btnStereo: LENS
  ON red bold, Lens off grey, blank while not running. The log's first
  line now says whether a debugger is attached (IsDebuggerPresent).
  Owner's build of 24 failed (E2003 OnLensChange, LensState, ldlOn) only
  because Lenticular had not been rebuilt - the program takes the
  package's DCUs from the Dcp folder. StereoCam25 (owner, 16:40: "Changing
  the depth with RightDrag made wheel zoom behave badly in big jumps"):
  Zoom scales Distance, the distance to the TARGET, so after a deep
  SetTargetDepth (the log had 1186) a notch moved the camera ~110 units.
  The test form's wheel now steps by a share of the camera's distance to
  the MODEL's box centre, moving along the line of sight (Distance minus
  the change), at least MIN_TARGET_SHARE (5%) of Distance left when the
  target is in front of the model; FZoom tracks the model distance. Form
  only, the component's Zoom is unchanged.
  StereoCam26 (owner, 16:47: wants the model to pop out, "a Z of < 0 but
  right drag won't permit this"): the target depth is a distance from the
  camera, always > 0; pop-out is the TARGET DEEPER THAN THE MODEL (drag
  up), which right-drag already allows (the log went to 1186). The status
  line now says it: DepthStatus gives the model centre's Z against the
  glass, Z = depth along the line of sight - target depth (< 0 in front,
  out of the screen), and in mm while the display runs, at mm per unit =
  view height mm / (2 * target depth * tan(FOV / 2)), FOV taken as
  vertical. Nothing shows on the display until step 1 weaves.
  Owner's log (16:54, debugger attached): (1) the indicator never went
  red - only one LensOff event came (after lnb_Initialize), never LensOn,
  yet the owner says the lens WAS on whenever it showed blank (unknown:
  during the start and after Stop). Events only tell of changes once the
  bridge's listener exists, so the start's state and the state after
  lnb_Finalize are not seen. The SDK has a lens query and
  a lens preference for a new context (SRDelphiFMX's runtime imports),
  but the bridge exposes neither: OFFERED, NOT DONE - a bridge export
  lnb_GetLensState and creating the context with the lens preference
  (owner's MSVC rebuild of SRDelphiFMX). (2) "a sudden jump and the
  target appeared to move vertically": right drag took the target depth
  to 7 362 159; the camera position is the target less Distance in
  SINGLE precision, so the camera drifted (model depth 4.837 -> 13.479)
  and stayed moved. StereoCam27: SetTargetDepth clamps to the viewport's
  FarPlane (SPRITELY_ORBITAL_MAX_TARGET_DEPTH 10000 without one; drift was
  0.002 at 7000), the status line says AT THE LIMIT there; the lens
  indicator shows "Lens ?" (orange) when unknown instead of blank, and
  is hidden with the button where the display runtime is not installed.
  Bridge (owner, 16:59: "give me the bridge. I'll build and push"):
  zip LenticularBridgeLens1 for peardox/SRDelphiFMX - NewContext() makes the display
  context with the runtime's lens preference (g.lensOn) (optional export) for
  lnb_Initialize and lnb_Probe, and a new export lnb_GetLensState (the runtime's
  own lens state; 1 / 0 / -1); SRDelphiFMX's LenticularBridge.Api, README and
  CLAUDE.md say so; its demos unchanged (they ask for the lens on).
  StereoCam28 here: LenticularBridge.Api declares lnb_GetLensState;
  TLenticularDisplay reads it right after lnb_Initialize and at every poll
  (ReadLens, when LenticularBridgeHasExport says the bridge has it), the events
  still followed too. The submodule SRDelphiFMX must be updated to the
  owner's push for the new dll\LenticularBridge.dll.
  Owner (17:11) saw "Lens ? in red": that run never started the display (the
  saved choice was off, Stereo not pressed), so unknown was right, but
  dark orange read as red. StereoCam29: LENS ON red bold, Lens off
  green, Lens ? grey. The bridge lens reading is still to be seen.
  Owner's log 17:17: bridge lens reading WORKS ("Lens off (read from
  the display)", context made lens off), tracking with nothing presented.
  Owner (17:20): "Lets move on to doing some drawing" (start timings left
  for a Release run without the debugger).
- STEP 1, first light (StereoCam30): TLenticularDisplay gains Weaving (shows
  the bridge's window, lnb_SetVisible, and asks the lens on; cleared by
  Stop), SubmitViews (lnb_SubmitViews, BGRA or RGBA, results counted and
  logged once a second) and UpdateEyes. src/common/StereoModelEyes.pas
  (program unit until it works, then lib): TPeardoxGorillaEyes - timer
  16 ms; per eye moves the orbital camera's inner Gorilla camera (child of
  RollPivot, normally at (0, 0, -Distance), no rotation) to
  (OX, OY, -D), OX = dx * D / dz, OY = -dy * D / dz (dx, dy, dz eye mm
  from the view centre; FMX Y down), turned by RotationAngle (pitch, yaw)
  to look at the orbit centre - signs found by Calibrate (four tries
  against AbsoluteDirection vs pivot - camera, logged) - then
  RenderManual (viewport UseFixedFrameRate False, ManualRendering True
  while active, restored by Stop) and MakeScreenshot; camera put back;
  rows copied side by side into FBuffer, SubmitViews. Eyes: tracked with
  LookAround, the saved EyeSeparationMM rebuilt about the midpoint;
  else a fixed viewer 650 mm in front of the view centre. Form: started
  in DisplayStarted, stopped in DisplayStopped / FormClose; keys S (swap
  eyes) and R (RenderManual before the screenshot or not). UNKNOWNS to
  read from the first log: whether RenderManual / MakeScreenshot work as
  hoped with Gorilla3D's ManualRendering, whether RotationAngle on the
  inner camera is honoured (the calibration scores), the frame rate.
  Owner's first light (17:33, debug + debugger): "Glasses free but not
  nearly as good as demo"; asked: LAG / JUDDER and DOUBLE IMAGES. Log:
  calibration yaw -1 pitch 1 matched 0.99985 (RotationAngle honoured),
  every frame woven; 35 fps windowed (960 x 634: render 2.9, shot 1.8,
  copy 0.8, submit 9 ms - the 16 ms TTimer quantised it), 20-23 fps full
  screen (3840 x 1968: render 7, shot 8.7, copy 7.7, submit 10 ms).
  StereoCam31: frames from Application.OnIdle (Done := False, the old
  handler chained, a 50 ms watchdog timer; NOT TThread.ForceQueue, whose
  posted messages would starve timers, paints and input), paced by the
  bridge's vblank wait; Convergence ecShift (default): both cameras turned
  alike from the eyes' midpoint (parallel to each other), each picture
  shifted by ShiftFor = sign * offset / (D * tan(FOV/2) * W/H) * W/2 px
  (FOV taken as vertical), black strip at the edge - the off-axis frustum,
  removes toe-in's vertical mismatch at the corners; ecToeIn kept. Keys T
  (toggle), X (ShiftSign), S, R. Owner (17:37): "some of the FMX3D fields
  for the projection matrix are strictly private" but the Delphi source is
  there - RTTI can write private fields (TRttiField.SetValue) if we know
  which one Gorilla3D draws with; the shift already gives the off-axis
  pair, a real projection offset would add the eye's own field of view and
  lose the strip.
  Owner (17:47-17:58): X (shift sign -1) "marginally better", T (toe-in)
  "not bad either", still leaning to X; keys reacted too quickly (a held
  key's repeated key-down toggled again). StereoCam32: ShiftSign default
  -1; keys on OnKeyUp by virtual key code (vkS, vkT, vkX, vkR), once a
  press. Eye separation explained: 63 mm (Lenticular.json default), rebuilt
  about the tracked midpoint; near the glass the on-screen disparity
  matches real 63 mm eyes whatever the window size.
  Log 17:50 (debug + debugger): idle loop 44 fps windowed, 22 fps full
  screen (render 7.2, shot 8.9, copy 8.2, submit 9.5 ms); shifts +-79 px
  at depth 3.0. SUSPICION: X "better" may mean the camera's +X is the
  picture's LEFT - then the eye placement is mirrored too (each eye drawn
  from the other's side: depth inverted, pseudo-stereo) and S+X is the
  right pair; ASKED the owner to test (pop the cube out with right-drag
  up: in front or behind?). StereoCam32 also: each eye decimated to the
  display's recommended view width (DisplayInfo.recommendedViewWidth,
  1920; Step = W div it, every Step-th pixel / row), so full screen copies
  and uploads a quarter.
  StereoCam33 (owner, 18:03: "construct a model Gorilla3D can load from
  the scene in SRDemoFMX ... The cubes are the real show-off"):
  tools/gen_demo_scene.py (stdlib) writes models/DemoScene.glb and
  DemoSceneNoWall.glb from SRDemoFMX/ui/MainForm.pas's numbers: 121
  spheres (d 1.4, step 3, colours per depth row, centre lime green), 6
  cubes (3 units, Y +-4.5/9/13.5, #E8A33D), wall 60 x 40 at Z 18
  (#35507A, two-sided); FMX (x, y, z) written as glTF (x, -y, -z), as the
  program turns models 180 about X; sRGB colours made linear; animation
  "CubeSpin": each cube's rotation about Y keyed every quarter turn over
  8 s. LoadModel now plays the first animation
  (AnimationManager.PlayNextAnimation, TryGetCurrentAnimation logged) -
  untested whether Gorilla3D plays glTF node animations, and whether it
  loops.
  StereoCam34 (owner, 18:09: "display the azimuth and inclination so I
  can work out the proper angles for a definitive test scene"): the form's
  Caption shows ViewText (azimuth, inclination = PolarAngle, roll, target
  depth, model centre Z) after every orbit / depth drag step, wheel notch
  and fit; each drag's end logs "View: ..." (ShowStatus). ModelDepth split
  out of DepthStatus.
  Owner (18:23): the test view - inclination 75, depth 42, azimuth 52,
  roll 0, NoWall - "the 3D really pops out", make it the default; "a LOT
  of ghosting on the balls"; the owner has a cataract in the right eye
  (glasses for this screen), so judging is harder. StereoCam35: TEST_MODEL
  = DemoSceneNoWall.glb, TestView after it loads (angles, FitView, then
  Distance := 42, FZoom kept; "depth 42" taken as the camera 42 from the
  target on the scene's axis - CHECK with the owner if it was a moved
  target); Home = TestView for it, ResetView otherwise. For the
  ghosting: TLenticularDisplay.SetLatencyFrames (live lnb_SetLatencyInFrames,
  not 0) and keys L (latency 0..4, saved) and [ / ] (eye separation +-5 mm,
  20..90, saved). Ghosting suspects: latency (our frames read back through
  the CPU, 20-40 fps in Debug), big disparities (lenticular crosstalk
  grows with them; white balls on dark show it most), the point-sampled
  halving (shimmer, not ghosting).
  Owner (18:30): "The settings from SRDemoFMX were excellent ... log what
  the settings were ... we may be able to improve this version". Zip
  SRDemoSnap1 for SRDelphiFMX (synced to its push db0a459 first):
  the stereo renderer's LogSnapshot(Note) + SRDemoFMX key P. StereoCam36
  here: TPeardoxGorillaEyes.LogSnapshot(Note) + key P, the same
  quantities: display, view mm / px, eyes tracked and drawn from,
  settings, FOV, target depth, convergence, shifts, the IMPLIED scale
  (2 * D * tan(FOV/2) / view height mm) and with it the glass's distance
  in mm and the eyes' true distance / separation in units beside where
  the cameras really go (D and sep * D / dz), fps. Also the owner: "Your
  RightClick Drag may not be working as I desired. I think the axis it
  moves in should be that from the camera to the viewpoint not any given
  named Axis" - SetTargetDepth already moves along Orientation.Rotate(0,
  0, 1), the camera-to-target line; ASKED what he sees (at inclination 75
  that line is steep, so the target goes mostly up / down in the world;
  while weaving, the eyes' offsets scale with D, so the picture's depth
  and the look-around change).
  Owner (18:45): SRDemoFMX's Release snapshot - 60.0 fps locked (worst
  17-19 ms), every frame woven, eyes 3840 x 2160 each copied on the GPU
  (no decimation), weaver latency 31.7 ms, per-eye off-axis frustum at the
  real eye distance (zoom ~2.14, FOV ~22 deg, shear L -0.26 R -0.19 with
  the viewer ~20 cm left at ~87 cm), scale 0.04936 units/mm, glass 20 units
  from the reference camera; tilt 78 roll 10 scene spans 69 mm out to
  69 mm in.
  Owner (18:52): StereoModel's Release log, no debugger. Small window
  (960 x 634): render 11-12, shot 1.6-2.2, copy 0.8, submit 7.6-9.6 ms,
  29-37 fps. Maximised (3840 x 1968, woven at 1920): render 9.4-15.5,
  shot 8.7, copy 6.8, submit 7-9 ms, 20-25 fps. So shot + copy scale with
  size (option 2, render at the weave size, saves ~11 ms), but render
  (~10 ms for two eyes, Gorilla's per-object cost?) and submit (~8 ms:
  the bridge's frame cap, WaitForVBlank after Present) do not; 8 ms wait +
  25 ms work misses the next blank, so <= 30 fps. StereoCam37: key C
  toggles lnb_SetFrameCap (form field FFrameCapOff, re-applied in
  DisplayStarted, not saved). Also from the owner: StereoModel is not
  display aware (SRDemoFMX moves its window onto the 3D display); this
  run's log did say "The form is on the 3D display". The lens state is
  the 3D display's own, so LENS ON was true even with our window
  elsewhere - we just never check where the view is before weaving.
  PLAN (owner, 18:52 + 19:04), StereoCam38+: a 2D "launcher" form with
  the controls, and a borderless full-screen output form on the display
  display hosting the bridge's window, with the Gorilla viewport hidden
  under it at the recommended view (1920 x 1080 = option 2). Two
  monitors: both shown, wherever the user puts the launcher. One
  monitor (or by choice): the launcher hides while the output shows full
  screen, and Esc closes the output and restores the launcher - works
  whatever monitors there are; the user may want either. Weave only while
  the output is on the 3D display, else flat with the lens off. Two the display
  displays: ask which (not yet). Owner (19:04): "The purpose of the Stereo
  button has, since the start, to switch into full screen on the display" - so
  btnStereo opens the output form full screen on the 3D display (and
  starts weaving); Esc / btnStereo again closes it.
  Owner (19:21): "The cubes don't spin in StereoModel" (so Gorilla3D does
  not drive the glTF node animation, or not visibly); C pressed twice,
  nothing logged - the only frame cap line was the bridge's own. No key
  line (P included) has been logged since keys moved to OnKeyUp at
  StereoCam33: FMX's OnKeyUp never fired here. StereoCam38 (replacing the
  key part of 37): a thread keyboard hook (WH_KEYBOARD, as SRDemoFMX's
  InstallKeyHook / HookKey), local user32 externals (no Winapi.Windows,
  its names hide FMX's), acting on key-down, repeats (lParam bit 30)
  dropped but swallowed, only while GetActiveWindow = the form (not in the
  open dialog), the action queued (ForceQueue, once) to HandleKey.
  IsTestKey lists the keys. Non-Windows keeps OnKeyUp. RemoveKeyHook in
  FormClose and finalization. The render drop (~15.5 -> ~9.4 ms) came at
  17.7, 17.6, 20.8 (Debug) and 14.0 s after the model loaded - not a fixed
  time, and the cubes don't spin, so not the animation's length; cause
  unknown (clocks ramping? Gorilla warming up?).
  Owner (19:27, Release, C pressed 4x): frame cap on - submit 7-9.7 ms,
  23-25 fps, worst 40-43 ms; off - submit 0.9-1.0 ms, 31-32.5 fps, worst
  27-30 ms; repeatable both ways. Off: render 9.2 + shot 8.4 + copy 6.7 +
  submit 0.9 = ~25 ms of a ~31 ms frame (~6 ms outside the four: poses,
  FMX's idle loop). Owner (19:30): "No difference visually". StereoCam39:
  TLenticularDisplaySettings.FrameCap (published, default False, so old
  Lenticular.json files get off), TLenticularDisplay.SetFrameCap(AOn) (live, logs;
  not saved), lnb_SetFrameCap(Ord(FrameCap)) after lnb_Initialize, the
  start's settings line shows it; key C = SetFrameCap(not ...) +
  SaveSettings; the form's FFrameCapOff and its LenticularBridge.Api use
  gone. PACKAGE REBUILD (Lenticular). Next: the two-window layout
  (output form on the 3D display, view hidden at the recommended view
  1920 x 1080: shot + copy ~15 -> ~4 ms, so ~50 fps), and time the ~6 ms
  outside the four steps.
  Owner (19:37 log: StereoCam39 works, "frame cap off" after init).
  Owner (19:43), the two-window spec: the window starts with the lens
  off; Stereo = full screen on the 3D display, lens on, scene there; Esc
  or the button again stops it (the button has state); started on the display
  display, the main window hides until Stereo is off; on another screen it
  stays, button pressed; the lens indicator is now useless; Stereo is
  disabled until the display is available, so switching is quick. StereoCam40:
  FOutput (TForm.CreateNew, borderless, black, OnClose = caHide + Leave)
  with FOutputHost (TLayout client, HitTest, the view's mouse handlers) =
  FDisplay.Control; the display starts in FirstShown on the HIDDEN FOutput (lib:
  FindFormWindow needs a Handle, no longer Visible; LogStartDetails says
  "hidden for now"), UseGlassesFree3D no longer used by StereoModel;
  OnStarted enables btnStereo, OnStopped / OnProblem disable it.
  EnterStereo: DisplayRect (new lib TLenticularDisplay.DisplayRect), main
  hidden if its centre is on the display rect, SizeViewForStereo (viewport
  Align None, recommended view in physical px / scene scale, centred,
  ViewLayout clipped; FResizing stops ViewResize's refit both ways),
  FOutput.Show + PlaceOutput (SetWindowPos HWND_TOPMOST to the display rect,
  again once queued after the DPI change, logged), FEyes.Start.
  LeaveStereo: FEyes.Stop, hide FOutput, Align Client, show main. Key hook
  takes keys while either window is active; Esc = LeaveStereo while on.
  The viewport stays on the main form (not reparented): rendered by
  RenderManual even with the main form hidden - CHECK the eyes are not
  black then. FLensLabel and DisplayLensChange gone. PACKAGE REBUILD.
  Owner (19:53): started on the 3D display, Stereo -> full screen,
  "completely black image". Log: one frame submitted, then 0 fps (EyePair
  needs WindowSizeMM > 0), and the bridge's window measured "centre
  (-298.4, 167.8) mm, 0.0 x 0.0 mm" = a zero rect at screen (0, 0), what
  GetClientRect / ClientToScreen give for a window that no longer exists:
  FMX had made FOutput's window again at its first Show, destroying the
  bridge's child (lnb_Initialize had parent $6D1042). StereoCam41: FDisplayParent
  = FormToHWND(FOutput) in DisplayStarted; EnterStereo logs both handles and,
  if they differ, restarts the display on the shown form (FRestarting keeps
  OnStopped from leaving Stereo; DisplayStarted then FEyes.Start while
  FStereoOn); DisplayProblem leaves Stereo. Program only, no rebuild. NEXT
  LOG: does the handle change only at the first Show (then later toggles
  are quick) or every time; are the eyes still black with the main form
  hidden.
  Owner (20:02), two logs: started on the 3D display - handle changed at
  the first Show only ($551040 -> $561040), the display restarted (0.3 s), then 65-74
  fps, render 5.7, shot 2.5, copy 2.2, submit 1.0 ms; later toggles quick,
  no restart. Started on the widescreen - same restart, 47-56 fps, render
  7.9 ms, and "screen flashes horribly in the launcher window" (FMX painting
  the visible viewport while the eyes move its camera). Also: "The stereo
  button becomes enabled extremely quickly. Is it possible to click before
  the display is ready (first time the screen hung - had to task-manager kill)" - no
  log of the hang. StereoCam42: viewport Visible False while Stereo (FMX
  does not draw it; the eyes' RenderManual + MakeScreenshot still do - CHECK
  not black), FStereoNote label in its place; FirstShown shows FOutput once
  off-screen (-32000) and hides it before FDisplay.Start so FMX's re-make
  happens first (restart check kept as a fallback); FStereoWatch: if
  FEyes.WovenFrames (new, SubmitViews = LNB_OK since Start) is still 0
  STEREO_WATCH_MS = 3000 after weaving starts (StartWeaving), Stereo is
  turned off - a black topmost full-screen window can no longer trap the
  user. btnStereo is enabled only from OnStarted, after lnb_Initialize has
  returned: it cannot be clicked before the display is ready. Program only.
  Owner (20:10): "black screen... how about a 1x1 gorilla render window for
  2-screen mode?" Log: no restart ($3D0FDA both - the off-screen first
  Show worked), 104-130 fps but render 0.2-0.3 ms: Gorilla3D renders
  nothing for an invisible viewport. A 1x1 viewport would give 1x1 eyes
  (MakeScreenshot is the viewport's size). StereoCam43: viewport stays
  Visible, FStereoCover (TRectangle, Align Contents, opaque $FF202428,
  HitTest False, BringToFront) with FStereoNote (white) over it while
  Stereo is on. If FMX's painting of the covered viewport still costs
  (~7.9 vs 5.7 ms render), next: reparent the viewport onto FOutput under
  the bridge's window, or ask Gorilla's author for an offscreen render
  target.
  Owner (20:13): compile E2003 Combine / GetDocumentsPath - FMX.Objects'
  TPath (the shape) hid System.IOUtils.TPath; qualified in full (43b).
  Owner (20:15): "Still flashes", and render 14 ms, 37 fps: Gorilla3D's
  render shows in the window the viewport is on, cover or not. StereoCam44:
  FRenderForm (TForm.CreateNew, borderless, shown once off-screen and
  hidden in FirstShown like FOutput); while Stereo is on and the main form
  stays in sight, GorillaViewport1.Parent := FRenderForm (Align None, the
  recommended view in its physical px, the form's client sized to it), the
  cover with its note over the empty ViewLayout; back to ViewLayout on
  leave. With the main form hidden (on the 3D display) the viewport stays
  put - the proven 70 fps case. CHECK: reparenting a Gorilla viewport
  between forms keeps its context; not black; render ~5.7 ms.
  Owner (20:20): "Good" - StereoCam44 works from the widescreen: SRDemo
  scene 40 fps then 64 fps after the usual drop (render 6.2 ms), Mage.glb
  with its animation 75-84 fps (render 4.2 ms). "Loader needs way to select
  animation if there are any - see sprite3d for examples." StereoCam45:
  FAnimationBox (TComboBox, control strip, Align Right left of btnStereo,
  hidden without animations): (none) + AnimationManager.GetSortedAnimations
  Ids (as Sprite3D's Helpers list them); FillAnimations after a load picks
  the first and plays it; OnChange -> AnimationManager.PlayAnimation(Id), or
  Current.Stop for (none). Sprite3D's frame-exact player (TSprite3D
  AnimationPlayer) not needed here.
  Owner (20:24): "This functionality will eventually be merged into
  Sprite3D so nothing complicated is required" - RULE: keep StereoModel's
  copies of what Sprite3D does (animation choice and the like) minimal.
  Owner (20:29): "can we name [the 3D display] when in 3D mode". The bridge
  has no name export, but Windows has the EDID name: StereoCam46, lib
  TLenticularDisplay.DisplayName (LENTICULAR_DISPLAY_DEFAULT_NAME 'the 3D display'
  until known), set in LogStartDetails by MonitorNameAt(centre of the display
  rect): MonitorFromPoint + GetMonitorInfoW (\\.\DISPLAYn), then
  QueryDisplayConfig's active paths, DisplayConfigGetDeviceInfo source name
  to match, target name -> monitorFriendlyDeviceName, the EDID maker code
  (SAM...) decoded and put in front if the name lacks it (MakerName, a small
  table). Own declarations (TPdxDC* records sized as in wingdi.h: path 72,
  source name 84, target name 420 bytes), user32 externals renamed Pdx*.
  Logged "The 3D display is ..."; StereoModel's note and Stereo-on status
  use it. PACKAGE REBUILD. Check whether the bridge's child window
  passes mouse messages through (drag on the output vs on the launcher).
  Owner (20:33): DisplayName undeclared + ForceQueue E2250 (knock-on) -
  the package had not been rebuilt; 46b also drops Eyes' unused
  RGBA := False. Owner pushed "2 windows" 977a107 and "Stupid gitignore"
  273bb9d (logs out of git, *.log and Win64/ ignored); synced, every file
  matches.
  ZERO COPY (owner, 20:45: "SRDemoFMX already does ZeroCopy ... for people
  with worse [laptops] ... all the speed we can give them helps"). Plan, no
  bridge change: StereoModel makes its own D3D11 device on the 3D display's
  adapter and gives it to the bridge (lnb_SetExternalDevice before
  lnb_Initialize, as SRDemoFMX gives FMX's); two eye textures on it,
  registered with OpenGL through WGL_NV_DX_interop2 (wglDXOpenDeviceNV,
  wglDXRegisterObjectNV, Lock / Unlock); after each eye's RenderManual,
  glBlitFramebuffer from Gorilla3D's picture into the eye texture, flipped
  (GL is bottom-up); then lnb_CopyEyeTexture(eye) and lnb_PresentViews
  (the bridge accepts any texture on its device). Screenshot route kept as
  the fallback. Saves shot + copy + upload, ~6 ms of a 12-14 ms frame.
  Step 1, StereoCam47: src/common/StereoModelGLProbe.pas (new; .dpr +
  .dproj) ProbeGL logs once, after the first eye's RenderManual and after
  its MakeScreenshot: current GL context / DC, vendor / renderer / version,
  WGL_NV_DX_interop2 + wglDXOpenDeviceNV, draw / read framebuffer,
  renderbuffer, 2D texture bindings, the read framebuffer's colour
  attachment (texture / renderbuffer, name, size, internal format,
  samples), and by RTTI the viewport's TTexture / TContext3D fields
  (contexts one level deeper) and integer fields named *FBO* / *FRAMEBUF* /
  *RENDERBUF* / *TEX*. Program only. 47b: GLInt hid the type GLint (Delphi
  is case-blind) - GLInteger; FMX.Types for TPixelFormat.
  Owner (20:51), the probe's answer: after RenderManual the context is
  current, NVIDIA RTX 5090 OpenGL 4.6 (driver 610.47), WGL_NV_DX_interop2
  there; draw and read framebuffer 3, its colour attachment texture 24
  1280 x 720 GL_RGB8 - the viewport's LOGICAL size (1280 x 720 at scale
  1.5; MakeScreenshot gave 1920 x 1080, so it renders again or scales);
  after MakeScreenshot still framebuffer 3. glGetError $502 (ours or
  Gorilla's, harmless). RTTI found no fields in TGorillaViewport.
  StereoCam48, zero copy: bridge export lnb_GetDevice (zip LenticularBridgeDevice1
  for SRDelphiFMX, which also carries the unpushed SRDemoSnap1 files: the
  bridge's g.dev, not AddRef'd; README / CLAUDE / LenticularBridge.h / .Api.pas);
  LenticularBridge.Api declares it; TLenticularDisplay.BridgeDevice (nil without
  the export) and SubmitEyeTextures (lnb_CopyEyeTexture x2 +
  lnb_PresentViews, counted by the new CountSubmit as SubmitViews is).
  src/common/StereoModelGLInterop.pas (new; .dpr + .dproj):
  TPeardoxGLInterop - two B8G8R8A8 textures made on the bridge's device
  (own IPdxD3D11Device declaration up to CreateTexture2D, no Delphi D3D
  headers), wglDXOpenDeviceNV, registered as GL textures (WRITE_DISCARD),
  each attached to an FBO; CopyEye: lock, bind own FBO as draw, scissor
  off, clear black if shifted, glBlitFramebuffer from the still-bound read
  FBO with Y flipped and X shifted, put back draw FBO / scissor / clear
  colour, unlock; SourceSize reads the read FBO's texture size. Eyes:
  ZeroCopy (default True, key Z), PrepareZeroCopy after a screenshot-path
  RenderManual (GL current) makes FInterop at the source size; CanZeroCopy
  frames: RenderEyeGPU x2 then SubmitEyeTextures (timings: screenshot slot
  = blit, copy 0, submit = present); a failure falls back to screenshots
  for that device (a size change just remakes). Main: with
  ZeroCopyPossible the viewport is sized at the view size in LOGICAL units
  (Scale 1), so Gorilla3D draws 1920 x 1080. PACKAGE REBUILD and BRIDGE
  REBUILD. 48b: glIsEnabled returns a Byte (GLboolean) - "<> 0".
  Owner (21:06): zero copy set up ("two 1920 x 1080 eye textures"), one
  screenshot frame woven, then the dialog "cannot begin rendering scene for
  TContextOpenGLWindows: 1282" (GL_INVALID_OPERATION) and 0 frames; on exit
  "Runtime error 231". FMX's OpenGL context (FMX.Context.GLES, DoBeginScene)
  raises if ANY glGetError is pending; the probe had already seen $502
  pending after RenderManual (Gorilla3D's, or ours), and on the screenshot
  route MakeScreenshot took it. Owner: SRDemoFMX hit the same kind of thing
  ("needed Delphi's OpenGL context source"). StereoCam49:
  TPeardoxGLInterop.TakeErrors (glGetError until GL_NO_ERROR, at most 32)
  after RenderManual and after the blit in RenderEyeGPU, each place's first
  error logged (NoteGLError), and at the end of Start / Release; Start
  keeps its HGLRC / HDC and Release makes them current (wglMakeCurrent)
  when none is, so the GL side is undone; Eyes.ReleaseZeroCopy in FormClose
  (before the display stops, while the context exists) and in DisplayStopped. Program
  only.
  Owner (21:10): "Not as bad (but not great either)" - ONE 1282 dialog,
  then ZERO COPY WORKS: ~9 fps while the modal dialog was up (watchdog
  frames), after OK 55 fps, then after the usual drop 90-110 fps, render
  7.2, blit 0.4, copy 0, present 0.2 ms (screenshot route ~65-75 fps).
  "OpenGL error $502 after the zero-copy blit (ours)" logged; none after
  RenderManual. The dialog came on the set-up frame: PrepareZeroCopy runs
  on both eyes' screenshot renders, and on the second its SourceSize (bind
  the attachment texture to read its size, bind the old one back) left
  $502 for MakeScreenshot's BeginScene. StereoCam50: SourceSize reads the
  size by name with glGetTextureLevelParameteriv (GL 4.5, optional, else the
  old bind) and always ends with TakeErrors.
  Owner (21:14): no dialog, zero copy 90-109 fps (render 7.2, blit 0.4,
  present 0.2 ms), no GL error logged - "But also no image". The blit
  copies nothing without an error if the source's read buffer is GL_NONE
  (or the colour mask / scissor interfere). StereoCam51: CopyEye sets read
  buffer COLOR_ATTACHMENT0, colour mask all on, scissor off for the copy
  and puts each back; once a second (Eyes -> FInterop.CheckNext) it logs
  "Zero copy check": source FBO, read buffer, colour mask, sRGB writes,
  scissor, and the middle pixel read back (glReadPixels, skipped if a pack
  buffer is bound) from the source and from the eye texture after the
  blit - so the next log says whether the picture reaches the eye texture
  (GL side) or is lost after (D3D / bridge side).
  Owner (21:17) log: every check "source framebuffer 3, read buffer $8CE0,
  colour mask 1111, sRGB writes False, scissor False | middle pixel RGBA
  source 0 0 0 0, eye texture 0 0 0 0", and $502 after the blit. RGB8 read
  as RGBA would have alpha 255, so the reads failed too: FBO 3 is
  MULTISAMPLED (FMX 3D views render with 4 samples; the probe's
  GL_TEXTURE_2D bind of an MS texture failed - the old $502 - so its
  "samples 0" was another texture's). A multisampled framebuffer may only
  be resolved same rect, same format: our flipped / shifted blit into BGRA
  was GL_INVALID_OPERATION. StereoCam52: Start reads GL_SAMPLES (source FBO
  bound as draw for a moment) and the source texture's internal format
  (DSA), and when samples > 1 makes FResolveFBO + FResolveTex (that format,
  glTexImage2D); CopyEye resolves source -> FResolveFBO (same rect,
  NEAREST), reads from there for the flipped / shifted blit and the check,
  and puts read FBO, draw FBO and read buffer back. Logged "the picture has
  N samples per pixel ... resolved first".
  Owner (21:20): "4 samples per pixel, internal format $8814" (RGBA32F -
  a float, likely HDR, target), no GL errors now, but the resolved middle
  pixel still 0 0 0 0 (alpha 0 too) and no picture. So FBO 3 after
  RenderManual is probably not where the finished picture is (Gorilla3D
  may render HDR into FBO 3 and finish - tone-map / post - into another
  target; texture 29 is bound after RenderManual). StereoCam53: one-off
  TPeardoxGLInterop.Survey after Start - textures 1..64 (>= 256 px): target,
  size, format, samples and, for 2D, the middle texel as floats
  (glGetTextureSubImage); framebuffers 1..16: colour attachment 0 (DSA, so
  nothing bound).
  Owner (21:23): "Crash..." after the survey's texture 30 (the next texture
  or the framebuffer part). The map (all 1920 x 1080): 1 2D RGBA8 (middle
  0,0,0,1), 2 MS4 RGBA8, 11 and 14-18 2D RGBA8 (0,0,0,0), 19-24 MS4: RGBA8,
  RG16F $822E, RGBA16F $881A, RGB16F $881B, RGB8 $8051, RGBA32F $8814
  (= FBO 3's attachment) - a deferred G-buffer + HDR target, with 25-30 2D
  copies of the same formats. EVERY middle texel was background (normal
  RG 0, position 0): with the eye camera offset the middle falls between
  spheres, so the 0 0 0 0 checks proved nothing. StereoCam54: Survey no
  longer called (kept); the check counts lit pixels of a 3 x 3 grid in
  the source and in the eye texture. ASKED the owner whether the 21:20
  run (resolve in place) showed a picture. If FBO 3 (HDR, before tone
  mapping) is the wrong source, texture 1 (RGBA8, alpha 1) is the likely
  finished picture.
  Owner (21:25): "black"; the grid read source 0, eye texture 0 at 90-110
  fps: FBO 3 holds nothing usable after RenderManual. StereoCam55:
  FindPicture (in Start) walks framebuffers 1..32 with safe calls only
  (glIsFramebuffer, DSA attachment and texture queries - no
  glGetTextureSubImage, the likely survey crash), reads a 3 x 3 grid of
  every eye-sized 2D one, and of every MS RGBA8 one after resolving it
  into a temporary RGBA8 target; logs each ("framebuffer N, texture T,
  ... lit L of 9") and copies from the most lit (FSourceFB), else the
  bound one. CopyEye binds FSourceFB for reading and puts the bound one
  back after.
  Owner (21:31, StereoCam55): "a picture - but the frames are
  misaligned". FindPicture chose framebuffer 1 (texture 2, FMX's MS4
  RGBA8, lit 3 of 9; framebuffer 2 = texture 1 its resolve, also 3);
  FBO 3 (HDR) is not readable, FBO 4 (texture 30) lit 0. Zero copy: 95-106
  fps, render 7.3 ms, copy 0.5, submit 0.2 (screenshots at the weave
  size were ~70). The checks show the eye texture matching the source
  (middle pixels equal bar edge pixels), so the copy is current and
  whole. StereoCam56: key F (TPeardoxGorillaEyes.ZeroCopyFlip ->
  TPeardoxGLInterop.FlipRows) turns the row flip off, to test; S, X and
  Z (screenshots) are the other comparisons. ASKED the owner what the
  misalignment looks like.
  Owner (21:37): only Z did anything - "the mis-aligned image again";
  F, S and X were black. That run's FindPicture found nothing lit at the
  3 x 3 points (framebuffer 1 lit 0) and fell back to FBO 3 (black); so
  the misalignment is in the SCREENSHOT path too, not zero copy's.
  Screenshots there: 2880 x 1620 per eye, ~40 fps (screenshot 5.1, copy
  4.9, submit 2.0 ms). StereoCam57: FindPicture reads an 8 x 8 grid and,
  with nothing lit, takes the first MS RGBA8 framebuffer (FMX's), then
  the first 2D RGBA8, never the HDR target; FormKeyUp only off Windows
  (H2219). ASKED again what "misaligned" looks like and whether the
  screenshot picture was right before the zero-copy work.
  Owner (21:38): the misalignment is the old ghosting (SRDemoFMX too);
  SRDemoFMX's cure is a per-eye off-axis view (zoom TanRef / TanEye and
  shear in the view matrix, FMX.SRStereoViewport.pas ~2740), StereoModel
  still has a fixed 45 deg FOV, camera at the target distance, and a
  sideways shift. Offered as StereoCam58 (T kept to compare); not yet
  answered.
  Owner (21:51, StereoCam57 picked framebuffer 1, 64-point grid lit 7):
  "T/X fix it in ZeroCopy - basically the reverse of ScreenShots".
  Screenshots line up at shift sign -1, zero copy at +1 or toe-in.
  StereoCam58a: zero copy negates the shift (ShiftL/ShiftR := -ShiftFor);
  the reason is NOT known - the blit and CPU copy both move right for a
  positive shift, and the picture is not mirrored (toe-in is right).
  Suspect: FMX's framebuffer picture and MakeScreenshot's bitmap differ
  in some way the shift sees; to settle with the per-eye view.
  Owner (22:07): per-eye view, clean up and remove the unused / test
  code; render scale "Sharp" (asked: Gorilla3D takes no projection of
  ours and draws no run-time FOV change, so the off-axis cut is made in
  the copy and the picture rendered larger). StereoCam59:
  TPeardoxGorillaEyes rewritten - ViewScale reads the projection
  (ProjectToView of CameraPosition + Orientation.Rotate((1, 1, 1)) gives
  1 / tan of both half-angles, FProjX / FProjY) and the scale
  2 D / (SY * view height mm); EyeView puts the camera at the eye
  (dx, -dy, -dz) * scale in the roll pivot's frame, no turn, and the
  glass's corners through the projection give TPeardoxEyeView.Part
  (fractions, top-left origin, may pass 0..1); RenderEyeGPU ->
  TPeardoxGLInterop.CopyEye(eye, part in source pixels): resolve, then
  one GL_LINEAR blit of the part (clipped, the rest cleared black) into
  the eye texture, rows turned over; the screenshot route's CopyPart
  samples the part (nearest) into FBuffer. Render scale 2 (StereoCam60:
  the RenderScale setting):
  SizeViewForStereo makes the viewport 2 x the recommended view (3840 x
  2160); the eye textures stay the view size (Start takes source and
  view sizes). Removed: convergence (ecShift / ecToeIn), ShiftSign,
  SwapEyes, RenderBeforeShot, ZeroCopyFlip / FlipRows, Calibrate and the
  turn signs, ShiftFor, the decimation, the once-a-second zero-copy check
  (CheckNext, a pipeline stall), Survey, the GL probe unit
  StereoModelGLProbe (.dpr / .dproj too), FindPicture's pixel reads (it
  now picks FMX's multisampled RGBA8 framebuffer of the picture's size
  by name), keys S T X R Z F. Keys now: L [ ] C P Home Esc. Program only.
  Owner (22:31): works, "Oh yeah, that's nice"; 46-48 fps. StereoCam60:
  display settings PerEyeView (V), RenderScale (, .), HideCursor (M),
  Weave (W, TLenticularDisplay.Flat: lens off while weaving, one view from the
  eyes' midpoint for both). PACKAGE REBUILD (Lenticular). The
  SubmitViews PasDoc block, cut off from its declaration since
  StereoCam48, put back above it.
  Owner (22:59): "right click + drag still doesn't work". No drag reached
  FMX while Stereo was on: the bridge's child window covered the 3D
  window and took the mouse, and on the launcher the viewport had gone to
  FRenderForm under a cover with HitTest off. StereoCam61: the bridge's
  window subclassed (SetWindowSubclass; WM_NCHITTEST -> HTTRANSPARENT),
  logged "Mouse passed through N window(s)"; the cover takes the view's
  mouse handlers.
  Owner (23:10): drags arrive, but "No, it still moves" - the model slid
  across the 3D view during a right drag: the scale followed the target
  depth, so the eyes' cameras moved sideways with it. StereoCam62: the
  scale is set at ModelDepth (the Subject's centre along the line of
  sight), full-speed mode too. Owner (23:17): "that's good now".
- Later: TPeardoxGorillaEyes into lib as a component (with a design
  package); the true off-axis frustum (Gorilla3D's author: projection
  offset); LensMode (lens off over the controls); an OpenGL weaver path
  in the bridge (the runtime's OpenGL weaver) for zero copy.
- FastMM5 (submodule, owner 7 November 2026) is the memory manager on
  Windows, first in the `.dpr`; Debug builds report leaks, in full, to
  `StereoModel_MemoryManager_EventLog.txt` beside the executable.
- First Win64 run (owner, 7 November 2026): camera made, uvcube.glb loaded
  and framed (distance 4.84), headlight on; then an ACCESS VIOLATION ON
  EXIT, still there with StereoCam3. The FastMM5 leak dump of that run
  located it (see Lessons); StereoCam4 fixes it. The model also came up
  upside down: StereoCam4 turns it 180 degrees about X as Sprite3D does.
  Owner's re-test (push 5aea8b7): upright, horizontal drag reversed as
  asked (StereoCam6), no word of the exit crash since StereoCam4. Then:
  the wheel could take the camera inside the model. StereoCam7 adds
  `Subject` (a TGorillaModel): every move made through the component keeps
  the camera beyond the face nearest it (ray from the orbit centre through
  the model's box, plus twice the viewport's near plane). The box, not the
  mesh: a model that does not fill its box stops short.
- `tools/pasdoc.bat` (+ the two dark .css files), adapted from
  peardox/SRDelphiFMX: programs are `src\<program>.dpr`, the api run is
  `lib` without `*.Reg`. Not yet run.
- `MainMenu1` is on the form: once it has items, desktop Linux needs
  Sprite3D's `UseFmxMenuBar` swap (see Sprite3D's `CLAUDE.md`, Menus).

## Maybe later (owner, 7 November 2026)

Not to start unless the owner asks for one.

- **Dolly zoom**: DONE (8 November 2026) in TSpritelyProjection
  (FieldOfView with Dolly); the StereoCam15-17 attempt through the
  camera's FOV is history.
- **Convergence pull**, once the stereo pair exists: convergence (the
  depth that sits on the screen surface) and eye separation will be rig
  properties anyway; a pull is changing convergence smoothly during a
  view, bringing the model out of the screen or back behind it.
- **Focus pull**: advised AGAINST. It needs depth-of-field blur from the
  renderer (not checked whether Gorilla3D has one), and on a glasses-free
  display blur fights the depth cues and tires the viewer.

## Lessons learned

- **Gorilla3D teardown**: let the viewport free what is in it. The camera
  and light are owned by the viewport, as in Sprite3D and VirtualGamepad.
  The viewport sends its free notification BEFORE it frees the children
  and owned components it holds: FastMM5's dump of the leaked component
  showed FViewport nil, FLight nil, but FCamera still set, so the
  component's destructor later called into a dead camera. On the
  viewport's notice the component now lets go of the camera and light at
  once and never touches them again.
- **Palette greyed out**: a component class needs
  `[ComponentPlatformsAttribute(...)]` (here `SPRITELY_COMPONENT_PLATFORMS`,
  `pidAllPlatforms` as Gorilla3D's components use); without it the IDE
  takes it as Win32-only and greys it out while the project's active
  platform is Win64 (owner, 7 November 2026). Every new Spritely component
  carries the attribute.
- **Loading a model**: make the TGorillaModel (owned by the viewport,
  parented to it) and call its `LoadFromFile`; never use the class
  function `TGorillaModel.LoadNewModelFromFile`. In Gorilla3D 1.5.3 it
  never frees the FBX loader's parse tree, so every FBX load leaks it
  (TFBXNode, TFBXProperty, their TObjectLists and name dictionaries).
  Found by comparing with Sprite3D, which loads with `LoadFromFile` and
  does not leak (StereoCam63).
- **Reading a FastMM5 leak dump**: when an exception aborts shut-down,
  TApplication, TPlatformWin, the form and its registry entries all show
  as leaks; they are a symptom. The leaked object of our own class is the
  clue, and its memory dump gives its fields (64-bit TComponent: VMT at
  0, FOwner at 8, FFreeNotifies at $28, interface slots at $68 and $70,
  the class's own fields from $78).

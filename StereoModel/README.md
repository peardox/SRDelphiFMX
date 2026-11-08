# StereoModel, ProjectionTest and the Spritely and Lenticular components

StereoModel shows a 3D model in a Gorilla3D viewport through the Spritely
orbital camera, and weaves it for a glasses-free (lenticular,
autostereoscopic) display through the Lenticular components. Delphi 13,
FireMonkey, Gorilla3D 1.5.3. ProjectionTest is the test bed of the Spritely
projection component.

They came from peardox/StereoModel (8 November 2026), which stays where it
is; the work goes on here. Paths below are from the repository root.

## Layout

| Folder | What is in it |
|---|---|
| `StereoModel/` | The program: `StereoModel.dpr` / `.dproj`, the form in `ui/`, helpers in `common/` (`FmxLinuxMenu`, an unchanged copy from G3DGames/TSteamAPI: the main menu as an FMX menu bar on desktop Linux; `StereoModelLog`, `StereoModelEyes`, `StereoModelGLInterop`), and this file |
| `ProjectionTest/` | The projection test (see [The projection test](#the-projection-test)): `ProjectionTest.dpr` / `.dproj`, the form in `ui/`, the measuring and the test runner in `common/` |
| `lib/` | The components, shared with the demos' library: `Spritely.*` (camera and projection) and `Lenticular.Display*`, `Lenticular.Storage`, `Lenticular.Reg` and `LenticularBridge.Api` (glasses-free 3D), two sets that do not need each other |
| `lib/icons/` | Their palette icons (`.ico`, and the `.svg` sources in `svg/`) |
| `models/` | Test models: `uvcube.glb` (a cube with a UV test texture), `Mage.glb`, `DemoScene.glb` / `DemoSceneNoWall.glb` (LenticularDemoFMX's scene, written by `tools/gen_demo_scene.py`) and `DollyHallway.glb` (the dolly-zoom test, written by `tools/gen_dolly_hallway.py`); models that may not be published go in `models/licensed/`, which git ignores |
| `packages/` | The packages: `Spritely` and `dclSpritely`, `Lenticular` and `dclLenticular` (runtime and design time of each set) |
| `tools/` | `gen_packages.py`, `gen_icons.py`, `gen_icon_res.py`, `gen_demo_scene.py`, `gen_dolly_hallway.py` (the packages, the palette icons, the test models); the PasDoc reference is the repository's `pasdoc.bat` |
| `bridge/`, `dll/` | The C++ bridge to the display's weaver and its build, `dll/LenticularBridge.dll` (see the root `README.md`) |
| `FastMM5/` | FastMM5, the memory manager on Windows (submodule); Debug builds report leaks |

## The components

Two sets, each in a runtime package and a design-time package of its own,
each on its own page of the palette. Neither set uses the other, so either
may be installed without the other. They are FireMonkey components and
show only while an FMX form is designed.

| Set | Palette page | Types | Needs |
|---|---|---|---|
| Spritely | **Spritely** | `TSpritely...` | FireMonkey, Gorilla3D |
| Lenticular | **Lenticular** | `TLenticular...` | FireMonkey only |

## Spritely components

Registered on the **Spritely** page of the palette by
`lib/Spritely.Reg.pas` (design-time).

### TSpritelyOrbitalCamera (`lib/Spritely.OrbitalCamera.pas`)

An orbit camera for a `TGorillaViewport`. It is non-visual: drop it on the
form, or create it in code, and set **Viewport**. At run time it builds the
camera in that viewport and makes it the viewport's camera; at design time
it only keeps its settings.

| Property | |
|---|---|
| `Viewport` | The `TGorillaViewport` the camera goes in |
| `Headlight` | True (default): a point light rides on the camera, lighting whatever is in view. False: no light is made; add the scene's lights yourself |
| `Azimuth`, `PolarAngle`, `Roll` | The camera's angles in degrees round the orbit centre. `PolarAngle` is not limited, so the camera can go over the poles |
| `Distance` | From the orbit centre (default 10) |
| `FOV` | Field of view in degrees (default 45) |
| `ProjectionMode` | Perspective (default), orthographic or isometric |
| `OrthoHeight`, `OrthoWidth` | The view's size in orthographic and isometric mode; 0 leaves Gorilla3D's own height, and a width of 0 follows the height |
| `Locked` | While True nothing moves or turns the camera |
| `Subject` | A model the camera may not go inside: the wheel, `Distance`, orbits and angles stop at the face nearest the camera (its bounding box, plus a gap of twice the viewport's near plane) |
| `Projection` | A `TSpritelyProjection` that draws this camera's view: it takes `Distance` as its target plane and moves the camera for the dolly zoom, and the fits and `ProjectToView` follow the lens, shift, rise and parallel views it draws (the camera's `ProjectionMode` must stay perspective) |

Methods: `FitToBounds` frames a subject for the current angles, and
`FitToBoundsMax` for every angle (orbit freely afterwards). Both work as
Sprite3D frames a model: the subject is centred in the view and the target
(the orbit centre) is put on its turning axis, the up axis through its
centre of rotation, so the camera turns about the subject's own axis.
`FitToBounds` makes the subject as large as it goes for the current angles;
`FitToBoundsMax` frames the ball round it, centred on that axis halfway up,
so no angle takes any of it out of view. Each sets the target and
`Distance`, or the orthographic size, from the angles, `FOV` and projection
as they are, and takes the subject as:

- a model: `FitToBounds(Model)`, turning about its `RotationCenter`;
- a group of models: `FitToBounds([Model1, Model2])`, the box holding them
  all, turning about its middle;
- a box in the scene's space: `FitToBounds(Box)`, turning about its middle;
- a box in an object's own space, such as part of a model:
  `FitToBounds(Box, Model)`, turning about the model's `RotationCenter`.

A box has no centre of rotation of its own, so the box and group forms
also take one: `FitToBounds(Box, Center)`, `FitToBounds(Box, Model, Center)`
(in the model's coordinates), `FitToBounds([Model1, Model2], Center)`.
All take an optional margin. Also: `SetTargetDepth` (moves the target
nearer or deeper along the line of sight without moving the camera: the
picture is unchanged, the point the camera orbits, and `Distance`, change;
for the stereo pair this is the depth that will sit on the display's
surface), `Orbit`, `Zoom` (works in every projection), `LookAt`,
`MoveCenterTo`, and `MinimumDistance` (how near the camera may come along
its present line without entering `Subject`).

It is a component of its own rather than the camera itself because the
camera hangs under three pivots, one per angle, that are not stored: as a
camera placed on a form it would never be written to the `.fmx`.

The camera came from Sprite3D's `Sprite3DCamera` unit
(<https://github.com/peardox/Sprite3D>), renamed so both can be used in one
program.

### TSpritelyProjection (`lib/Spritely.Projection.pas`)

A projection for any FireMonkey 3D viewport (`TViewport3D`, `TGorillaViewport`): FMX and Gorilla3D offer only perspective (with the camera's own angle of view) and orthographic. FMX keeps the projection it draws with private (`TContext3D.FProjectionMatrix`); the component finds it inside the first frame, by its value, and writes its own over it in every frame, through an empty 3D object first in the viewport. It is made from FMX's own each time, so resizes and a new angle of view are followed, and FMX's goes back when nothing is changed or `Active` is False. Found and measured with the ProjectionTest program (below).

| Property | |
|---|---|
| `Viewport` | The viewport to draw for |
| `Kind` | `pjPerspective` (default), `pjOrthographic`, `pjCavalier` (depth at full length, 45 degrees), `pjCabinet` (half length, 63.4 degrees), `pjMilitary` (full length straight down the picture: with the camera straight above, height is drawn straight up and the plan keeps its shape), `pjPlanOblique` (with the camera straight above and the plan square to the picture, height drawn up and to the left at 45 degrees, full length, as many hand-drawn top-down game maps are), `pjTrueIsometric` (orthographic from azimuth 45, inclination 35.264: the three axes equally foreshortened, 120 degrees apart), `pjDimetric` (2:1 dimetric, the "isometric" of pixel-art games: orthographic from azimuth 45, inclination 30, ground squares drawn twice as wide as high), `pjTrimetric` (orthographic from azimuth 35, inclination 45, the look of many pre-rendered role-playing maps) or `pjOblique` (`ObliqueAngle`, `ObliqueScale`) |
| `CameraPreset` | True (default): choosing a `Kind` with preset angles turns the `Focus` to them (`PresetAngles`: cavalier and cabinet level at a face, military straight above with the plan turned 45 degrees, plan oblique straight above, and the three orthographic presets above); `ApplyCameraPreset` does it again |
| `FieldOfView` | The lens: vertical field of view in degrees; 0 (default) keeps the camera's own |
| `Dolly` | True (default): a new `FieldOfView` also moves the `Focus` so the target plane keeps its size - the dolly zoom |
| `ShiftX`, `ShiftY` | Lens shift and rise: the picture moved across the lens, in normalised device units (the picture is 2 wide and 2 high), the camera standing still |
| `ObliqueAngle`, `ObliqueScale` | `pjOblique`'s direction (degrees, 0 right, 90 up) and length for depth |
| `Focus` | The camera that gives the target plane's distance and moves for the dolly zoom; set by `TSpritelyOrbitalCamera.Projection` |
| `Distance` | The target plane's distance without a `Focus` |
| `ManageCulling` | True (default): a `TGorillaViewport`'s `FrustumCulling` is off while the projection is changed, as Gorilla3D culls by its own camera's frustum |
| `Active` | False: FMX's own projection |

The parallel views are made from the perspective at the target plane, so switching keeps the target's size and true shape, and the depth range (and depth buffer) is kept. `TSpritelyProjectionAccess`, in the same unit, is the tool underneath: it finds the projection and camera matrices in memory and changes them, for tests and other uses.

## Lenticular components

The components for eye-tracked lenticular (glasses-free 3D) displays,
after this repository's stereo renderer (`Lenticular.StereoViewport`), registered on the **Lenticular** page of the
palette by `lib/Lenticular.Reg.pas` (design-time). The display runtime is
Windows 64-bit only, but the units compile everywhere, so the package and
the programs using it stay cross-platform; elsewhere nothing is offered. A
program needs `LenticularBridge.dll` (this repository's C++ bridge to the
display's weaver, built into `dll/`) beside its executable: StereoModel's Win64 post-build
step copies it from `dll/`. They need neither
Gorilla3D nor the Spritely components.

| Unit | |
|---|---|
| `Lenticular.Display` | `TLenticularDisplay`: `Installed` (Win64, the bridge beside the executable and the display runtime present; where not, `Start` does nothing and raises no event, so a program can hide everything to do with glasses-free 3D), `Start` (checks for the display service and the display on a background thread, so the window never freezes, then starts the display with the bridge's window over `Control`), `Stop`. While running it logs the runtime's version, the display, where `Control` lies on it in millimetres, the runtime's events and the tracked eyes (`OnLog`, `OnEyes`). `OnProblem` says why it could not start (no service, no display, no bridge). It weaves nothing itself: a renderer sets `Weaving` (the bridge's window over `Control`, the lens on) and hands it each side-by-side frame with `SubmitViews`, or each eye's texture with `SubmitEyeTextures`; `UpdateEyes` reads the eyes just before a frame |
| `Lenticular.Display.Settings` | `TLenticularDisplaySettings`: the viewer's and display's settings, as LenticularDemoFMX keeps them (use glasses-free 3D, eye separation, look-around, latency, lens mode, full screen, frame cap, per-eye view, render scale, hiding the pointer, weaving), in `Lenticular.json` in the `Peardox` folder of the user's application data (`%APPDATA%\Peardox` on Windows), shared by every Peardox program |
| `LenticularBridge.Api` | The bridge's imports, the same unit the demos use, declared on Windows only so it compiles everywhere |
| `Lenticular.Storage` | `AppDataFolder` and `TLenticularStorage` (published properties to and from a JSON file with the RTL's `System.JSON`, no third-party library), after Sprite3D's `Sprite3DStorage` |

### Palette icons

`python3 tools/gen_icons.py` draws `lib/icons/<Class>.ico` for both sets
(needs Pillow and `rsvg-convert`); `python3 tools/gen_icon_res.py` packages
them into `lib/Spritely.Reg.dcr` and `lib/Lenticular.Reg.dcr` (standard
library only). Never edit a `.dcr` by hand.

### Packages and installing

Four packages, like G3DGames/TSteamAPI's:

| Package | What it is |
|---|---|
| `packages/Spritely` | Runtime: the `Spritely.*` units in `lib`. It requires `rtl`, `fmx` and Gorilla3D's runtime package (`Gorilla3D_Delphi_13_2_0_Florence`). Win32, Win64, macOS (x64, ARM64), Linux64, Android (32 and 64-bit), iOS device and simulator; not WinARM64EC, for which Gorilla3D is not installed |
| `packages/dclSpritely` | Design time: `lib/Spritely.Reg.pas`, which puts the Spritely components on the **Spritely** palette page with their icons. Win32 (the 32-bit IDE) and Win64 |
| `packages/Lenticular` | Runtime: the `Lenticular.*` units in `lib`. It requires only `rtl` and `fmx`: not Gorilla3D, not Spritely. Same platforms as Spritely |
| `packages/dclLenticular` | Design time: `lib/Lenticular.Reg.pas`, the **Lenticular** palette page. Win32 and Win64 |

A runtime package's DCUs go to Delphi's Dcp folder,
`$(BDSCOMMONDIR)\Dcp\<platform>` (`\Dcp` alone for Win32), beside its
`.dcp`, which is on the IDE's default Library path, so **a program that
uses one of these components needs no search path**.

To install, in `Lenticular.groupproj` (or only the set you want):

1. Build **Spritely** and **Lenticular** for every platform you compile
   programs for, and always for **Win32**, which the 32-bit IDE's design
   packages need. Debug and Release write to the same Dcp folder: the last
   build wins.
2. Build **dclSpritely** and **dclLenticular** (Win32) and **Install** each
   (right-click in the Projects window). The Spritely and Lenticular pages
   appear on the palette.
3. Build `StereoModel`. It lists no `lib` unit and has no path to `lib`:
   `Spritely.OrbitalCamera` and `Lenticular.Display` come from the Dcp
   folder.

After a change in `lib`, rebuild the package holding it (Spritely or
Lenticular) for each platform used before building a program; after a
change to a `*.Reg.pas` unit or the icons, rebuild and reinstall its design
package too. A program failing with *F2613 Unit 'Spritely.OrbitalCamera'
not found* has not got Spritely built for the platform it is compiling for
(new projects start on Win32).

`python3 tools/gen_packages.py` writes the packages. A new component unit
in `lib` must be added to its set's list, or the script stops; it also
stops if a unit is put in the other set's package or one set's package is
made to require the other's. The `.dpk` files are always rewritten from it;
a `.dproj` only when missing, as the IDE's re-saved copy then counts
(`--force` overwrites it).

## The reference (PasDoc, optional)

`tools\pasdoc.bat` (see the root `README.md`) writes the Spritely set's
reference to `docs\html\spritely` (and `docs\chm\spritely`); the Lenticular
units are in `docs\html\api` with the rest of `lib`, and StereoModel and
ProjectionTest each get their own (their `.dpr`, forms and helpers; the
components come from the packages, so they are not repeated there).

## Running the test

Build and run `StereoModel/StereoModel.dproj` (after installing the packages,
above). The orbital camera, `SpritelyOrbitalCamera1`, is on the form with
its headlight; once the form is showing it loads a model, centres it,
turns it 180 degrees about X so it stands upright (glTF's up is +Y, FMX's
-Y; Sprite3D does the same) and frames it. It looks for the model in a
`models` folder beside the program, in the bundle's `Resources` on macOS,
in the documents folder on Android and iOS, then in the folders above the
program, which finds the repository's `models` folder when run from the
IDE on Windows. The status line at the bottom says which file it loaded, or
every folder it looked in.

File, Open (desktop) loads another model in place of the one shown. Its
filter lists every format Gorilla3D has a loader for in the program, read
from Gorilla3D's own registry: glTF / GLB, OBJ, FBX, Collada, STL, PLY, USD,
Babylon and Gorilla3D's G3D (one loader unit each, in `StereoModelMain`'s
uses). Not included: the Mayo CAD loaders and SketchUp's, which need
external libraries, and Sketchfab's, which loads from the web.

Mouse: left-drag orbits; right-drag up or down moves the target deeper or
nearer along the line of sight, the camera staying put (orbit afterwards
to see the new centre). The target's depth is the plane that will lie on the
display's glass, so the status line also gives the model centre's Z against
it, along the line of sight: below 0 it is in front of the glass (out of the
screen: drag up, past the model's own depth), above 0 behind it; while the
3D display runs, in millimetres too. The wheel zooms (stopping at the
model's nearest face, never inside it). Each notch moves the camera along
its line of sight by a share of its distance from the model, not from the
target, so the steps stay even wherever the target's depth has been put;
with the target in front of the model the camera stops just short of it. A
click on its own does nothing. A window resize refits the view, putting
the target back on the model.

Everything the status line shows is also written, with the time, to
`StereoModel.log` beside the executable (the documents folder on macOS and
mobile), flushed line by line; a run that ended normally finishes with
`Log closed normally`. The first line says whether a debugger was attached
(timings under one are far slower). The previous run's log is kept as
`StereoModel.prev.log`.

At start the program loads `models/DemoSceneNoWall.glb` and shows it
from the owner's test view: azimuth 52, inclination 75, roll 0, the camera
42 from the target (`TEST_VIEW_*` in `StereoModelMain`); Home goes back to
it. `models/DemoScene.glb` is LenticularDemoFMX's scene as a model, for
File, Open: the 11 x 11 grid of spheres, coloured by depth (red nearest,
white on the middle row, blue furthest, the centre one green), the two
columns of three cubes, which spin a turn every 8 s (the model's first
animation, started when it loads, if Gorilla3D plays glTF node animations),
and the back wall. `DemoSceneNoWall.glb` leaves the wall out, so the framed
view is not made big enough to hold it. `python3 tools/gen_demo_scene.py`
writes both (standard library only).

The window's title always shows the view as numbers: the camera's azimuth,
inclination (0 level, +90 above looking down) and roll in degrees, the target
depth and the model centre's Z against the glass (below 0: in front of it),
and each drag writes them to the status line and the log when it ends
(`View: ...`), to note down for a test scene.

A model with animations plays its first once loaded; the box left of
**Stereo** lists them (as Gorilla3D sorts them, as Sprite3D does) and plays
the one chosen, or none; it is hidden for a model without animations.

Glasses-free 3D: where the display runtime is installed (a Win64 build on
a computer with the runtime, `LenticularBridge.dll` beside the executable)
the **Stereo** button is shown. The display starts once the model has
loaded, on a hidden borderless 3D window, with the lens off; the button is
enabled once it has. Pressed, it shows the 3D window full screen on the 3D
display, on top, and weaves the view there (the lens comes on); if the main
window is on the 3D display it hides until Stereo is off, on any other
monitor it stays (the button shows pressed). **Esc**, the button again, or
Alt+F4 on the 3D window turn Stereo off: the 3D window hides, the lens goes
off, and the display stays running so the next time is quick. While Stereo
is on, the viewport is rendered at the render scale (2 by default) times
the size the display weaves each eye at (its recommended view, 1920 x 1080
on the owner's display, so 3840 x 2160), off screen, and the drags and
wheel work on the 3D window (through the bridge's window, which passes the
mouse on) and on the launcher's cover as on the viewport; a right drag
moves the target, the depth that sits on the glass, nearer or further with
the camera still, so the model comes out of the screen or goes behind it.

Once Stereo is on, the view is woven (`StereoModel/common/StereoModelEyes.pas`,
`TPeardoxGorillaEyes`), each eye from where it really is, as the stereo renderer's
demo does it (the per-eye off-axis view): the target's depth is the glass,
the view's rectangle on the display fills the camera's field of view there,
which sets how many scene units a millimetre is, and each frame the orbital
camera's Gorilla3D camera is put once per eye at the tracked eye's place in
those units, looking straight ahead, and rendered (`RenderManual`). From
there the glass is off to one side and smaller than the picture: that part
of the picture is cut out and scaled to the woven view, which is exactly
what the eye sees through the glass (LenticularDemoFMX does it in FMX's
view matrix; Gorilla3D 1.5.3 takes no matrix of ours, so it is done in the
copy, and the picture is rendered twice the size so the part stays sharp).
Where it can (zero copy: the bridge has `lnb_GetDevice` and OpenGL has
`WGL_NV_DX_interop2`) the part is copied on the GPU straight into a
Direct3D 11 texture on the bridge's device, the right way up, and woven
from there: no screenshot, no copy through the CPU, no upload (about 100
fps on the owner's laptop against 40 with screenshots). Elsewhere each eye
is captured (`MakeScreenshot`) and the part copied through the CPU. The
camera is put back after each frame. Frames are drawn whenever the program
is idle.

Keys (once per press, however long the key is held; on Windows through a
thread keyboard hook, as LenticularDemoFMX does, and only while the main
window or the 3D window is active):

| Key | |
|---|---|
| **L** | Steps the weaver's latency (0, the runtime's own, then 1 to 4 frames: how far ahead the weaver predicts the eyes) |
| **[** and **]** | Make the eye separation 5 mm smaller or larger |
| **C** | Turns the bridge's frame cap on and off (on: it waits for the 3D display's vertical blank after each frame, which cost frames here; off, the default, it does not; vsync stays on, so no tearing) |
| **V** | Turns the per-eye view off and on (off: each eye is drawn from the camera's own distance in the direction the real eye is, so the whole picture is woven at the view's size: full speed, about 100 fps against 46-48 on the owner's laptop, the depth exaggerated as the viewer moves back) |
| **,** and **.** | Make the render scale 0.25 smaller or larger (1 to 2; used only with the per-eye view: 1 is fast and softer, 2 sharp) |
| **M** | Turns hiding the mouse pointer over the 3D display off and on (hidden by default) |
| **W** | Turns weaving off and on (off: one flat view from between the tracked eyes for both, with the lens off, so a screen recording catches it and the view still follows the head) |
| **Home** | Puts the view back |
| **P** | Writes a snapshot to the log (one block between `=== SNAPSHOT ===` lines, in the same terms as LenticularDemoFMX writes with its own P: the display, the view on it, the eyes, the settings, the camera, the world-to-mm scale, each eye's camera and part of the picture, the frame rate), for comparing a view that looks right there with this one |

L, [ ], C, V, `,` `.`, M and W are saved in the display settings
(`LatencyFrames`, `EyeSeparationMM`, `FrameCap`, `PerEyeView`,
`RenderScale`, `HideCursor`, `Weave`).

The log gives, once a second, the frame rate, the time each stage takes,
the view size and each eye's part of the picture, and the bridge's own
lines: the runtime's version, the display, where the view lies on it, the
runtime's events and the eyes. The lens is on exactly while Stereo is; the
log has the runtime's LensOn and LensOff. The target's depth stops at the
viewport's far plane: further out, single precision moves the camera.
Where the display runtime is not installed the button is hidden.
`LenticularBridge.dll` must be beside the executable (the Win64 build
copies it from `dll`).

## The projection test

`ProjectionTest/ProjectionTest.dproj`, in `Lenticular.groupproj` (it needs the **Spritely** package only), asks whether the projection FireMonkey draws a 3D scene with can be reached and changed from outside FMX. FMX keeps the projection matrix private and builds it from the camera's angle of view, and Gorilla3D draws with what FMX gives it, so a camera of ours cannot supply its own. The test tries it on a lens shift and rise (the picture moved across the lens, the camera standing still), which needs an off-axis projection.

Run it: it loads `models/DemoSceneNoWall.glb` (or `uvcube.glb`); **Run test** runs the test (it no longer runs by itself at start: `AUTO_TEST` in the form brings that back). The log is in the panel on the right and in `ProjectionTest.log` beside the executable (the last run's kept as `ProjectionTest.prev.log`).

What it does:

1. **Survey.** An empty 3D object, the hook (`TSpritelyRenderHook`), is put first in the viewport, so FMX calls it inside each frame once the camera and projection are set and before any model is drawn. In one frame it reads the context's public `CurrentProjectionMatrix`, `CurrentCameraMatrix` and `CurrentCameraInvMatrix`, then looks through the memory of the context, the viewport, the cameras and the objects they hold for copies of them (or anything shaped like a perspective projection). That needs no RTTI, so it finds private fields whether or not FMX and Gorilla3D were compiled with field RTTI; RTTI only names them where it can. Each find is logged with its object, offset and name.
2. **Every way of moving the picture**, each written once, before each frame, or inside the frame by the hook: the context's public `SetRenderToMatrix` (a matrix after the projection), the public `SetCameraMatrix` with a shear in the view matrix (LenticularDemoFMX's way), and each projection and camera matrix found in memory.
3. **Measured, not judged by eye.** For each, a reference frame, two frames with the change, and one after putting everything back, all read with `MakeScreenshot`. The move is measured from the pictures (`ProjectionTestMeasure`): a shift of 0.1 of the half-width should move everything 96 px right on a 1920 px picture and change nothing else. Each line says `SHIFTS AS EXPECTED`, `NO CHANGE`, `SHIFTS THE WRONG WAY`, `MOVES, BUT NOT BY THE EXPECTED AMOUNT` or `CHANGES, BUT NOT A PLAIN SHIFT`; a way that shifts is then tried for rise.
4. **The result** at the end lists what worked.

Live, the component `TSpritelyProjection` draws the view (made in code here, as a new component is first; it is the orbit camera's `Projection`). The controls are along the top. The first row has **Run test**, the **model** box (every `.glb`, `.gltf`, `.fbx` and `.obj` in the models folder; choosing one loads it), **Open...** for any other, **Fit** (frames the model for the present angles in the projection actually drawn: lens, shift and parallel views included), the **Shift** and **Rise** sliders, **Centre**, **Active** and **Free Movement** (ticked, the camera is no longer kept outside the model's box, so it can go inside a model such as the hallway). The second row chooses the **projection** (the component turns the camera to the kind's preset angles, if it has them - cavalier and cabinet level at a face, military straight above with the plan turned 45 degrees, plan oblique straight above with the plan square to the picture, true isometric, 2:1 dimetric and trimetric from their angles; orbit from there as you like), the free oblique's **Angle** and **Depth**, the **Lens**, and **Dolly (keep size)**: with it, a lens change also moves the camera so the target plane keeps its size while the perspective flattens or deepens - the dolly zoom. Left-drag orbits and the wheel zooms throughout. While something is changed, the log says every 2 s what is drawn and in how many frames.

The view starts, and **Front** puts it back, level at the front: azimuth, inclination and roll 0, the target on the model's centre, framed for every angle.

To see the dolly zoom, choose **DollyHallway.glb** in the model box: the UV cube on a long chequered floor between two rows of pillars, a wall at the far end and the near end open, so the camera can come in (written by `tools/gen_dolly_hallway.py`, standard library only, from `uvcube.glb`). From the front view, wheel in on the cube, then drag Lens from 45 down to 10 and up to 120 with Dolly ticked: the cube keeps its size while the pillars, the floor and the far wall come forward (narrow lens) or stretch away (wide). Untick Dolly for a plain zoom.

## Trademarks

See the Trademarks notice at the end of the root `README.md`.

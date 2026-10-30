# SimulatedReality: handover notes

This shows FMX `TViewport3D` scenes on a LeiaSR eye-tracked lenticular display from Delphi. Read `README.md` first, especially "Notes for Claude", then this file.

## Where to pick up (30 October 2026, 02:15, end of session)

### What works (owner, on the hardware)

- 3D in a normal (maximised) window: correct off-axis projection (`corner`
  (1, 1)), look-around ("the model balls + cube all move properly"), no
  drift. The FMX view-matrix finding (23:40 below) was the fix.
- Opens on the SR display; moves there if started elsewhere.
- Lens off over the controls (SR's lens hint works while weaving), wait for
  the eyes before 3D (flat until then), off-display detection.
- F11 and Esc via the thread keyboard hook; full screen without the taskbar,
  held at the SR display rectangle against FMX's re-sizing.
- Stereo test images (`media/`) in a window.

### The one open fault: full screen goes wrong after a few seconds

Symptom: full screen is right for a second or so, then each eye gets one
half of the *left* view stretched to full width (green sphere and cube at
both edges in a screen grab). Coming out of full screen makes it right
again. A 3441 x 1440 or 3840 x 1700 window on the same display never breaks.

Ruled out, each by a test on the hardware:

| Idea | Test | Result |
|---|---|---|
| FMX re-creating the window, weaver made mid-resize | own borderless full screen, no re-creation, no SR restart | still breaks |
| lens switching | lens kept on in full screen; 00:50 run had one lens event | still breaks |
| views exactly the display's resolution | one row trimmed (3840 x 2159) | still breaks |
| window at x = -1 (FMX rounding) | window held at exactly (0, 0) 3840 x 2160 | still breaks |
| Windows treating it as full screen | "Plain full screen": one row short, not marked | still breaks |
| flip-model independent flip | bitblt `DISCARD` swap chain, as Leia's samples | still breaks |
| integrated GPU | Windows Graphics setting: High performance | still breaks, same fps |
| low frame rate | `beer.jpg` in full screen at 170-300 fps; Skip rendering | still breaks |

So it is not FMX's rendering, the frame rate, the projection or the window
manager as far as we can see: an image woven with no 3D rendering at all
still breaks. What remains is how the bridge's weaving behaves when its
window covers the display, against what Leia's own samples do.

### Next steps, in order

1. **Run Leia's DX11 sample from the 1.36.2 SDK full screen on this
   machine** (`examples/directx11_weaving`, CMake, VS 2022; starts full
   screen, F11 toggles, default mode is a stereo image). If it also breaks
   after a few seconds, the fault is the runtime/driver/display, not ours:
   report to Leia. If it holds, close the gap step by step:
2. **A new test project** (the owner's rule: any further demo is a new
   project in the group, e.g. `SRFullScreenTest/` with `ui/`, sharing `lib/`
   and `dll/`). Plain, no FMX 3D: a borderless full-screen window, the
   bridge, a stereo image. Then vary one thing at a time:
   - the weaver created on the top-level window, not the bridge's child
     window (the samples weave into a swap chain on the top-level window);
   - views at the recommended 1920 x 1080 (bridge: mip 1 of the
     side-by-side texture), as the samples;
   - the adapter (bridge already picks it the samples' way, see below).
3. Only then port the fix into `TSRStereoRenderer`.

### Built but not yet run

- The bridge with the adapter choice (commit `4ce0f0f`, DLL built 02:13 against
  SDK 1.36.2): it logs every adapter and the monitors it drives
  (`adapter n: name, vendor, MB dedicated; monitors: ...`), puts its device on
  the one with the most dedicated memory, as Leia's 1.36 sample does
  (`D3D11 device on ...`), and after finding the SR display says which adapter
  drives it and whether that is the bridge's (`SR display is driven by adapter
  ...`). The first build failed (C3861, `LogSRDisplayAdapter` used before its
  declaration); fixed with a forward declaration. The first run's log will
  show the owner's GPU layout; check it before anything else.
- The owner's laptop: an RTX 5090 Mobile drives the SR display; there is also
  an integrated GPU, which cannot drive it. SRDemo.exe is set to High
  performance in Windows Graphics settings (GDEM's `GPUPreferences.pas` /
  `GDEMGpuPreference` can set this from the program). That made no
  difference to the fault or the frame rate.

### Diagnostics left in on purpose

`FullScreenPlain` / "Plain full screen (test)", `FlipModel`, the frame
trace after each viewport resize, `Full screen held` lines. Remove the plain
test once the fault is understood.

Notes: the 02:02 log's `ipd 42.4` is the Depth slider (0.67 x 63 mm), not a
tracking fault. The 1.36.2 SDK headers are compatible; the bridge builds
against either SDK.

## Earlier (30 October 2026, 01:15)

**Display placement confirmed** (owner, 23:40): SRDemo always opens on the SR
display.

**Lens switching.** The lens covers the whole panel, so the Delphi controls
look soft while it is on. Unticking 3D makes the panel 2D (the owner), and
the owner understands all these devices have switchable lenses. A second
monitor for the controls is a no-go: most users have one screen.

Delivered: `TSRStereoRenderer.LensMode` (`lensOffOverControls` default,
`lensAlwaysOn`, `lensAlwaysOff`) and `LensSwitchDelay` (250 ms). Each frame
it checks the pointer: off the SR display, lens on; over the viewport with
our form the window under it, lens on; anything else on the SR display, lens
off. No change while a mouse button is held. It calls `srb_SetLens`, which
the bridge already had (SR's switchable-lens hint), so the bridge is
unchanged. While the lens is off both eyes are drawn from the midpoint, so
the woven image is a clean 2D picture; stereo test images use the left half
for both. The log says `Lens ON/OFF (reason)` and tags the summary
`LENS-OFF`. Not yet known: whether the hint switches the lens while our
weaver is running, and how fast the panel switches. SRDemo has a Lens combo
in the diagnostics row, saved as `LensMode` (an integer) in settings.

**Start-up drift** (owner, 23:50: "a small amount of startup drift - I guess
it's trying to find my eyes"; suggested finding the eyes first, then
switching). Delivered: `SettleTime` (300 ms). Until the tracked eyes are
real (not nominal, not IPD-rebuilt) and the midpoint has stayed within 20 mm
for that long, the lens is off and the view is drawn flat from a fixed
viewer at (window centre, 650 mm). Losing the eyes for over a second goes
back to waiting. Log: `Eyes found and steady ...: 3D on`, `Eyes lost ...`.

**F11 "messes the screen up"** (23:47-00:07). Screenshot: the two eyes'
images about 1800 px apart and squashed; it "almost gets there" (the flat
picture while waiting for the eyes looked right), then goes wrong when 3D
comes on. The log (23:58:57) had every number right: form 2560 x 1440
logical = 3840 x 2160 physical at the owner's 150% scaling, viewport the
whole 596.7 x 335.7 mm panel, corner (1, 1), zoom about 2.1. But FMX's
`FullScreen` re-created the form window, so the renderer stopped and
restarted SR, and the new weaver was created 0.2 s later, very likely while
FMX was still sizing the new window (the owner's clue: 150% scaling, so a
logical size used as pixels for a moment). Unconfirmed; the owner was asked
to untick and re-tick 3D in full screen to test it.

Delivered: `TSRStereoRenderer.FullScreen`. It makes the existing window
borderless (Raymond Chen's `WS_OVERLAPPEDWINDOW` / `SetWindowPlacement`
method) at the SR display's rectangle in physical pixels, so nothing is
re-created and SR never restarts. SRDemo uses it instead of the form's
`FullScreen`. If this does not fix it, the weaver does not follow window
size changes at all, and the bridge must re-create it (or re-set its input)
when the child window's size changes; check whether resizing the normal
window breaks the weave too.

Owner, 00:21: "better but not actually full screen" - the taskbar stayed.
Fixed: `WS_MAXIMIZE` is cleared with the frame styles (a maximised window is
held to the work area), and `ITaskbarList2.MarkFullscreenWindow` tells the
shell. The log line gives the wanted and actual rectangles and whether the
window is still maximised. No DirectX calls are needed: this is a borderless
full-screen window, and a flip-model swap chain covering the monitor already
gets the independent-flip path; DXGI exclusive full screen is the inferior
mode. (Later: that independent-flip path is now the prime suspect for the
broken full screen; see the swap chain note above.)

**Full screen works** (owner, 00:29). **But** (00:35): start, F11 (fine),
back to normal, F11 again: broken exactly as in the 23:55 screenshot. No
window re-creation and no SR restart now, so it is not the weaver being
created mid-resize. Reading that screenshot again: it matches both eyes being
taken from the left view only, each half of it stretched to the full width
(the left half for one eye, the right half for the other: green sphere and
cube at both edges, the rest in order), as if the weaver took the view width
as a quarter of the texture instead of a half. Candidate trigger: the lens
going off and on again (the first broken run also broke when the lens came
on after waiting for the eyes; normal to full screen the first time had no
lens switch). Asked the owner to repeat with Lens "Always on", and to send
the log: the renderer now logs each viewport size change and traces 3
frames after it, and the bridge logs every `setInputViewTexture`.

If it is the lens or the resize, the likely fix is the SDK's own pattern: a
fixed-size view texture (the SDK samples use the recommended 1920 x 1080 and
never resize it; the weaver scales to the window). That is the render-scale
work below, with the projection's aspect corrected for the window.

**The GPU (01:44).** The owner's machine is a laptop: an RTX 5090 Mobile
drives the SR display, beside an integrated GPU that cannot drive it. On
such hybrid laptops Windows starts programs on the integrated GPU unless
told otherwise, so FMX's context and the bridge's device (both on the
default adapter) very likely ran on the integrated GPU, with every frame
crossing to the 5090: normal in a window (DWM copies it), a different path
full screen. It also fits 35 fps at 4K. Plain full screen (01:44): fine for
a moment, then broken, the picture nearer the left.

First test, no rebuild: Windows Settings > System > Display > Graphics,
SRDemo.exe, High performance. Delivered as well (**bridge rebuild**): the
bridge logs every adapter with the monitors it drives, picks the one with
the most dedicated memory as Leia's 1.36 sample does, logs `D3D11 device on
...`, and after finding the SR display logs which adapter drives it and
whether it is the bridge's. FMX cannot be told an adapter, so the Windows
preference is the real fix; GDEM's `GDEMGpuPreference` (from Sprite3D)
writes it (HKCU\Software\Microsoft\DirectX\UserGpuPreferences), so SRDemo
could set itself to high performance, taking effect at the next start.

**01:35 run, bitblt bridge rebuilt: still broken in full screen.** The log
confirms the bitblt swap chain. Windowed now runs at 70-79 fps (was 60 with
the flip model). So independent flip was not the cause either; bitblt is
kept anyway because it matches Leia's samples. Untested so far: the "Plain
full screen (test)" checkbox (bottom row uncovered, Windows not told). Still
to try, in order: that test; the weaver created on the form's top-level
window while full screen (bridge); views at the recommended 1920 x 1080
(bridge: generate mips on the side-by-side texture and give the weaver mip 1;
the renderer cannot render into a separate context, because
`TControl3D.RenderInternal` draws into the viewport's own context); choosing
the adapter as the 1.36 sample does.

**SDK 1.36.2 (owner found it, 01:25) and the swap chain.** The 1.36.2
headers differ from 1.34.5 almost only in comments, plus a new
`SR::IDisplayManager` / `IDisplay` (`TryGetDisplayManagerInstance`, lazy
bound), which could later replace `DisplayMirror`. The installed runtime is
already 1.36.4, so the SDK alone changes nothing at run time; the bridge
builds against either (the `sr_stub` still applies). What the 1.36 DX11
sample shows that matters: its swap chain is the **bitblt model**,
`DXGI_SWAP_EFFECT_DISCARD`, one sRGB buffer (1.34's too), and it picks the
adapter with the most dedicated memory. Ours was the flip model. A flip-model
swap chain covering the display can be promoted by Windows, a moment after
it appears, to independent flip or a hardware overlay that bypasses DWM
composition, which matches "fine for a few seconds, then wrong, with nothing
in our log", only in full screen. Delivered (**bridge rebuild needed**): the
bridge now uses the bitblt model by default; `srb_SetPresentModel(1)` /
`TSRStereoRenderer.FlipModel` brings back the flip model for comparison
(called only when needed, so the new Delphi code still runs with an older
bridge). Not yet copied from the sample: choosing the adapter.

**01:18 run: the hold works, the fault stays.** The window sat at exactly
(0, 0) 3840 x 2160 with no further moves, and it still broke after a few
seconds, with nothing logged at that moment. So the x = -1 offset below was
not the cause either (the hold is kept: it is still right). Something outside
our code reacts some seconds after the window becomes full screen. Every
broken run either covered the display exactly or was marked full screen
with `ITaskbarList2` (the 01:07 run was one row short but marked). Leia's
samples are full screen too, but their weaver is created on that full-screen
window; ours is on the bridge's child window. Theory: SR polls for a
full-screen window and treats one that is not its weaver's window
differently. Test delivered (no bridge rebuild): `FullScreenPlain`
(SRDemo: "Plain full screen (test)" in the diagnostics row) leaves the
bottom row uncovered and does not mark the window. If plain full screen
holds, the fix is the samples' way: the weaver on the top-level window while
full screen (bridge change: re-create the weaver on the form's HWND; in full
screen the child covers the form's client area exactly, so the position is
the same).

**The full-screen fault: the window was one pixel onto the next monitor
(01:07 log and video).** Every attempt to put the borderless window at the
SR display's (0, 0) 3840 x 2160 ended at (-1, 0) or (-1, 1), 3841 wide: FMX
re-sizes the window from its rounded logical bounds (150% scaling) after we
place it. In that run the per-frame check put it back 207 times in 6 s and
FMX moved it again each time. x = -1 puts one column on the monitor to the
left. The video: full screen correct for about 3 s, then the broken picture
(each eye one half of the left view, stretched), with nothing in the log at
that moment; SR presumably re-reads the window position and gets a window
spanning two monitors. The SDK samples (plain Win32, no FMX) sit exactly at
the monitor rectangle and work.

Delivered: `HoldWindowProc`, a comctl32 subclass (`SetWindowSubclass`,
declared locally) on the form's window while full screen. On
`WM_WINDOWPOSCHANGING` it rewrites any move or size to `FFullScreenRect`
before it happens, counts the attempts, and the frame logs them (`Full
screen held: n attempt(s) ... the last to (x, y) w x h`); no logging inside
the window procedure. The one-row gap (`FullScreenGap`) and the one-row view
trim are removed: both were wrong guesses.

**Checked against the SDK samples afterwards (should have been first).**
`examples/directx11_weaving` (and dx12, gl) start full screen by default,
F11 toggles, and full screen is exactly Raymond Chen's method on the whole
monitor (`MONITOR_DEFAULTTOPRIMARY`, no gap). So exact coverage works for
Leia, which makes the gap theory doubtful. What the samples do differently:
1. The weaver is created on the top-level window, which owns the swap chain.
   Ours is created on the bridge's child window.
2. The views are a fixed `getRecommendedViewsTextureWidth/Height`
   (1920 x 1080 here), never resized; the weaver scales to the window.
   Ours are the viewport's size (3840 x 2160 in full screen).
If the gap does not fix it, the next steps are, in order: fixed 1920 x 1080
views (renderer only, also restores 60 fps), then the weaver on the
top-level window (bridge rebuild).

The owner asked whether display sizes are measured at the start (Sprite3D's
DisplayData does): the SR display's rectangle is read from SR when it
starts, and full screen goes straight to it; the 00:50 run had the window at
its final size before SR started, so measuring sooner would not have helped.

**00:39 log (owner started full screen on his 3440 x 1440 widescreen, at
100% scaling).** The renderer moved the window to the SR display at
3840 x 2160 before the first frame was submitted, so the weaver only ever
had 3840 x 2160 views: the fault is not the view texture changing size. It
was broken from the moment the lens came on (after waiting for the eyes)
until 00:39:41.9, when Windows shrank the window to 3441 x 1440 (the
cross-scaling move; nothing of ours did it), after which it worked at 60 fps.

What all three broken cases share: the lens went off and back on while the
window covered the whole 3840 x 2160 display. The one good full-screen run
had no lens switch while full screen; switching in a normal window has never
broken. Unproven, but cheap to act on. Delivered:
- `LensWanted` keeps the lens on in `FullScreen` (nothing but the viewport is
  showing), and full screen turns the lens on *before* resizing the window.
- Waiting for the eyes no longer switches the lens: it only draws flat.
- Each frame in full screen re-applies the SR display rectangle if Windows
  has changed it.
If it still breaks, the next step is in the bridge (re-set the weaver's
input, or re-create the weaver, after a lens switch or a resize), or the
SDK's fixed-size views.

**Off the SR display** (owner asked; GDEM does the same): the renderer
checks each frame whether the viewport's centre is on the SR display
(`ViewportOnSRDisplay`); if not, the lens is off and the view flat, logged on
each change.

Full screen also runs at 32-41 fps instead of 60: 3840 x 2160 per eye is
66 MB read back per frame. Offered: a render scale (SR recommends 1920 x
1080 per eye). That needs a separate, smaller context, since the viewport's
own context is sized to the viewport.

Also noted: the light-blue back wall moves with the head because it is 8
units (about 13 cm) behind the glass; that is correct parallax.

## Earlier (23:45)

**The view-matrix fix works (owner, 23:32).** The scene fills the viewport,
`corner` is (1.0000, 1.0000) for both eyes, the zoom is about 2.57 (right for
823 mm from a 264 mm-high window), and "as I move my head around the model
balls + cube all move properly". The drift is solved. A screen grab shows both
eyes blended: the cube on the glass single, the spheres doubled by their
distance from it. One 237 ms frame at 23:31:04; watch whether that repeats.

**F11 still did nothing** with `OnKeyDown` on the form. Now delivered: a
thread keyboard hook (`WH_KEYBOARD`, in `MainForm.pas`, with the few user32
calls declared locally so `Winapi.Windows` doesn't hide FMX names) sees F11
and Esc before FMX or the bridge's child window, swallows them, and queues
the toggle. The log says which window had the keyboard
(`keyboard focus <class> ($handle)`) and the form's size and state after each
change. Still untested: SR display placement on the owner's several monitors.

## Earlier (23:40)

**The real cause of the drift, found from FMX's own source** (the owner sent
`FMX.Types3D.pas`, `FMX.Controls3D.pas`, `FMX.Viewport3D.pas` and
`FMX.Context.DX11.pas` from Delphi 13; they are not to be copied into the
repository):

- `TContext3D.GetCurrentModelViewProjectionMatrix` is
  `CurrentMatrix * CurrentCameraMatrix * CurrentProjectionMatrix`, and that is
  what reaches the shaders (`ApplyMaterial`). So **the matrix given to
  `SetCameraMatrix` is the view matrix itself**. `TCamera.CameraMatrix` is one
  (`CreateLookAtDirRH`). The renderer had assumed the opposite: it passed a
  camera placement and expected FMX to invert it.
- `GetProjectionMatrix` is cached and only rebuilt when
  `FRecalcProjectionMatrix` is set, on context create or resize.
  `SetCameraAngleOfView` and `SetRenderToMatrix` do not set it, so neither has
  any effect between frames.
- My per-frame "corner" check used `CurrentCameraInvMatrix`, the same wrong
  assumption, so it reported (1, 1) while the GPU drew something else.
- What the owner saw (OBS recording and a screenshot, 23:13): the scene about
  a sixth of its proper size, both eyes' copies identical but shifted, and
  the whole picture sliding with the head. That is the wrong matrix exactly.

**Fixed, delivered:** `RenderEye` builds the eye's view as
`RefView * Translation(-eye) * OffAxis`, where `OffAxis` is the shear plus a
zoom of TanRef / TanEye, and passes that to `SetCameraMatrix`. FMX's own
projection is used as it is. The corner check now uses the shaders' formula
(world * `CurrentCameraMatrix` * `CurrentProjectionMatrix`). The axis signs
are measured in view space through the projection. Lighting is unaffected:
materials get the model matrix, and the eye position (the inverse's origin)
is unchanged by the shear and zoom.

Also delivered: full screen (F11) hides the toolbars and log, F11 or Esc
leaves it, and both keys are logged. The owner had found F11 did not return.

Next: the owner runs it. The scene should now fill the viewport as in 2D, the
two eyes' copies should differ by depth (the cube on the glass nearly single,
the wall and spheres doubled oppositely), and the picture should stay still,
apart from look-around parallax.

## Earlier (23:00)

**22:37 run:** images "look better" letterboxed, but "the drift still happens"; it isn't yet clear whether the images drift too or only the scene. The owner noticed a lot of on-screen movement as the head moves, which is the look-around (motion parallax). There was one 2.9 s stall at 22:37:53, with the weaver's latency at 150 ms for that second; cause not known (possibly the owner doing something else). The first run opened on the wrong monitor (the owner has several). The owner will try a screen recording, though OBS doesn't understand SR displays.

Delivered (the bridge changed, so it must be rebuilt):

- **SR display placement.** The bridge finds the SR display's desktop rectangle: through `SR::Display::getLocation` via `DisplayMirror` (a class mirroring `SR::Display`'s virtual functions, since `WorldObject` has none), checked against the C API, called under SEH. If that fails it matches monitors by resolution and EDID size (`GetDeviceCaps` HORZSIZE/VERTSIZE). New export `srb_GetDisplayRect`. `srb_GetWindowRectMM` now measures against the SR display, not the monitor the window is on. The renderer moves the form there at start (`PlaceFormOnSRDisplay`).
- **LookAround** (renderer property, demo checkbox): off draws from a fixed viewer 650 mm in front of the viewport centre. If the drift goes away with it off, the drift was the look-around.
- **Settings** (`lib/SRSettings.pas`, Neon, `%APPDATA%\SRDelphiFMX\settings.json`, GDEMSettings' pattern). The demo has an eye separation number box (default 63, 0 = tracked) and a latency combo, and saves on every change.
- `CREDITS.md`, written GDEM-style.

The owner usually wants multi-platform code, but this project is Windows only by design (Leia's Android version is left out: no device).

## Earlier (22:40)

**The weaving is proven (22:20 run).** Media images woven as given, with no 3D
rendering: Avatar01/02 and beer.jpg are "extremely good stereo" (the owner).
fry.jpg (made with Immersity's AI tool) has some depth; keep it as a test.
dice.jpg (a Blender attempt) is poor and the owner may delete it. So the
bridge, the weaver and the window placement are right, and any fault left in
the 3D scene is in the rendering or the scene itself.

- **The drift** is very likely motion parallax and not a fault. The demo
  scene goes about 13 cm behind the glass (the back wall) and 10 cm in front
  (the nearest sphere) at 83 cm viewing distance; that is a lot for a 27-inch
  panel, so things move a long way with the head. There is also one jump at
  start-up, from the nominal viewer to the tracked one (the tracker reports
  L = R = (0, 100, 600) until it locks on). Offered, not yet chosen: a
  stereo-only mode (fixed head position, real eye separation), smoothing, and
  a shallower demo scene.
- **63 mm fixed separation "definitely helps"**, so it is now on by default in
  SRDemo. The tracker reads the owner at 67-75 mm, against 63 mm set in the
  Samsung hub app.
- **The areas outside the viewport look blurred:** the lens covers the whole
  panel. That is hardware; noted in the README.
- **Delivered:** letterboxing for images (they were stretched to the
  viewport), and log rotation into `oldlogs\` (20 kept per name; FastMM's log
  too). Owner's request: clean or rotate the logs between runs.
- **FastMM5 full debug mode is ON now** (the post-build fix worked), and the
  run had no corruption.

## Earlier (22:30)

**Second log (22:04): the projection is now right, but the drift is still
there.** `corner` was (1.0000, 1.0000) for both eyes in every frame, and the
zoom ran 1.88 to 2.64. The eyes were steady: about L(-185, -38, 825) and
R(-115, -33, 835). The tracker's eye separation read 61-74 mm, against 63 mm
set in the owner's Samsung hub app. So the remaining fault is either in the
weaving (the bridge, the SR weaver, window placement) or in something about
the 3D content.

Delivered to tell which:

- **Show: (media image).** SRDemo can weave one of the side-by-side images
  from `media/` exactly as given, with no 3D rendering
  (`TSRStereoRenderer.ShowStereoImage`). If an image also drifts, the fault is
  in the weaving. If images are steady and only the scene drifts, it is in the
  rendering.
- **Fixed 63 mm eye separation** (`EyeSeparationMM`), to rule out the
  tracker's wandering separation.
- **Post-build copy fixed.** The IDE had joined the two copies with `&&`
  after `if ... else (...)`, so the FastMM DLL copy only ran when the bridge
  copy failed. Each copy is now a parenthesised `(copy ... || echo warning)`.

Waiting on: the owner's answers to whether a still head drifts, whether the
media images drift, and what exactly "splits and drifts" looks like.

## Earlier (22:15)

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
- The bridge owns a child window over the viewport (`WM_NCHITTEST` returns `HTTRANSPARENT`, so the mouse reaches FMX), plus its own D3D11 device and swap chain (bitblt model since 30 October, as Leia's samples; the flip model is optional). Views are uploaded through typeless textures with sRGB views, and the render target view on the back buffer is sRGB too, so the weaver does no sRGB conversion in its shader.
- `TSRStereoRenderer` renders the viewport's 3D children into the viewport's own `TContext3D` (`RenderInternal`), once per eye. It sets the lights itself from `IViewport3D.Lights`, and reads each eye back with `CopyToBits` into one side-by-side buffer.
- The off-axis projection is built into the view matrix passed to `SetCameraMatrix`: `RefView * Translation(-eye) * OffAxis` (a shear plus a zoom). FMX's projection is left as it is. The axis signs are measured in view space every frame, and the viewport corner is checked against NDC (1, 1) with the shaders' own formula.
- The eye frame is millimetres from the display centre, x right, y up, z towards the viewer. The window rectangle in mm comes from the child window's screen rectangle, the SR display's desktop rectangle (`FindSRDisplayRect`; the window's monitor only if that is unknown), and the SR display's physical size.

## Lessons learned

- `MonitorFromWindow`, `GetMonitorInfo`, `TMonitorInfo` and `MONITOR_DEFAULTTONEAREST` are in `Winapi.MultiMon`, not `Winapi.Windows` (GDEM's `GDEMFetch/ui/GDEMDisplays.pas`, cut down from Sprite3D's `DisplayData`, uses them the same way).
- The IDE rewrites a multi-line post-build event into one line joined with `&&`. An `if exist ... (...) else (...)` followed by `&&` makes the next command part of the `else` branch. Write each step as a parenthesised `(command || echo warning)` instead.

- FMX 3D (`FMX.Types3D`): `SetCameraMatrix` takes the **view** matrix (world to view; `TCamera.CameraMatrix` is a `CreateLookAtDirRH` one). The shaders get `Model * CurrentCameraMatrix * Projection`, and `CurrentCameraInvMatrix` is only used for picking. The projection is cached and rebuilt only on context create or resize, so `SetCameraAngleOfView` and `SetRenderToMatrix` do nothing mid-frame. Put any field of view or off-axis change into the view matrix.
- A self-check built on the same wrong assumption as the code proves nothing. Check against the formula the GPU uses, or against the picture: the owner's OBS recording found what the log could not.
- The SR weaver reports both eyes at one point (0, 100, 600) before the tracker locks on.
- `SR::Display`'s base `WorldObject` has no virtual functions, so its vtable can be mirrored (`DisplayMirror` in the bridge) to call `getLocation` without including `display.h`, which includes OpenCV.

- The SDK's `sr/management/srcontext.h` includes OpenCV through the network headers. Don't include it in the bridge; the stub in `bridge/sr_stub` stands in.
- In Delphi 13, `TContext3D.Width` and `Height` are `Single`.
- `dcc32` in the build output means a 32-bit build, which can't load the 64-bit bridge. `SRBridgeLastError` now says so.
- Delphi 11 and earlier leave floating-point exceptions unmasked; driver and SR code expect them masked, so every bridge export masks them (`SRB_ENTRY`).

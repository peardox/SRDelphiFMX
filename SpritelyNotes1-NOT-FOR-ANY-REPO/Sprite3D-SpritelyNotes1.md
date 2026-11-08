# Spritely in Sprite3D: notes for the Sprite3D session

Written 8 November 2026 (19:45) in the session on peardox/SRDelphiFMX, for
a session on peardox/Sprite3D. Read this, then Sprite3D's own `CLAUDE.md`.
This file goes in no repository: read it, then record what is still true
in Sprite3D's `CLAUDE.md`.

The owner wants to see whether Sprite3D can use the Spritely components.
Nothing has been decided about how. Ask the owner before changing what
Sprite3D does (see "Questions for the owner").

## What Spritely is

Spritely is a set of camera components for FireMonkey and Gorilla3D 1.5.3,
by the owner (Peardox is the owner, not a product). It is one of two
independent sets in peardox/SRDelphiFMX; the other, Lenticular, is for
glasses-free 3D displays. **Neither set uses the other**, so Spritely can
be installed alone and needs nothing of Lenticular.

| Where (in SRDelphiFMX) | What |
|---|---|
| `lib/Spritely.OrbitalCamera.pas` | `TSpritelyOrbitalCamera` (the component), `TSpritelyOrbitalGorillaCamera` (the camera it makes), `TSpritelyOrbitalFraming`, `TSpritelyQuat`, `TSpritelyLookAtMode`, `SPRITELY_ORBITAL_...` |
| `lib/Spritely.Projection.pas` | `TSpritelyProjection` (the component), `TSpritelyProjectionAccess` (the matrix tool underneath), `TSpritelyRenderHook`, `ISpritelyProjectionFocus`, `TSpritelyViewShape`, `SPRITELY_PROJECTION_...` |
| `lib/Spritely.Reg.pas` + `.dcr` | Registers both on the palette page **Spritely** (green icons) |
| `packages/Spritely.dpk` | Runtime package: requires `rtl`, `fmx`, `Gorilla3D_Delphi_13_2_0_Florence`; all platforms Gorilla3D has (not WinARM64EC) |
| `packages/dclSpritely.dpk` | Design package: Win32 (the IDE) and Win64 |
| `StereoModel/`, `ProjectionTest/` | The two programs that use it; ProjectionTest is the projection's test bed |
| `StereoModel/README.md` | The full description of both components, the packages and how to install them |
| `StereoModel/CLAUDE.md` | Their rules and history (the Rules section applies to Spritely) |

The runtime package writes its DCUs to `$(BDSCOMMONDIR)\Dcp\<platform>`
(`\Dcp` for Win32), beside its `.dcp`, which is on the IDE's default
library path. **A program that uses Spritely needs no search path and
lists no Spritely unit in its `.dpr`**: it names `Spritely.OrbitalCamera`
or `Spritely.Projection` in a uses clause, and Delphi finds the DCU. The
owner has the four packages built and the design packages installed from
SRDelphiFMX (19:43). A program fails with *F2613 Unit
'Spritely.OrbitalCamera' not found* when Spritely is not built for the
platform it compiles for.

## Where it came from: Sprite3D's own camera

`TSpritelyOrbitalGorillaCamera` IS Sprite3D's `TSprite3DCamera` (unit
`Sprite3DCamera`), copied and renamed so the two can be linked into one
program side by side:

| Sprite3D | Spritely |
|---|---|
| `TSprite3DCamera` | `TSpritelyOrbitalGorillaCamera` |
| `TSprite3DFraming` | `TSpritelyOrbitalFraming` |
| `TQuat` | `TSpritelyQuat` |
| `TLookAtMode` | `TSpritelyLookAtMode` |

Since the copy it has grown (all checked on the owner's hardware in
StereoModel): a non-visual wrapper component `TSpritelyOrbitalCamera`
(published `Viewport`, `Headlight`, `Azimuth`, `PolarAngle`, `Roll`,
`Distance`, `FOV`, `Locked`, `Subject`, `ProjectionMode`, `OrthoHeight`,
`OrthoWidth`, `Projection`); fits for a model, an array of models, a box
in the scene's space or in an object's space, each with an optional
rotation centre (`FitToBounds` frames the corners for the present angles,
as Sprite3D's FitCameraToSweep; `FitToBoundsMax` is safe at every angle);
`Subject` keeps the camera outside a model's box; `SetTargetDepth` slides
the target along the line of sight with the camera fixed; `Orbit`,
`Zoom`, `LookAt`, `MoveCenterTo`, `MinimumDistance`; and the link to
`TSpritelyProjection`, whose shift, lens and parallel views the fits and
`ProjectToView` follow. Compare Sprite3D's present `Sprite3DCamera` with
`Spritely.OrbitalCamera.pas` before deciding anything: Sprite3D may have
changed since the copy, and anything it has that Spritely lacks is worth
listing for the owner.

## TSpritelyProjection in short

FMX keeps the projection matrix private and builds it from the camera's
angle of view, and Gorilla3D draws with what FMX gives it, so a camera
cannot supply its own. `TSpritelyProjection` finds FMX's private
`TContext3D.FProjectionMatrix` by VALUE in the drawing context (never by a
fixed offset) from an empty 3D object placed first in the viewport
(`TSpritelyRenderHook`, run inside each frame), and writes its own
projection there every frame, made from FMX's own, so resizes and lens
changes are followed. FMX's projection goes back when `Active` is False or
nothing is changed. It gives:

- perspective with any lens (`FieldOfView`, 0 = the camera's own) and the
  dolly zoom (`Dolly`: the `Focus` camera moves so the target plane keeps
  its size);
- lens shift and rise (`ShiftX`, `ShiftY`, in normalised device units);
- parallel views at the target plane: `pjOrthographic`, the obliques
  `pjCavalier`, `pjCabinet`, `pjMilitary`, `pjPlanOblique`, `pjOblique`
  (`ObliqueAngle`, `ObliqueScale`), and orthographic presets
  `pjTrueIsometric` (45 / 35.264), `pjDimetric` (2:1, 45 / 30),
  `pjTrimetric` (35 / 45); `CameraPreset` (default True) turns the
  `Focus` camera to a kind's angles;
- `ManageCulling` (default True): Gorilla3D's `FrustumCulling` off while
  the projection is changed, as Gorilla3D culls by its own camera.

To use both: drop a `TSpritelyOrbitalCamera` and a `TSpritelyProjection`,
set the camera's `Viewport` and its `Projection` to the projection (that
sets the projection's `Focus` and `Viewport`), then set `Kind` and the
rest. ProjectionTest's form (`ProjectionTest/ui/ProjectionTestMain.pas`
in SRDelphiFMX) shows every property in use.

## Rules that come with Spritely

- **Spritely lives in SRDelphiFMX.** Sprite3D uses the installed package;
  it does not copy or change the units. If Sprite3D needs something in
  Spritely, write it up for a session on SRDelphiFMX (notes, or whole
  files in a zip for that repository) and say so to the owner; that
  delivery then carries the line
  `====> REBUILD RUNTIME PACKAGE SPRITELY (ALL PLATFORMS) AND REINSTALL DCLSPRITELY <====`.
- **Spritely knows nothing of Sprite3D** (nor of Lenticular, nor of any
  program): Sprite3D may require Spritely, never the reverse. A unit that
  needs both goes in Sprite3D or in a third package that requires both.
- **No trademarks** in names, UI, logs, comments or docs; the projection
  kinds are named for the projection, never for a game that used it
  (owner, 8 November 2026).
- Spritely's code style is Sprite3D's: `//**` PasDoc on everything
  (private members too), ASCII sources, two-space indent, cross-platform
  (Windows, macOS, Linux 64-bit, Android, iOS) with `{$IF}` alternatives.
- Every Spritely component carries
  `[ComponentPlatformsAttribute(SPRITELY_COMPONENT_PLATFORMS)]`, or the
  palette greys it out for Win64.

## Gorilla3D lessons from StereoModel (worth checking in Sprite3D too)

- Load a model by making it (`TGorillaModel.Create(Viewport)`) and calling
  its `LoadFromFile`, as Sprite3D does. Never use the class function
  `TGorillaModel.LoadNewModelFromFile`: in 1.5.3 it never frees the FBX
  loader's parse tree.
- Teardown: the viewport sends its free notification BEFORE it frees its
  children, so a component must let go of the camera and light on that
  notice and never touch them again (the cause of an exit access
  violation in StereoModel).
- `MakeScreenshot` is ONE FRAME LATE: it shows the `RenderManual` before
  the last. Render twice before a screenshot that must show a change.
- FMX's perspective is D3D-style (depth 0..1) and NDC y is up; a written
  projection stays until FMX makes it again (resize, lens change);
  `SetRenderToMatrix` does nothing.

## Questions for the owner

1. **Replace or keep?** Should Sprite3D use `TSpritelyOrbitalGorillaCamera`
   / `TSpritelyOrbitalCamera` in place of its own `TSprite3DCamera`, or
   keep its own and use only `TSpritelyProjection`? Both can be linked
   together, as every name differs.
2. **Package or source?** Sprite3D as a program built against the
   installed Spritely package (no paths, the usual way here), or something
   else Sprite3D needs (for example a Sprite3D package of its own that
   requires Spritely)?
3. **What first?** For example the projection kinds as a view choice in
   Sprite3D's UI, the dolly zoom, or shift and rise.
4. **The merge the other way.** StereoModel's notes say its animation
   choice and similar "will eventually be merged into Sprite3D" (owner,
   7 November 2026): is this that step, or later?

## Open items in Spritely itself

From `StereoModel/CLAUDE.md`, not yet settled: a Windows chime on
ProjectionTest's exit (no dialog, cause unknown); "Depth 0" in
ProjectionTest's Front view taken as the target on the model's centre (not
confirmed); `SetTargetDepth` changes a parallel view's size, by design
(its size is the target plane's); the wheel scales `Distance`, so it never
passes the target (a fly / move-forward control would need asking for).

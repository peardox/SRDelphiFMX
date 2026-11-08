# Notes for the SRDelphiFMX session: the bridge renamed for Lenticular

Written 8 November 2026 by the StereoModel session that renamed StereoModel's
components (StereoModel zip Rename1, branch `refactor`). The owner runs this
session on peardox/SRDelphiFMX straight after, on its own branch. StereoModel
has ALREADY been changed to expect everything in Part 1, and is written as if
this work were done. Part 2 is the owner's call. Part 3 is the order of work
and checks.

## Why

The owner (Peardox) is renaming his components to avoid trademark trouble:

- The display maker's company name is a trademark and is to be **removed from
  every place**: identifiers, file names, UI text, log lines, comments, docs,
  build scripts. The one exception is a short Trademarks notice in the README
  (wording below).
- "SR" / "Simulated Reality" is the current owner's marketing term (Immersity,
  which owns the display maker). It is not to be used as **our** name for
  anything either: say "the display", "the display runtime", "the 3D
  display", "glasses-free 3D", "lenticular" (the science the displays use).
- Other companies' marks (Samsung and so on) likewise: never in our names.
- In StereoModel the glasses-free 3D components are now the **Lenticular**
  set (`TLenticularDisplay`, units `Lenticular.*`, packages `Lenticular` /
  `dclLenticular`, palette page Lenticular), and the camera components the
  **Spritely** set. The bridge becomes **LenticularBridge**.

The bridge is the boundary: inside its C++ the vendor's SDK headers, its C++
classes and its runtime DLL file names must stay, because that is what the
bridge is built against and loads. Keep them **inside the bridge's code
only**, never in its exported names, its header's public names, its log or
error text, or anything the Delphi side shows. (StereoModel no longer names
the runtime's DLLs at all; that is why `lnb_RuntimeInstalled` is new, below.)

Trademarks notice for the README (owner's wording, "These components"):

> These components are not affiliated with or endorsed by any display
> manufacturer. Leia, Samsung and other names are trademarks of their
> respective owners.

## Part 1 - REQUIRED: the contract StereoModel now uses

StereoModel's `lib/Lenticular.Display.Api.pas` (attached to these notes as a
copy, for reference) declares exactly what follows. Anything that does not
match makes StereoModel fail to load an import (delayed: it raises when
called) or show glasses-free 3D as not installed.

### 1.1 The DLL

| Was | Now |
|---|---|
| `dll/SRBridge.dll` | `dll/LenticularBridge.dll` |
| CMake `project(SRBridge CXX)`, `add_library(SRBridge ...)` | `project(LenticularBridge CXX)`, `add_library(LenticularBridge ...)` (so the output is `LenticularBridge.dll`) |
| `SRBRIDGE_EXPORTS` | `LENTICULARBRIDGE_EXPORTS` (CMake defines `<TARGET>_EXPORTS` itself) |
| post-build "Copying SRBridge.dll to dll/" | "Copying LenticularBridge.dll to dll/" |
| `bridge/SRBridge.cpp`, `bridge/SRBridge.h` | `bridge/LenticularBridge.cpp`, `bridge/LenticularBridge.h` |
| the child window class `"SRBridgeChildWindow"` | `"LenticularBridgeChildWindow"` |

`dll/.gitignore` excludes `*.dll`: add the new DLL with `git add -f
dll/LenticularBridge.dll` and `git rm dll/SRBridge.dll`. StereoModel's
post-build step copies `SRDelphiFMX\dll\LenticularBridge.dll` beside its
executable (the submodule path `SRDelphiFMX` stays as it is unless the owner
renames the repository - see Part 2).

### 1.2 The exports: every `srb_` becomes `lnb_`

Same signatures, same calling convention (cdecl), same behaviour, same
return codes:

`lnb_Initialize`, `lnb_Finalize`, `lnb_IsInitialized`, `lnb_IsWeaving`,
`lnb_SetBounds`, `lnb_SetVisible`, `lnb_GetDisplayInfo`, `lnb_GetDisplayRect`,
`lnb_GetWindowRectMM`, `lnb_GetEyePositions`, `lnb_SubmitViews`,
`lnb_SetExternalDevice`, `lnb_Probe`, `lnb_SetProgramDevice`,
`lnb_GetGpuCheck`, `lnb_CopyEyeTexture`, `lnb_PresentViews`,
`lnb_SetFrameCap`, `lnb_SetVSync`, `lnb_SetLatencyInFrames`, `lnb_SetLens`,
`lnb_GetLensState`, `lnb_GetDevice`, `lnb_PollSystemEvent`, `lnb_GetStats`,
`lnb_SetLogCallback`, `lnb_GetLastError`, `lnb_GetPlatformVersion`,
`lnb_SetDllDirectory`, and the demo scene's `lnb_SceneParamsSize` and
`lnb_RenderScene` (StereoModel does not import these two; rename them anyway).

No `srb_` aliases: the DLL has a new name, so nothing old can load it.

### 1.3 NEW export: `lnb_RuntimeInstalled`

```c
/* Whether the display runtime is installed: every runtime DLL the bridge
 * needs can be found where the bridge would load it from (the normal DLL
 * search, plus a folder given to lnb_SetDllDirectory). Checked with
 * LoadLibraryExW(name, NULL, LOAD_LIBRARY_AS_DATAFILE) and FreeLibrary
 * straight after, so no code runs and no dependency is needed: quick and
 * safe on any computer, before lnb_Initialize, from any thread that is not
 * inside another bridge call. Says nothing about whether the display
 * service is running or a display is plugged in (lnb_Probe does that).
 * Returns 1 if all were found, 0 if any was not. */
LNB_API int32_t lnb_RuntimeInstalled(void);
```

The DLLs to look for are the three the bridge's runtime loader needs (the
"core", "displays" and "directx" ones it loads with `LoadLibraryW` today,
around line 308 of `SRBridge.cpp`); the optional version-string DLL is not
required. Share the list with the loader (one array) so the two never
disagree. This replaces the
check StereoModel did itself with the DLL names written out
(`SRRuntimeInstalled` in the old `SRBridge.Api.pas`): the names now live only
in the bridge. StereoModel calls it only when `LenticularBridgeHasExport(
'lnb_RuntimeInstalled')` says it is there, so a missing export means "not
installed" - it must be in the first LenticularBridge.dll.

### 1.4 The header's public names: `SRB_` becomes `LNB_`

| Was | Now |
|---|---|
| `SRB_API` | `LNB_API` |
| `SRB_OK`, `SRB_E_NOT_INITIALIZED`, `SRB_E_NO_SERVICE`, `SRB_E_NO_DISPLAY`, `SRB_E_D3D`, `SRB_E_WEAVER`, `SRB_E_ARGS`, `SRB_E_WINDOW` | `LNB_OK`, `LNB_E_NOT_INITIALIZED`, ... (same values) |
| `SRB_E_SR_DLL_MISSING` (-2) | `LNB_E_RUNTIME_MISSING` (-2) |
| `SRB_S_2D_FALLBACK`, `SRB_S_OCCLUDED`, `SRB_FMT_BGRA8`, `SRB_FMT_RGBA8` | `LNB_S_2D_FALLBACK`, `LNB_S_OCCLUDED`, `LNB_FMT_BGRA8`, `LNB_FMT_RGBA8` |
| `SRB_DisplayInfo`, `SRB_SystemEvent`, `SRB_Stats`, `SRB_SceneParams`, `SRB_SceneInfo`, `SRB_GpuCheck` | `LNB_DisplayInfo`, `LNB_SystemEvent`, `LNB_Stats`, `LNB_SceneParams`, `LNB_SceneInfo`, `LNB_GpuCheck` |
| `SRB_GpuCheck` fields `srDisplayAdapter`, `programOnSRAdapter`, `bridgeOnSRAdapter`, `srRefreshHz` | `displayAdapter`, `programOnDisplayAdapter`, `bridgeOnDisplayAdapter`, `displayRefreshHz` |

**Layouts and values do not change**: `LNB_Stats` 96 bytes, `LNB_GpuCheck`
416 bytes, `LNB_SystemEvent` as before, the event type numbers as before
(lens on 14, lens off 15; StereoModel names them `LNB_EVENT_LENS_ON` /
`LNB_EVENT_LENS_OFF` on its side).

### 1.5 The Delphi import unit

`lib/SRBridge.Api.pas` becomes `lib/LenticularBridge.Api.pas`, unit
`LenticularBridge.Api`, with the C names above and these Delphi names, the
same as StereoModel's `Lenticular.Display.Api` (StereoModel's unit says it
follows this one; keep the two in step):

| Was | Now |
|---|---|
| `SRBridgeDll` (`'SRBridge.dll'`) | `LenticularBridgeDll` (`'LenticularBridge.dll'`) |
| `SRBridgeAvailable` | `LenticularBridgeAvailable` |
| `SRBridgeHasExport` | `LenticularBridgeHasExport` |
| `SRBridgeLastError` | `LenticularBridgeLastError` |
| `SRRuntimeInstalled` (if this repo has it) | `LenticularRuntimeInstalled`, now `HasExport('lnb_RuntimeInstalled') and (lnb_RuntimeInstalled = 1)` - no DLL names in Pascal |
| `TSRB...` / `PSRB...` records | `TLNB...` / `PLNB...` (`TLNBDisplayInfo`, `TLNBSystemEvent`, `TLNBStats`, `TLNBGpuCheck`, `TLNBLogCallback`, `TLNBRect`, `TLNBVec3`, and the scene records) |
| an event-name function, if any | StereoModel's `LenticularEventTypeName` uses `'RuntimeUnavailable'` / `'RuntimeRestored'` for values 2 and 3 (the rest unchanged) |

Every `.dpr` / `.dproj` that lists `SRBridge.Api` lists `LenticularBridge.Api`
instead, and every post-build step copies `LenticularBridge.dll`.

### 1.6 The bridge's own text

StereoModel logs every line the bridge sends (`lnb_SetLogCallback`) and shows
`lnb_GetLastError` to the user, so these must follow the trademark rule too.
Found in today's `SRBridge.cpp` (line numbers at 2c4a2f1):

- 314-315 the "runtime DLLs not found" error names the DLLs and the
  maker's platform: make it "The display runtime's DLLs were not found:
  install the display runtime, or call lnb_SetDllDirectory()." (no DLL names
  in the message; log the names at debug level only if really needed - better
  not at all).
- 320 "Missing SR export: " -> "Missing runtime export: ".
- 355, 478 messages naming the SDK's weaver function -> "the runtime has no
  DX11 weaver (runtime too old?)", "creating the weaver failed".
- 375 "SR system event %llu: %s" -> "runtime event %llu: %s".
- 387, 394, 396, 424-432, 486-487, 1014 "SR context" -> "runtime context";
  425 names the SDK's lens-preference function -> "this runtime has no lens
  preference for a new context, so its own applies until the hint".
- 432 "is the SR service running?" -> "is the display service running?".
- 445, 605, 608, 733, 766, 777, 823-825, 991, 1070-1072 "SR display" ->
  "3D display".
- 587-589 messages naming the SDK's display-location call -> "the runtime's
  display location".
- 1512 "one SR window per process" -> "one 3D window per process".
- The header comment block (lines 1-14) and every comment: the maker's name,
  "SR" and "Simulated Reality" as our words -> as above. SDK identifiers in
  CODE (`SR::...`, the include paths, the mangled export name, the DLL names
  in the loader) stay.

StereoModel's log after the change should contain no maker name and no
"SR" (it checks nothing automatically; the owner will read it).

## Part 2 - RECOMMENDED: the rest of the repository (owner's call)

Not needed by StereoModel; ask the owner which he wants, as each is a bigger
change for this repository's own users:

1. **Build instructions and CMake.** `LEIASR_SDKROOT` (variable, cache entry,
   environment variable, messages) -> `LENTICULAR_SDKROOT`. The README must
   still tell a builder which SDK to download: describe it without the mark
   ("the display vendor's weaver SDK for Windows, the one whose
   `include/sr/weaver/dx11weaver.h` this checks for") or ask the owner for
   wording. The include path itself (`sr/weaver/...`) is the vendor's and
   stays.
2. **The Delphi library** (`lib/`): units and classes with "SR" as our name -
   `FMX.SRStereoViewport` (+ `.Reg`), `FMX.SRMovieRenderer`, `SRSettings`,
   `SRSettingsDialog`, `SRStartProblem`, `SRStereoFrame`, `SRStereoImage`,
   `SRDiagLog`, `SRGpuPreference`, `SRAudioOutput`, `SRVideoDecoder`, the
   classes in them (`TSRStereoRenderer`, `TSRSettings`, ...) and the palette
   page. A natural mapping is `Lenticular.*` / `TLenticular...`, but they must
   not collide with StereoModel's `Lenticular` package (unit names
   `Lenticular.Display`, `Lenticular.Display.Settings`, `Lenticular.Display.Api`,
   `Lenticular.Storage`, `Lenticular.Reg`; type `TLenticularDisplay`,
   `TLenticularDisplaySettings`, `TLenticularStorage`) if a program
   ever uses both - e.g. `Lenticular.FMX.StereoViewport` /
   `TLenticularStereoViewport`, or a prefix of the owner's choosing. ASK.
3. **`lib/SimulatedReality.Api.pas`** (direct imports of the vendor's C
   API): its unit name is the vendor's term. Rename (e.g.
   `LenticularRuntime.Api`) or fold what is still used into the bridge.
   Identifiers that ARE the vendor's C names stay, as Winapi keeps Windows'.
4. **The demos and group**: `SRDemoFMX`, `SRDemoVCL`,
   `SimulatedReality.groupproj`, their settings folder
   (`%APPDATA%\SRDelphiFMX`), window titles, and the text in
   `MoviePlayerFMX`.
5. **The repository's name** `SRDelphiFMX` (GitHub redirects a renamed
   repository; StereoModel's submodule path and post-build step would then
   want updating in a later StereoModel session).
6. **Neon**: StereoModel dropped Neon for the RTL's `System.JSON` (owner, 8
   November 2026). This repository has a `delphi-neon` submodule too; the
   owner may want the same here.
7. **Docs**: `README.md`, `CREDITS.md`, `CLAUDE.md`, `tools/pasdoc.bat`,
   `dll/README.md` - all mention the maker; reword and add the Trademarks
   notice to the README.

Files that mention the maker today (at 2c4a2f1): `README.md`, `CREDITS.md`,
`CLAUDE.md`, `tools/pasdoc.bat`, `bridge/CMakeLists.txt`,
`bridge/SRBridge.h`, `bridge/SRBridge.cpp`, `lib/SRBridge.Api.pas`,
`lib/SimulatedReality.Api.pas`, `lib/SRSettings.pas`,
`lib/SRStartProblem.pas`, `lib/FMX.SRStereoViewport.pas`,
`lib/FMX.SRStereoViewport.Reg.pas`, `SRDemoFMX/SRDemoFMX.dpr`,
`SRDemoFMX/ui/MainForm.pas`, `SRDemoVCL/SRDemoVCL.dpr`,
`SRDemoVCL/ui/MainFormVCL.pas`, `MoviePlayerFMX/MoviePlayerFMX.dpr`,
`MoviePlayerFMX/ui/PlayerForm.pas`.

## Part 3 - Order of work and checks

1. Part 1 first, as one change: CMake, header, .cpp, the Pascal import unit,
   every project that uses them, and the new export. Rebuild the DLL (MSVC
   x64) so `dll/LenticularBridge.dll` is the one committed.
2. Check the exports: `dumpbin /exports dll\LenticularBridge.dll` lists only
   `lnb_...` names (32: the 31 of today plus `lnb_RuntimeInstalled`), no `srb_`.
3. Check sizes are unchanged: the .cpp already asserts `SRB_SceneParams` is
   64 bytes; add `static_assert(sizeof(LNB_Stats) == 96)` and
   `static_assert(sizeof(LNB_GpuCheck) == 416)` beside it.
4. `git grep -n -i "leia"` finds only the README's Trademarks notice;
   `git grep -n -w "SR"` finds only SDK code identifiers inside the bridge
   (and whatever of Part 2 the owner chose to keep for now).
5. Build and run SRDemoFMX (it must still weave) - this repository's own
   regression test.
6. Then in StereoModel (its `refactor` branch): update the submodule to this
   repository's new commit (`git -C SRDelphiFMX fetch` + checkout, then
   commit the gitlink), build StereoModel Win64: the post-build copies
   `LenticularBridge.dll`; the log's start shows "Display runtime <version>",
   the Stereo button appears, and Stereo weaves as before.
7. Follow this repository's own delivery rules (its CLAUDE.md): whole files,
   its rebuild lines, and say BRIDGE REBUILD.

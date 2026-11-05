{ @abstract(Imports for SRBridge.dll, the C wrapper around the LeiaSR
  DirectX 11 weaver.)

  The SR weaver is C++ only, so @code(bridge/SRBridge.cpp) wraps it behind
  a flat C API; this unit declares that API for Delphi. See
  @code(bridge/SRBridge.h) for the C side. The SR runtime is 64-bit only.
  This unit still compiles for Win32 so a design-time package can load in the
  32-bit IDE; there the imports are never called and @link(SRBridgeAvailable)
  returns @false.

  All imports are delayed, so a program using this unit starts on machines
  without the DLL; call @link(SRBridgeAvailable) before anything else. }
unit SRBridge.Api;

interface

{$ALIGN 8}
{$WARN SYMBOL_PLATFORM OFF}

const
  { File name of the bridge DLL, expected beside the executable. }
  SRBridgeDll = 'SRBridge.dll';

  { Success. }
  SRB_OK = 0;
  { The bridge has not been initialised. }
  SRB_E_NOT_INITIALIZED = -1;
  { The SR runtime DLLs could not be loaded. }
  SRB_E_SR_DLL_MISSING = -2;
  { No SR context: the SR service is not running. }
  SRB_E_NO_SERVICE = -3;
  { The SR display did not become ready in time. }
  SRB_E_NO_DISPLAY = -4;
  { Direct3D 11 failed. }
  SRB_E_D3D = -5;
  { The weaver could not be created. }
  SRB_E_WEAVER = -6;
  { Bad arguments. }
  SRB_E_ARGS = -7;
  { The child window could not be created. }
  SRB_E_WINDOW = -8;

  { @code(srb_SubmitViews) presented the left view unwoven, because SR is
    temporarily unavailable. }
  SRB_S_2D_FALLBACK = 1;
  { @code(srb_SubmitViews) found the window fully hidden. }
  SRB_S_OCCLUDED = 2;

  { Pixel format: blue, green, red, alpha bytes. }
  SRB_FMT_BGRA8 = 0;
  { Pixel format: red, green, blue, alpha bytes. }
  SRB_FMT_RGBA8 = 1;

type
  { Physical properties of the SR display. }
  TSRBDisplayInfo = record
    { Width in pixels as seen by the user. }
    resolutionWidth: Int32;
    { Height in pixels as seen by the user. }
    resolutionHeight: Int32;
    { Width of the panel in pixels. }
    physicalResolutionWidth: Int32;
    { Height of the panel in pixels. }
    physicalResolutionHeight: Int32;
    { Width of the active area in millimetres. }
    physicalWidthMM: Single;
    { Height of the active area in millimetres. }
    physicalHeightMM: Single;
    { Recommended width of each eye's view in pixels. }
    recommendedViewWidth: Int32;
    { Recommended height of each eye's view in pixels. }
    recommendedViewHeight: Int32;
  end;
  { Pointer to a @link(TSRBDisplayInfo). }
  PSRBDisplayInfo = ^TSRBDisplayInfo;

  { One SR system event, copied off the SR thread by the bridge. }
  TSRBSystemEvent = record
    { Microseconds since the epoch. }
    time: UInt64;
    { The SR event type (SR_Info, SR_ContextInvalid and so on). }
    eventType: UInt64;
    { The event's message, zero-terminated UTF-8. }
    message: array[0..255] of AnsiChar;
  end;
  { Pointer to a @link(TSRBSystemEvent). }
  PSRBSystemEvent = ^TSRBSystemEvent;

  { Counters kept by the bridge for diagnostics, since initialisation.
    Matches @code(SRB_Stats) in @code(SRBridge.h): 96 bytes. }
  TSRBStats = record
    { Present calls. }
    framesSubmitted: UInt64;
    { Frames presented woven. }
    framesWoven: UInt64;
    { Frames presented unwoven because SR was unavailable. }
    frames2D: UInt64;
    { Frames whose window was fully hidden. }
    framesOccluded: UInt64;
    { SR context re-creations tried after a loss. }
    reinitAttempts: UInt64;
    { SR context re-creations that worked. }
    reinitSuccesses: UInt64;
    { C++ exceptions caught from the SR runtime. }
    exceptions: UInt64;
    { The weaver's latency setting in microseconds. }
    weaverLatencyUs: UInt64;
    { HRESULT of the last Present. }
    lastPresentHr: Int32;
    { Back buffer width in pixels. }
    backBufferWidth: Int32;
    { Back buffer height in pixels. }
    backBufferHeight: Int32;
    { Width of each eye's view last submitted. }
    viewWidth: Int32;
    { Height of each eye's view last submitted. }
    viewHeight: Int32;
    { 1 when a weaver exists. }
    weaving: Int32;
    { 1 when a context loss is waiting to be recovered. }
    contextInvalid: Int32;
    { Padding. }
    reserved: Int32;
  end;
  { Pointer to a @link(TSRBStats). }
  PSRBStats = ^TSRBStats;

  { What to draw with @link(srb_RenderScene). Matches @code(SRB_SceneParams)
    in @code(SRBridge.h): 64 bytes (32 before 5 November 2026, 08:30). }
  TSRBSceneParams = record
    { Width of each eye's view in pixels. }
    viewWidth: Int32;
    { Height of each eye's view in pixels. }
    viewHeight: Int32;
    { The cubes' turn about their vertical axis, radians. }
    rotation: Single;
    { Eye separation in millimetres, 0 for the tracked one. }
    eyeSeparationMM: Single;
    { Scale of the eye separation about the midpoint (depth); 1 is real, 0
      means 1. }
    depthScale: Single;
    { 0 draws from a fixed viewer 650 mm in front of the window's centre. }
    lookAround: Int32;
    { 1 draws both eyes from the midpoint: a 2D picture, for the lens off. }
    flat: Int32;
    { The frame rate, drawn on the glass at the top left; below 0 none. }
    fps: Int32;
    { The whole scene moved away from the viewer, world units (the viewport
      is 16.57 units high on the glass, as SRDemoFMX's). }
    sceneZ: Single;
    { The scene turned about the horizontal axis through the main sphere,
      degrees. }
    tiltDeg: Single;
    { The scene turned about the depth axis through the main sphere,
      degrees. }
    rollDeg: Single;
    { The sphere grid turned about the vertical axis through the main
      sphere, degrees. }
    gridSpinDeg: Single;
    { Kept zero. }
    reserved: array[0..3] of Int32;
  end;
  { Pointer to a @link(TSRBSceneParams). }
  PSRBSceneParams = ^TSRBSceneParams;

  { What @link(srb_RenderScene) drew from. Matches @code(SRB_SceneInfo):
    48 bytes. }
  TSRBSceneInfo = record
    { The left eye drawn from, millimetres from the display's centre, x
      right, y up, z towards the viewer. }
    leftEye: array[0..2] of Single;
    { The right eye drawn from. }
    rightEye: array[0..2] of Single;
    { The window's centre on the display, x, millimetres. }
    windowCenterX: Single;
    { The window's centre on the display, y, millimetres. }
    windowCenterY: Single;
    { The window's width in millimetres. }
    windowWidth: Single;
    { The window's height in millimetres. }
    windowHeight: Single;
    { 1 when the tracker had no eyes yet and a default viewer was used. }
    nominalEyes: Int32;
    { 1 when the tracked separation was outside 45-85 mm and 63 mm was
      used. }
    separationRebuilt: Int32;
  end;
  { Pointer to a @link(TSRBSceneInfo). }
  PSRBSceneInfo = ^TSRBSceneInfo;

  { Which GPUs are in use, from @link(srb_GetGpuCheck). Matches
    @code(SRB_GpuCheck) in @code(SRBridge.h): 416 bytes. }
  TSRBGpuCheck = record
    { The program's GPU, UTF-8; empty if no device was given. }
    programAdapter: array[0..127] of AnsiChar;
    { The bridge's GPU, UTF-8. }
    bridgeAdapter: array[0..127] of AnsiChar;
    { The GPU driving the SR display, UTF-8; empty if not found. }
    srDisplayAdapter: array[0..127] of AnsiChar;
    { 1 when the program draws on the SR display's GPU, 0 when it does not
      (slow, and may misbehave), -1 when unknown. }
    programOnSRAdapter: Int32;
    { 1 when the bridge is on the SR display's GPU, 0 when not, -1 unknown. }
    bridgeOnSRAdapter: Int32;
    { 1 when the bridge shares the program's device (zero copy). }
    sharingProgramDevice: Int32;
    { 1 when the program's device was offered but is not on the SR display's
      GPU, so it was not shared. }
    sharedRefused: Int32;
    { 1 when the program draws in software (WARP, the Basic Render
      Driver). }
    programSoftware: Int32;
    { The SR display's refresh rate in hertz, 0 if unknown. }
    srRefreshHz: Int32;
    { Padding. }
    reserved: array[0..1] of Int32;
  end;
  { Pointer to a @link(TSRBGpuCheck). }
  PSRBGpuCheck = ^TSRBGpuCheck;

  { Receives one zero-terminated UTF-8 log line from the bridge, on any
    thread; see @link(srb_SetLogCallback). }
  TSRBLogCallback = procedure(Line: PAnsiChar); cdecl;

  { Four integers: a rectangle's left, top, right and bottom. }
  TSRBRect = array[0..3] of Int32;

  { Three singles: an eye position in millimetres. }
  TSRBVec3 = array[0..2] of Single;

{ Creates the SR context, a child window of @code(parentWnd), a Direct3D 11
  device and the weaver, waiting up to @code(timeoutSeconds) for the SR
  service.
  @returns(@link(SRB_OK) or a negative error code) }
function srb_Initialize(parentWnd: Pointer; timeoutSeconds: Double): Int32; cdecl;
  external SRBridgeDll delayed;
{ Destroys the weaver, SR context, Direct3D objects and child window. }
procedure srb_Finalize; cdecl; external SRBridgeDll delayed;
{ @returns(1 when initialised) }
function srb_IsInitialized: Int32; cdecl; external SRBridgeDll delayed;
{ @returns(1 when a weaver exists) }
function srb_IsWeaving: Int32; cdecl; external SRBridgeDll delayed;
{ Places the child window, in physical pixels relative to the parent's client
  area; the size is also the back buffer's. }
function srb_SetBounds(x, y, width, height: Int32): Int32; cdecl; external SRBridgeDll delayed;
{ Shows (1) or hides (0) the child window. }
procedure srb_SetVisible(visible: Int32); cdecl; external SRBridgeDll delayed;
{ Fills @code(info) with the SR display's properties. }
function srb_GetDisplayInfo(info: PSRBDisplayInfo): Int32; cdecl; external SRBridgeDll delayed;
{ The SR display's rectangle on the desktop in physical pixels, from SR
  itself when possible, otherwise by matching monitors' resolution and
  physical size.
  @returns(@link(SRB_OK), or @link(SRB_E_NO_DISPLAY) if it was not found) }
function srb_GetDisplayRect(var rect: TSRBRect): Int32; cdecl; external SRBridgeDll delayed;
{ The child window's rectangle on the SR display in millimetres, from the
  display's centre, x right and y up. }
function srb_GetWindowRectMM(out centerX, centerY, width, height: Double): Int32; cdecl;
  external SRBridgeDll delayed;
{ The weaver's predicted eye positions in millimetres, from the display's
  centre, x right, y up, z towards the viewer. }
function srb_GetEyePositions(var left, right: TSRBVec3): Int32; cdecl; external SRBridgeDll delayed;
{ Uploads a side-by-side image (left view in the left half), weaves and
  presents it.
  @returns(@link(SRB_OK), @link(SRB_S_2D_FALLBACK), @link(SRB_S_OCCLUDED) or a
    negative error code) }
function srb_SubmitViews(pixels: Pointer; viewWidth, viewHeight, pitch, pixelFormat: Int32): Int32;
  cdecl; external SRBridgeDll delayed;
{ Draws the bridge's own 3D scene (a back wall, a floor, a turning cube on
  the glass and four spheres in front of and behind it) for both eyes
  straight into a view texture on the GPU, with an off-axis projection per
  eye, then weaves and presents. No pixels pass through the program. Not in
  bridges built before 5 November 2026, 03:30: check with
  @link(SRBridgeHasExport).
  @param(params what to draw)
  @param(info receives the eyes and window used; may be nil)
  @returns(as @link(srb_SubmitViews)) }
function srb_RenderScene(params: PSRBSceneParams; info: PSRBSceneInfo): Int32; cdecl;
  external SRBridgeDll delayed;
{ The bridge's @code(sizeof(SRB_SceneParams)): must be
  @code(SizeOf(TSRBSceneParams)) (64). Not in bridges built before
  5 November 2026, 08:40, which draw the old scene from 32-byte params:
  check with @link(SRBridgeHasExport).
  @returns(the size in bytes) }
function srb_SceneParamsSize: Int32; cdecl; external SRBridgeDll delayed;
{ Zero copy: the bridge shares this Direct3D 11 device (FMX's
  @code(TCustomDX11Context.SharedDevice)) instead of making its own. Call
  before @link(srb_Initialize); nil goes back to the bridge's own device.
  Not in bridges built before 5 November 2026, 04:30: check with
  @link(SRBridgeHasExport).
  @param(d3d11Device an @code(ID3D11Device), or nil) }
procedure srb_SetExternalDevice(d3d11Device: Pointer); cdecl; external SRBridgeDll delayed;
{ Whether SR can start, without a window or a device: loads the runtime,
  then tries for an SR context and a ready display until timeoutMs has
  passed, and deletes the context again. Meant for a background thread, so
  waiting for a starting service or a display does not freeze the program
  (@link(srb_Initialize) waits on the calling thread); call nothing else in
  the bridge until it returns. Not in bridges built before 5 November 2026,
  06:20: check with @link(SRBridgeHasExport).
  @param(timeoutMs how long to keep trying; 0 tries each once)
  @returns(@link(SRB_OK), @link(SRB_E_SR_DLL_MISSING),
    @link(SRB_E_NO_SERVICE) or @link(SRB_E_NO_DISPLAY)) }
function srb_Probe(timeoutMs: Int32): Int32; cdecl; external SRBridgeDll delayed;
{ For the GPU check only: the program's own Direct3D 11 device, not shared.
  Call before @link(srb_Initialize). Not in bridges built before 5 November
  2026, 05:00: check with @link(SRBridgeHasExport).
  @param(d3d11Device an @code(ID3D11Device), or nil) }
procedure srb_SetProgramDevice(d3d11Device: Pointer); cdecl; external SRBridgeDll delayed;
{ After @link(srb_Initialize): which GPU the program, the bridge and the SR
  display are on. Not in bridges built before 5 November 2026, 05:00.
  @param(check receives the answer)
  @returns(@link(SRB_OK), or @link(SRB_E_NO_DISPLAY) if the SR display's GPU
    was not found; the other fields are still filled in) }
function srb_GetGpuCheck(check: PSRBGpuCheck): Int32; cdecl; external SRBridgeDll delayed;
{ Zero copy: copies one eye's rendered texture (on the shared device;
  multisampled is resolved) into that eye's half of the view texture, on
  the GPU.
  @param(eye 0 left, 1 right)
  @param(texture an @code(ID3D11Texture2D) or its @code(ID3D11Resource))
  @param(viewWidth width of each view in pixels)
  @param(viewHeight height of each view in pixels)
  @returns(@link(SRB_OK) or a negative error code) }
function srb_CopyEyeTexture(eye: Int32; texture: Pointer; viewWidth, viewHeight: Int32): Int32;
  cdecl; external SRBridgeDll delayed;
{ Zero copy: weaves and presents the views copied with
  @link(srb_CopyEyeTexture).
  @returns(as @link(srb_SubmitViews)) }
function srb_PresentViews(viewWidth, viewHeight: Int32): Int32; cdecl; external SRBridgeDll delayed;
{ 1 (the default): with vsync on, wait for the SR display's vertical blank
  after each present (the compositor if its output is unknown), so no more
  frames are drawn than the display shows. }
procedure srb_SetFrameCap(enabled: Int32); cdecl; external SRBridgeDll delayed;
{ Turns waiting for the vertical blank on (1) or off (0). }
procedure srb_SetVSync(enabled: Int32); cdecl; external SRBridgeDll delayed;
{ Tells the weaver how many frames the rendering pipeline takes. }
procedure srb_SetLatencyInFrames(frames: UInt64); cdecl; external SRBridgeDll delayed;
{ Asks for the lens to be on (1) or off (0). }
procedure srb_SetLens(enabled: Int32); cdecl; external SRBridgeDll delayed;
{ Takes the oldest queued system event.
  @returns(1 if one was written to @code(ev), 0 if none) }
function srb_PollSystemEvent(ev: PSRBSystemEvent): Int32; cdecl; external SRBridgeDll delayed;
{ Fills @code(stats) with the bridge's counters. }
function srb_GetStats(stats: PSRBStats): Int32; cdecl; external SRBridgeDll delayed;
{ Sends the bridge's log lines to @code(callback) (nil to stop). Also
  installs last-gasp handlers for abort, @code(std::terminate), pure virtual
  calls and CRT invalid parameters, which log a FATAL line before the program
  ends. The callback is called from any thread and must be thread-safe. }
procedure srb_SetLogCallback(callback: TSRBLogCallback); cdecl; external SRBridgeDll delayed;
{ @returns(the last error message, UTF-8) }
function srb_GetLastError: PAnsiChar; cdecl; external SRBridgeDll delayed;
{ @returns(the SR platform version, UTF-8) }
function srb_GetPlatformVersion: PAnsiChar; cdecl; external SRBridgeDll delayed;
{ Adds a folder to search for the SR runtime DLLs; call before
  @link(srb_Initialize). }
procedure srb_SetDllDirectory(path: PWideChar); cdecl; external SRBridgeDll delayed;

{ Loads SRBridge.dll from the executable's folder or the search path.
  @returns(@true if it could be loaded; always @false in a 32-bit build) }
function SRBridgeAvailable: Boolean;

{ Whether the loaded bridge exports a function, for exports added after the
  first release, which an older DLL lacks (calling one would raise an
  exception).
  @param(Name the export's name, such as @code('srb_Probe'))
  @returns(@true if the DLL is loaded and has it) }
function SRBridgeHasExport(const Name: string): Boolean;

{ Whether the LeiaSR runtime is installed: its three DLLs
  (@code(SimulatedRealityCore.dll), @code(SimulatedRealityDisplays.dll),
  @code(SimulatedRealityDirectX.dll)) can be found where the bridge would
  load them from. Checked without loading them as code and without the
  bridge, so it is quick and safe on any computer; on one without LeiaSR a
  program can behave as if it had no SR support at all. It says nothing
  about whether the SR service is running or a display plugged in.
  @returns(@true if all three are found) }
function SRRuntimeInstalled: Boolean;

{ The bridge's last error, or why the DLL could not be loaded.
  @returns(a readable message) }
function SRBridgeLastError: string;

implementation

uses
  Winapi.Windows, System.SysUtils;

var
  { Module handle of the loaded bridge, 0 until loaded. }
  BridgeHandle: HMODULE = 0;
  { Windows error code from the failed load, 0 if none. }
  BridgeLoadError: DWORD = 0;

function SRBridgeAvailable: Boolean;
begin
{$IFDEF WIN64}
  if BridgeHandle = 0 then
  begin
    BridgeHandle := SafeLoadLibrary(ExtractFilePath(ParamStr(0)) + SRBridgeDll);
    if BridgeHandle = 0 then
      BridgeHandle := SafeLoadLibrary(SRBridgeDll);
    if BridgeHandle = 0 then
      BridgeLoadError := GetLastError;
  end;
  Result := BridgeHandle <> 0;
{$ELSE}
  Result := False;
{$ENDIF}
end;

function SRBridgeHasExport(const Name: string): Boolean;
begin
  Result := SRBridgeAvailable and (GetProcAddress(BridgeHandle, PChar(Name)) <> nil);
end;

function SRRuntimeInstalled: Boolean;
const
  RuntimeDlls: array[0..2] of string = ('SimulatedRealityCore.dll', 'SimulatedRealityDisplays.dll',
    'SimulatedRealityDirectX.dll');
var
  Name: string;
  H: HMODULE;
begin
  for Name in RuntimeDlls do
  begin
    // The same search as the bridge's LoadLibraryW, but as data: no code
    // runs and no dependencies are needed
    H := LoadLibraryEx(PChar(Name), 0, LOAD_LIBRARY_AS_DATAFILE);
    if H = 0 then
      Exit(False);
    FreeLibrary(H);
  end;
  Result := True;
end;

function SRBridgeLastError: string;
begin
{$IFDEF WIN64}
  if SRBridgeAvailable then
    Exit(UTF8ToString(srb_GetLastError));
  case BridgeLoadError of
    ERROR_MOD_NOT_FOUND:
      Result := SRBridgeDll + ' or one of its dependencies was not found (exe folder: ' +
        ExtractFilePath(ParamStr(0)) + '). If the DLL is there, install the ' +
        'Microsoft Visual C++ 2015-2022 x64 redistributable.';
    ERROR_BAD_EXE_FORMAT:
      Result := SRBridgeDll + ' has the wrong bitness for this program.';
  else
    Result := Format('%s could not be loaded: %s (error %d)',
      [SRBridgeDll, SysErrorMessage(BridgeLoadError), BridgeLoadError]);
  end;
{$ELSE}
  Result := 'This is a 32-bit build. LeiaSR needs the Windows 64-bit target platform.';
{$ENDIF}
end;

end.

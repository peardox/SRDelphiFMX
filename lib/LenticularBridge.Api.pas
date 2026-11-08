{ @abstract(Imports for LenticularBridge.dll, the C wrapper around the
  lenticular display runtime's DirectX 11 weaver.)

  The weaver is C++ only, so @code(bridge/LenticularBridge.cpp) wraps it behind
  a flat C API; this unit declares that API for Delphi. See
  @code(bridge/LenticularBridge.h) for the C side. The display runtime is 64-bit only.
  This unit compiles on every platform, so the Lenticular package (which
  holds it) and the programs using it stay cross-platform: the records and
  constants are declared everywhere, the imports only on Windows. Elsewhere,
  and on Win32 (where the imports exist so the 32-bit IDE can load the
  design package, but are never called), @link(LenticularBridgeAvailable)
  and @link(LenticularRuntimeInstalled) return @false and nothing else may
  be called.

  All imports are delayed, so a program using this unit starts on machines
  without the DLL; call @link(LenticularBridgeAvailable) before anything else. }
unit LenticularBridge.Api;

interface

{$ALIGN 8}
{$WARN SYMBOL_PLATFORM OFF}

const
  { File name of the bridge DLL, expected beside the executable. }
  LenticularBridgeDll = 'LenticularBridge.dll';

  { Success. }
  LNB_OK = 0;
  { The bridge has not been initialised. }
  LNB_E_NOT_INITIALIZED = -1;
  { The display runtime DLLs could not be loaded. }
  LNB_E_RUNTIME_MISSING = -2;
  { No runtime context: the display service is not running. }
  LNB_E_NO_SERVICE = -3;
  { The 3D display did not become ready in time. }
  LNB_E_NO_DISPLAY = -4;
  { Direct3D 11 failed. }
  LNB_E_D3D = -5;
  { The weaver could not be created. }
  LNB_E_WEAVER = -6;
  { Bad arguments. }
  LNB_E_ARGS = -7;
  { The child window could not be created. }
  LNB_E_WINDOW = -8;

  { @code(lnb_SubmitViews) presented the left view unwoven, because the display is
    temporarily unavailable. }
  LNB_S_2D_FALLBACK = 1;
  { @code(lnb_SubmitViews) found the window fully hidden. }
  LNB_S_OCCLUDED = 2;

  { Pixel format: blue, green, red, alpha bytes. }
  LNB_FMT_BGRA8 = 0;
  { Pixel format: red, green, blue, alpha bytes. }
  LNB_FMT_RGBA8 = 1;

  { @link(TLNBSystemEvent).eventType when the display's lens has come on. }
  LNB_EVENT_LENS_ON = 14;
  { @link(TLNBSystemEvent).eventType when the display's lens has gone off. }
  LNB_EVENT_LENS_OFF = 15;

type
  { Physical properties of the 3D display. }
  TLNBDisplayInfo = record
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
  { Pointer to a @link(TLNBDisplayInfo). }
  PLNBDisplayInfo = ^TLNBDisplayInfo;

  { One runtime event, copied off the runtime's thread by the bridge. }
  TLNBSystemEvent = record
    { Microseconds since the epoch. }
    time: UInt64;
    { The runtime event type (Info, ContextInvalid and so on). }
    eventType: UInt64;
    { The event's message, zero-terminated UTF-8. }
    message: array[0..255] of AnsiChar;
  end;
  { Pointer to a @link(TLNBSystemEvent). }
  PLNBSystemEvent = ^TLNBSystemEvent;

  { Counters kept by the bridge for diagnostics, since initialisation.
    Matches @code(LNB_Stats) in @code(LenticularBridge.h): 96 bytes. }
  TLNBStats = record
    { Present calls. }
    framesSubmitted: UInt64;
    { Frames presented woven. }
    framesWoven: UInt64;
    { Frames presented unwoven because the display was unavailable. }
    frames2D: UInt64;
    { Frames whose window was fully hidden. }
    framesOccluded: UInt64;
    { runtime context re-creations tried after a loss. }
    reinitAttempts: UInt64;
    { runtime context re-creations that worked. }
    reinitSuccesses: UInt64;
    { C++ exceptions caught from the display runtime. }
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
  { Pointer to a @link(TLNBStats). }
  PLNBStats = ^TLNBStats;

  { What to draw with @link(lnb_RenderScene). Matches @code(LNB_SceneParams)
    in @code(LenticularBridge.h): 64 bytes (32 before 5 November 2026, 08:30). }
  TLNBSceneParams = record
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
      is 16.57 units high on the glass, as LenticularDemoFMX's). }
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
  { Pointer to a @link(TLNBSceneParams). }
  PLNBSceneParams = ^TLNBSceneParams;

  { What @link(lnb_RenderScene) drew from. Matches @code(LNB_SceneInfo):
    48 bytes. }
  TLNBSceneInfo = record
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
  { Pointer to a @link(TLNBSceneInfo). }
  PLNBSceneInfo = ^TLNBSceneInfo;

  { Which GPUs are in use, from @link(lnb_GetGpuCheck). Matches
    @code(LNB_GpuCheck) in @code(LenticularBridge.h): 416 bytes. }
  TLNBGpuCheck = record
    { The program's GPU, UTF-8; empty if no device was given. }
    programAdapter: array[0..127] of AnsiChar;
    { The bridge's GPU, UTF-8. }
    bridgeAdapter: array[0..127] of AnsiChar;
    { The GPU driving the 3D display, UTF-8; empty if not found. }
    displayAdapter: array[0..127] of AnsiChar;
    { 1 when the program draws on the 3D display's GPU, 0 when it does not
      (slow, and may misbehave), -1 when unknown. }
    programOnDisplayAdapter: Int32;
    { 1 when the bridge is on the 3D display's GPU, 0 when not, -1 unknown. }
    bridgeOnDisplayAdapter: Int32;
    { 1 when the bridge shares the program's device (zero copy). }
    sharingProgramDevice: Int32;
    { 1 when the program's device was offered but is not on the 3D display's
      GPU, so it was not shared. }
    sharedRefused: Int32;
    { 1 when the program draws in software (WARP, the Basic Render
      Driver). }
    programSoftware: Int32;
    { The 3D display's refresh rate in hertz, 0 if unknown. }
    displayRefreshHz: Int32;
    { Padding. }
    reserved: array[0..1] of Int32;
  end;
  { Pointer to a @link(TLNBGpuCheck). }
  PLNBGpuCheck = ^TLNBGpuCheck;

  { Receives one zero-terminated UTF-8 log line from the bridge, on any
    thread; see @link(lnb_SetLogCallback). }
  TLNBLogCallback = procedure(Line: PAnsiChar); cdecl;

  { Four integers: a rectangle's left, top, right and bottom. }
  TLNBRect = array[0..3] of Int32;

  { Three singles: an eye position in millimetres. }
  TLNBVec3 = array[0..2] of Single;

{$IFDEF MSWINDOWS}
// The imports: Windows only (the display runtime is Windows 64-bit only)

{ Creates the runtime context, a child window of @code(parentWnd), a Direct3D 11
  device and the weaver, waiting up to @code(timeoutSeconds) for the display
  service.
  @returns(@link(LNB_OK) or a negative error code) }
function lnb_Initialize(parentWnd: Pointer; timeoutSeconds: Double): Int32; cdecl;
  external LenticularBridgeDll delayed;
{ Destroys the weaver, runtime context, Direct3D objects and child window. }
procedure lnb_Finalize; cdecl; external LenticularBridgeDll delayed;
{ @returns(1 when initialised) }
function lnb_IsInitialized: Int32; cdecl; external LenticularBridgeDll delayed;
{ @returns(1 when a weaver exists) }
function lnb_IsWeaving: Int32; cdecl; external LenticularBridgeDll delayed;
{ Places the child window, in physical pixels relative to the parent's client
  area; the size is also the back buffer's. }
function lnb_SetBounds(x, y, width, height: Int32): Int32; cdecl;
  external LenticularBridgeDll delayed;
{ Shows (1) or hides (0) the child window. }
procedure lnb_SetVisible(visible: Int32); cdecl; external LenticularBridgeDll delayed;
{ Fills @code(info) with the 3D display's properties. }
function lnb_GetDisplayInfo(info: PLNBDisplayInfo): Int32; cdecl;
  external LenticularBridgeDll delayed;
{ The 3D display's rectangle on the desktop in physical pixels, from the display
  itself when possible, otherwise by matching monitors' resolution and
  physical size.
  @returns(@link(LNB_OK), or @link(LNB_E_NO_DISPLAY) if it was not found) }
function lnb_GetDisplayRect(var rect: TLNBRect): Int32; cdecl; external LenticularBridgeDll delayed;
{ The child window's rectangle on the 3D display in millimetres, from the
  display's centre, x right and y up. }
function lnb_GetWindowRectMM(out centerX, centerY, width, height: Double): Int32; cdecl;
  external LenticularBridgeDll delayed;
{ The weaver's predicted eye positions in millimetres, from the display's
  centre, x right, y up, z towards the viewer. }
function lnb_GetEyePositions(var left, right: TLNBVec3): Int32; cdecl;
  external LenticularBridgeDll delayed;
{ Uploads a side-by-side image (left view in the left half), weaves and
  presents it.
  @returns(@link(LNB_OK), @link(LNB_S_2D_FALLBACK), @link(LNB_S_OCCLUDED) or a
    negative error code) }
function lnb_SubmitViews(pixels: Pointer; viewWidth, viewHeight, pitch, pixelFormat: Int32): Int32;
  cdecl; external LenticularBridgeDll delayed;
{ Draws the bridge's own 3D scene (a back wall, a floor, a turning cube on
  the glass and four spheres in front of and behind it) for both eyes
  straight into a view texture on the GPU, with an off-axis projection per
  eye, then weaves and presents. No pixels pass through the program. Not in
  bridges built before 5 November 2026, 03:30: check with
  @link(LenticularBridgeHasExport).
  @param(params what to draw)
  @param(info receives the eyes and window used; may be nil)
  @returns(as @link(lnb_SubmitViews)) }
function lnb_RenderScene(params: PLNBSceneParams; info: PLNBSceneInfo): Int32; cdecl;
  external LenticularBridgeDll delayed;
{ The bridge's @code(sizeof(LNB_SceneParams)): must be
  @code(SizeOf(TLNBSceneParams)) (64). Not in bridges built before
  5 November 2026, 08:40, which draw the old scene from 32-byte params:
  check with @link(LenticularBridgeHasExport).
  @returns(the size in bytes) }
function lnb_SceneParamsSize: Int32; cdecl; external LenticularBridgeDll delayed;
{ Zero copy: the bridge shares this Direct3D 11 device (FMX's
  @code(TCustomDX11Context.SharedDevice)) instead of making its own. Call
  before @link(lnb_Initialize); nil goes back to the bridge's own device.
  Not in bridges built before 5 November 2026, 04:30: check with
  @link(LenticularBridgeHasExport).
  @param(d3d11Device an @code(ID3D11Device), or nil) }
procedure lnb_SetExternalDevice(d3d11Device: Pointer); cdecl; external LenticularBridgeDll delayed;
{ Whether the display can start, without a window or a device: loads the runtime,
  then tries for an runtime context and a ready display until timeoutMs has
  passed, and deletes the context again. Meant for a background thread, so
  waiting for a starting service or a display does not freeze the program
  (@link(lnb_Initialize) waits on the calling thread); call nothing else in
  the bridge until it returns. Not in bridges built before 5 November 2026,
  06:20: check with @link(LenticularBridgeHasExport).
  @param(timeoutMs how long to keep trying; 0 tries each once)
  @returns(@link(LNB_OK), @link(LNB_E_RUNTIME_MISSING),
    @link(LNB_E_NO_SERVICE) or @link(LNB_E_NO_DISPLAY)) }
function lnb_Probe(timeoutMs: Int32): Int32; cdecl; external LenticularBridgeDll delayed;
{ Whether the display runtime is installed: every runtime DLL the bridge
  needs can be found where it would load it from (the normal DLL search,
  plus a folder given to @link(lnb_SetDllDirectory)). Checked as data (no
  code runs, nothing stays loaded), so it is quick and safe on any computer,
  before @link(lnb_Initialize). Says nothing about whether the display
  service is running or a display is plugged in (@link(lnb_Probe) does
  that).
  @returns(1 if all were found, 0 if any was not) }
function lnb_RuntimeInstalled: Int32; cdecl; external LenticularBridgeDll delayed;
{ For the GPU check only: the program's own Direct3D 11 device, not shared.
  Call before @link(lnb_Initialize). Not in bridges built before 5 November
  2026, 05:00: check with @link(LenticularBridgeHasExport).
  @param(d3d11Device an @code(ID3D11Device), or nil) }
procedure lnb_SetProgramDevice(d3d11Device: Pointer); cdecl; external LenticularBridgeDll delayed;
{ After @link(lnb_Initialize): which GPU the program, the bridge and the display
  display are on. Not in bridges built before 5 November 2026, 05:00.
  @param(check receives the answer)
  @returns(@link(LNB_OK), or @link(LNB_E_NO_DISPLAY) if the 3D display's GPU
    was not found; the other fields are still filled in) }
function lnb_GetGpuCheck(check: PLNBGpuCheck): Int32; cdecl; external LenticularBridgeDll delayed;
{ Zero copy: copies one eye's rendered texture (on the shared device;
  multisampled is resolved) into that eye's half of the view texture, on
  the GPU.
  @param(eye 0 left, 1 right)
  @param(texture an @code(ID3D11Texture2D) or its @code(ID3D11Resource))
  @param(viewWidth width of each view in pixels)
  @param(viewHeight height of each view in pixels)
  @returns(@link(LNB_OK) or a negative error code) }
function lnb_CopyEyeTexture(eye: Int32; texture: Pointer; viewWidth, viewHeight: Int32): Int32;
  cdecl; external LenticularBridgeDll delayed;
{ Zero copy: weaves and presents the views copied with
  @link(lnb_CopyEyeTexture).
  @returns(as @link(lnb_SubmitViews)) }
function lnb_PresentViews(viewWidth, viewHeight: Int32): Int32; cdecl;
  external LenticularBridgeDll delayed;
{ 1 (the default): with vsync on, wait for the 3D display's vertical blank
  after each present (the compositor if its output is unknown), so no more
  frames are drawn than the display shows. }
procedure lnb_SetFrameCap(enabled: Int32); cdecl; external LenticularBridgeDll delayed;
{ Turns waiting for the vertical blank on (1) or off (0). }
procedure lnb_SetVSync(enabled: Int32); cdecl; external LenticularBridgeDll delayed;
{ Tells the weaver how many frames the rendering pipeline takes. }
procedure lnb_SetLatencyInFrames(frames: UInt64); cdecl; external LenticularBridgeDll delayed;
{ Asks for the lens to be on (1) or off (0). }
procedure lnb_SetLens(enabled: Int32); cdecl; external LenticularBridgeDll delayed;
{ The lens as it actually is, as the runtime reports it, not as asked.
  @returns(1 on, 0 off, -1 not known: not initialised, or a runtime that
    cannot say) }
function lnb_GetLensState: Int32; cdecl; external LenticularBridgeDll delayed;
{ The bridge's Direct3D 11 device (its own, or the program's when shared),
  for a program that makes its eye textures on it for
  @link(lnb_CopyEyeTexture): an OpenGL program, through WGL_NV_DX_interop2.
  Not AddRef'd: valid until @link(lnb_Finalize). Not in bridges built before
  7 November 2026, 21:00: check with @link(LenticularBridgeHasExport).
  @returns(an @code(ID3D11Device), or nil while not initialised) }
function lnb_GetDevice: Pointer; cdecl; external LenticularBridgeDll delayed;
{ Takes the oldest queued system event.
  @returns(1 if one was written to @code(ev), 0 if none) }
function lnb_PollSystemEvent(ev: PLNBSystemEvent): Int32; cdecl;
  external LenticularBridgeDll delayed;
{ Fills @code(stats) with the bridge's counters. }
function lnb_GetStats(stats: PLNBStats): Int32; cdecl; external LenticularBridgeDll delayed;
{ Sends the bridge's log lines to @code(callback) (nil to stop). Also
  installs last-gasp handlers for abort, @code(std::terminate), pure virtual
  calls and CRT invalid parameters, which log a FATAL line before the program
  ends. The callback is called from any thread and must be thread-safe. }
procedure lnb_SetLogCallback(callback: TLNBLogCallback); cdecl;
  external LenticularBridgeDll delayed;
{ @returns(the last error message, UTF-8) }
function lnb_GetLastError: PAnsiChar; cdecl; external LenticularBridgeDll delayed;
{ @returns(the display runtime version, UTF-8) }
function lnb_GetPlatformVersion: PAnsiChar; cdecl; external LenticularBridgeDll delayed;
{ Adds a folder to search for the display runtime DLLs; call before
  @link(lnb_Initialize). }
procedure lnb_SetDllDirectory(path: PWideChar); cdecl; external LenticularBridgeDll delayed;

{$ENDIF}

{ Loads LenticularBridge.dll from the executable's folder or the search path.
  @returns(@true if it could be loaded; always @false in a 32-bit build) }
function LenticularBridgeAvailable: Boolean;

{ Whether the loaded bridge exports a function, for exports added after the
  first release, which an older DLL lacks (calling one would raise an
  exception).
  @param(Name the export's name, such as @code('lnb_Probe'))
  @returns(@true if the DLL is loaded and has it) }
function LenticularBridgeHasExport(const Name: string): Boolean;

{ Whether the display runtime is installed, as the bridge finds it
  (@link(lnb_RuntimeInstalled): its DLLs looked for as data, never run).
  Quick and safe on any computer; on one without the runtime a program can
  behave as if it had no glasses-free 3D support at all. It loads the
  bridge, so without LenticularBridge.dll beside the executable it is
  @false. It says nothing about whether the display service is running or a
  display plugged in.
  @returns(@true if the bridge loads and finds the runtime) }
function LenticularRuntimeInstalled: Boolean;

{ The bridge's last error, or why the DLL could not be loaded.
  @returns(a readable message) }
function LenticularBridgeLastError: string;

{ @abstract(The name of a runtime event type, for logs.)
  @param(AEventType The event's type, @link(TLNBSystemEvent).eventType.)
  @returns(Its name, such as UserFound or LensOff, or "Event" and the number
  for one this unit does not know.) }
function LenticularEventTypeName(AEventType: UInt64): string;

implementation

uses
  {$IFDEF MSWINDOWS}
  Winapi.Windows,
  {$ENDIF}
  System.SysUtils;

{$IFDEF MSWINDOWS}
var
  { Module handle of the loaded bridge, 0 until loaded. }
  BridgeHandle: HMODULE = 0;
  { Windows error code from the failed load, 0 if none. }
  BridgeLoadError: DWORD = 0;
{$ENDIF}

function LenticularBridgeAvailable: Boolean;
begin
{$IFDEF WIN64}
  if BridgeHandle = 0 then
  begin
    BridgeHandle := SafeLoadLibrary(ExtractFilePath(ParamStr(0)) + LenticularBridgeDll);
    if BridgeHandle = 0 then
      BridgeHandle := SafeLoadLibrary(LenticularBridgeDll);
    if BridgeHandle = 0 then
      BridgeLoadError := GetLastError;
  end;
  Result := BridgeHandle <> 0;
{$ELSE}
  Result := False;
{$ENDIF}
end;

function LenticularBridgeHasExport(const Name: string): Boolean;
begin
{$IFDEF MSWINDOWS}
  Result := LenticularBridgeAvailable and (GetProcAddress(BridgeHandle, PChar(Name)) <> nil);
{$ELSE}
  Result := False;
{$ENDIF}
end;

function LenticularRuntimeInstalled: Boolean;
begin
{$IFDEF WIN64}
  // The runtime's DLL names are the bridge's business, never ours
  Result := LenticularBridgeHasExport('lnb_RuntimeInstalled') and (lnb_RuntimeInstalled = 1);
{$ELSE}
  Result := False;
{$ENDIF}
end;

function LenticularEventTypeName(AEventType: UInt64): string;
const
  // The runtime's event types in the order of their values, as the bridge
  // passes them on
  Names: array[0..17] of string = (
    'Info', 'ContextInvalid', 'RuntimeUnavailable', 'RuntimeRestored',
    'USBNotConnected', 'USBNotConnectedResolved',
    'DisplayNotConnected', 'DisplayNotConnectedResolved',
    'Duplicated', 'DuplicatedResolved',
    'NonNativeResolution', 'NonNativeResolutionResolved',
    'DeviceConnectedAndReady', 'DeviceDisconnected',
    'LensOn', 'LensOff', 'UserFound', 'UserLost');
begin
  if AEventType <= High(Names) then
    Result := Names[AEventType]
  else
    Result := 'Event' + UIntToStr(AEventType);
end;

function LenticularBridgeLastError: string;
begin
{$IF DEFINED(WIN64)}
  if LenticularBridgeAvailable then
    Exit(UTF8ToString(lnb_GetLastError));
  case BridgeLoadError of
    ERROR_MOD_NOT_FOUND:
      Result := LenticularBridgeDll + ' or one of its dependencies was not found (exe folder: ' +
        ExtractFilePath(ParamStr(0)) + '). If the DLL is there, install the ' +
        'Microsoft Visual C++ 2015-2022 x64 redistributable.';
    ERROR_BAD_EXE_FORMAT:
      Result := LenticularBridgeDll + ' has the wrong bitness for this program.';
  else
    Result := Format('%s could not be loaded: %s (error %d)',
      [LenticularBridgeDll, SysErrorMessage(BridgeLoadError), BridgeLoadError]);
  end;
{$ELSEIF DEFINED(MSWINDOWS)}
  Result := 'This is a 32-bit build. Glasses-free 3D needs the Windows 64-bit target platform.';
{$ELSE}
  Result := 'Glasses-free 3D is available on Windows (64-bit) only.';
{$ENDIF}
end;

end.

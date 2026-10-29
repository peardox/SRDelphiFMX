{ @abstract(Delphi translation of the LeiaSR (Simulated Reality) SDK 1.34 C
  API.)

  Covers @code(core_c.h), @code(version_c.h), @code(displays_c.h),
  @code(facetrackers_c.h), @code(sr/types.h), @code(systemevent.h),
  @code(eyepair.h), @code(head.h) and @code(weaverposition.h). The weaver is
  C++ only and is reached through @link(SRFmxBridge.Api) instead; hand
  trackers, cameras and the admin API are not translated.

  All imports are delayed, so a program using this unit starts on machines
  without the SR runtime; call @link(SRRuntimeAvailable) first. The SR runtime
  is 64-bit only; in a 32-bit build @link(SRRuntimeAvailable) returns @false.

  Eye and head positions are in millimetres from the centre of the SR display,
  x to the right, y up and z towards the viewer. }
unit SimulatedReality.Api;

interface

{$MINENUMSIZE 4}
{$ALIGN 8}
{$WARN SYMBOL_PLATFORM OFF}

const
  { The SR core DLL: context and system events. }
  SRCoreDll = 'SimulatedRealityCore.dll';
  { The SR displays DLL: display properties and lens hints. }
  SRDisplaysDll = 'SimulatedRealityDisplays.dll';
  { The SR face trackers DLL: eye, head and weaver-position trackers. }
  SRFaceTrackersDll = 'SimulatedRealityFaceTrackers.dll';
  { The SR DLL that reports the platform version. }
  SRVersionDll = 'SimulatedReality.dll';

type
  { Handle of an SR context, which keeps track of everything created in it. }
  SRContext = Pointer;
  { Handle of an SR display. }
  SR_display = Pointer;
  { Old name for @link(SR_display). }
  SR_screen = SR_display;
  { Handle of a lens hint, owned by the context. }
  SR_switchableLensHint = Pointer;
  { Handle of the system sense, which reports system events. }
  SR_systemSense = Pointer;
  { Handle of a system event listener. }
  SR_systemEventListener = Pointer;
  { Handle of an eye tracker. }
  SR_eyeTracker = Pointer;
  { Handle of an eye pair listener. }
  SR_eyePairListener = Pointer;
  { Handle of a head tracker. }
  SR_headTracker = Pointer;
  { Handle of a head listener. }
  SR_headListener = Pointer;
  { Handle of a predicting weaver tracker. }
  SR_predictingWeaverTracker = Pointer;
  { Handle of a weaver position listener. }
  SR_weaverPositionListener = Pointer;

  { Two 64-bit integers: a vector or point in 2D. }
  SR_vector2i = record
    { First value. }
    x: Int64;
    { Second value. }
    y: Int64;
  end;
  { A point in 2D, integer. }
  SR_point2i = SR_vector2i;
  { Two doubles: a vector or point in 2D. }
  SR_vector2d = record
    { First value. }
    x: Double;
    { Second value. }
    y: Double;
  end;
  { A point in 2D, double. }
  SR_point2d = SR_vector2d;
  { Three doubles: a vector or point in 3D. }
  SR_vector3d = record
    { First value. }
    x: Double;
    { Second value. }
    y: Double;
    { Third value. }
    z: Double;
  end;
  { A point in 3D. }
  SR_point3d = SR_vector3d;
  { Pointer to an @link(SR_point3d). }
  PSR_point3d = ^SR_point3d;
  { An integer rectangle. }
  SR_recti = record
    { Left edge. }
    left: Int64;
    { Top edge. }
    top: Int64;
    { Right edge. }
    right: Int64;
    { Bottom edge. }
    bottom: Int64;
  end;

  { Type of a system event; see the @code(SR_...) constants below. }
  SR_eventType = UInt64;

  { A system-wide event. }
  SR_systemEvent = record
    { Microseconds since the epoch. }
    time: UInt64;
    { What happened. }
    eventType: SR_eventType;
    { Length of @code(message) in bytes. }
    messageLength: UInt64;
    { UTF-8 text, not necessarily zero-terminated: use @code(messageLength). }
    message: PAnsiChar;
  end;
  { Pointer to an @link(SR_systemEvent). }
  PSR_systemEvent = ^SR_systemEvent;

  { Positions of both eyes. }
  SR_eyePair = record
    { Frame number, counting up. }
    frameId: UInt64;
    { Microseconds since the epoch. }
    time: UInt64;
    { Left eye, millimetres. }
    left: SR_point3d;
    { Right eye, millimetres. }
    right: SR_point3d;
  end;
  { Pointer to an @link(SR_eyePair). }
  PSR_eyePair = ^SR_eyePair;

  { Position and orientation of the head. }
  SR_headPose = record
    { Frame number, counting up. }
    frameId: UInt64;
    { Microseconds since the epoch. }
    time: UInt64;
    { Head position, millimetres. }
    position: SR_point3d;
    { Pitch, yaw and roll in radians, clockwise as the user sees it. }
    orientation: SR_point3d;
  end;

  { Positions of both ears. }
  SR_earPair = record
    { Frame number, counting up. }
    frameId: UInt64;
    { Microseconds since the epoch. }
    time: UInt64;
    { Left ear, millimetres. }
    left: SR_point3d;
    { Right ear, millimetres. }
    right: SR_point3d;
  end;

  { Everything the head tracker reports. }
  SR_head = record
    { Frame number, counting up. }
    frameId: UInt64;
    { Microseconds since the epoch. }
    time: UInt64;
    { Head pose. }
    headPose: SR_headPose;
    { Eyes. }
    eyes: SR_eyePair;
    { Ears. }
    ears: SR_earPair;
  end;
  { Pointer to an @link(SR_head). }
  PSR_head = ^SR_head;

  { Position the weaver works from. }
  SR_weaverPosition = record
    { Frame number, counting up. }
    frameId: UInt64;
    { Microseconds since the epoch, when captured. }
    time: UInt64;
    { Position in centimetres (not millimetres). }
    weaverPosition: SR_point3d;
  end;
  { Pointer to an @link(SR_weaverPosition). }
  PSR_weaverPosition = ^SR_weaverPosition;

  { Called on an SR thread with each system event. The C side passes the
    struct by value; on Win64 a struct over 8 bytes passed by value arrives as
    a pointer to a copy, so a pointer parameter is binary-identical. Do not
    touch FMX controls from it: copy the data and use @code(TThread.Queue). }
  TSRSystemEventCallback = procedure(Event: PSR_systemEvent); cdecl;
  { Called on an SR thread with each eye pair; see
    @link(TSRSystemEventCallback) for the rules. }
  TSREyePairCallback = procedure(EyePair: PSR_eyePair); cdecl;
  { Called on an SR thread with each head; see @link(TSRSystemEventCallback)
    for the rules. }
  TSRHeadCallback = procedure(Head: PSR_head); cdecl;
  { Called on an SR thread with each weaver position; see
    @link(TSRSystemEventCallback) for the rules. }
  TSRWeaverPositionCallback = procedure(Position: PSR_weaverPosition); cdecl;

const
  { Information about the system that does not affect the program. }
  SR_Info = 0;
  { The context must be re-created. }
  SR_ContextInvalid = 1;
  { Show 2D only: SR content cannot be seen as intended. }
  SR_SRUnavailable = 2;
  { SR content can be shown again. }
  SR_SRRestored = 3;
  { The device's USB cable is not connected. }
  SR_USBNotConnected = 4;
  { The device's USB cable is connected again. }
  SR_USBNotConnectedResolved = 5;
  { The device's display cable is not connected. }
  SR_DisplayNotConnected = 6;
  { The device's display cable is connected again. }
  SR_DisplayNotConnectedResolved = 7;
  { The SR display is duplicated, so SR content cannot be shown. }
  SR_Duplicated = 8;
  { The SR display is extended again. }
  SR_DuplicatedResolved = 9;
  { The SR display is not at its native resolution. }
  SR_NonNativeResolution = 10;
  { The SR display is at its native resolution again. }
  SR_NonNativeResolutionResolved = 11;
  { The device is connected and ready. }
  SR_DeviceConnectedAndReady = 12;
  { The device was disconnected. }
  SR_DeviceDisconnected = 13;
  { The lens was switched on. }
  SR_LensOn = 14;
  { The lens was switched off. }
  SR_LensOff = 15;
  { The eye tracker found the user. }
  SR_UserFound = 16;
  { The eye tracker lost the user. }
  SR_UserLost = 17;

  { The left eye. }
  SR_LeftEye = 0;
  { The right eye. }
  SR_RightEye = 1;

{ Creates a context. May raise an external exception if the SR service is not
  running.
  @returns(the new context) }
function newSRContext: SRContext; cdecl; external SRCoreDll delayed;
{ Creates a context with an initial lens preference.
  @returns(the new context) }
function newSRContextLensPreference(lensPreference: Boolean): SRContext; cdecl;
  external SRCoreDll delayed;
{ Starts every sense in the context; call after creating them all. }
procedure initializeSRContext(context: SRContext); cdecl; external SRCoreDll delayed;
{ Deletes the context and everything it owns. }
procedure deleteSRContext(context: SRContext); cdecl; external SRCoreDll delayed;
{ Creates the system sense.
  @returns(the sense) }
function createSystemSense(context: SRContext): SR_systemSense; cdecl; external SRCoreDll delayed;
{ Starts calling @code(acceptSystemEventCallback) with system events.
  @returns(the listener, for @link(deleteSystemEventListener)) }
function createSystemEventListener(systemSense: SR_systemSense;
  acceptSystemEventCallback: TSRSystemEventCallback): SR_systemEventListener; cdecl;
  external SRCoreDll delayed;
{ Stops a system event listener. }
procedure deleteSystemEventListener(systemEventListener: SR_systemEventListener); cdecl;
  external SRCoreDll delayed;

{ @returns(the SR platform version, as MAJOR.MINOR.PATCH.HASH) }
function getSRPlatformVersion: PAnsiChar; cdecl; external SRVersionDll delayed;

{ Creates a display object, owned by the context.
  @returns(the display) }
function createDisplay(context: SRContext): SR_display; cdecl; external SRDisplaysDll delayed;
{ @returns(height in pixels as seen by the user) }
function getResolutionHeight(display: SR_display): Integer; cdecl; external SRDisplaysDll delayed;
{ @returns(width in pixels as seen by the user) }
function getResolutionWidth(display: SR_display): Integer; cdecl; external SRDisplaysDll delayed;
{ @returns(height of the panel in pixels) }
function getPhysicalResolutionHeight(display: SR_display): Integer; cdecl;
  external SRDisplaysDll delayed;
{ @returns(width of the panel in pixels) }
function getPhysicalResolutionWidth(display: SR_display): Integer; cdecl;
  external SRDisplaysDll delayed;
{ @returns(height of the active area in centimetres) }
function getPhysicalSizeHeight(display: SR_display): Single; cdecl; external SRDisplaysDll delayed;
{ @returns(width of the active area in centimetres) }
function getPhysicalSizeWidth(display: SR_display): Single; cdecl; external SRDisplaysDll delayed;
{ @returns(distance between pixels in centimetres) }
function getDotPitch(display: SR_display): Single; cdecl; external SRDisplaysDll delayed;
{ @returns(recommended width of each eye's view in pixels) }
function getRecommendedViewsTextureWidth(display: SR_display): Integer; cdecl;
  external SRDisplaysDll delayed;
{ @returns(recommended height of each eye's view in pixels) }
function getRecommendedViewsTextureHeight(display: SR_display): Integer; cdecl;
  external SRDisplaysDll delayed;

{ Creates a lens hint, owned by the context.
  @returns(the hint) }
function createSwitchableLensHint(context: SRContext): SR_switchableLensHint; cdecl;
  external SRDisplaysDll delayed;
{ @returns(@true if the lens is on) }
function isLensEnabled(lensHint: SR_switchableLensHint): Boolean; cdecl;
  external SRDisplaysDll delayed;
{ @returns(@true if any program has asked for the lens to be on) }
function isLensEnabledByPreference(lensHint: SR_switchableLensHint): Boolean; cdecl;
  external SRDisplaysDll delayed;
{ Asks for the lens to be on. }
procedure lensEnableHint(lensHint: SR_switchableLensHint); cdecl; external SRDisplaysDll delayed;
{ Asks for the lens to be off. }
procedure lensDisableHint(lensHint: SR_switchableLensHint); cdecl; external SRDisplaysDll delayed;
{ Drops a lens hint before its context goes away. }
procedure deleteSwitchableLensHint(lensHint: SR_switchableLensHint); cdecl;
  external SRDisplaysDll delayed;

{ Creates an eye tracker.
  @returns(the tracker) }
function createEyeTracker(context: SRContext): SR_eyeTracker; cdecl;
  external SRFaceTrackersDll delayed;
{ Starts calling @code(acceptEyePairCallback) with eye positions.
  @returns(the listener, for @link(deleteEyePairListener)) }
function createEyePairListener(eyeTracker: SR_eyeTracker;
  acceptEyePairCallback: TSREyePairCallback): SR_eyePairListener; cdecl;
  external SRFaceTrackersDll delayed;
{ Stops an eye pair listener. }
procedure deleteEyePairListener(eyePairListener: SR_eyePairListener); cdecl;
  external SRFaceTrackersDll delayed;
{ Creates a head tracker.
  @returns(the tracker) }
function createHeadTracker(context: SRContext): SR_headTracker; cdecl;
  external SRFaceTrackersDll delayed;
{ Starts calling @code(acceptHeadCallback) with head data.
  @returns(the listener, for @link(deleteHeadListener)) }
function createHeadListener(headTracker: SR_headTracker;
  acceptHeadCallback: TSRHeadCallback): SR_headListener; cdecl; external SRFaceTrackersDll delayed;
{ Stops a head listener. }
procedure deleteHeadListener(headListener: SR_headListener); cdecl;
  external SRFaceTrackersDll delayed;
{ Creates a predicting weaver tracker.
  @returns(the tracker) }
function createPredictingWeaverTracker(context: SRContext): SR_predictingWeaverTracker; cdecl;
  external SRFaceTrackersDll delayed;
{ Starts calling @code(acceptWeaverPositionCallback) after each prediction.
  @returns(the listener, for @link(deleteWeaverPositionListener)) }
function createWeaverPositionListener(predictingWeaverTracker: SR_predictingWeaverTracker;
  acceptWeaverPositionCallback: TSRWeaverPositionCallback): SR_weaverPositionListener; cdecl;
  external SRFaceTrackersDll delayed;
{ Stops a weaver position listener. }
procedure deleteWeaverPositionListener(weaverPositionListener: SR_weaverPositionListener); cdecl;
  external SRFaceTrackersDll delayed;
{ Predicts the weaver position @code(latency) microseconds ahead into
  @code(output). }
procedure predictWeaverPositionWithOutput(predictingWeaverTracker: SR_predictingWeaverTracker;
  latency: UInt64; output: PSR_weaverPosition); cdecl; external SRFaceTrackersDll delayed;
{ Predicts the weaver position @code(latency) microseconds ahead for the
  listeners. }
procedure predictWeaverPosition(predictingWeaverTracker: SR_predictingWeaverTracker;
  latency: UInt64); cdecl; external SRFaceTrackersDll delayed;

{ Loads the SR runtime DLLs, if installed.
  @returns(@true if they could be loaded; always @false in a 32-bit build) }
function SRRuntimeAvailable: Boolean;

{ The message of an @link(SR_systemEvent) as a string.
  @param(Event the event)
  @returns(its message) }
function SRSystemEventMessage(const Event: SR_systemEvent): string;

{ A readable name for an event type.
  @param(EventType one of the @code(SR_...) event constants)
  @returns(its name, such as UserLost) }
function SREventTypeName(EventType: SR_eventType): string;

implementation

uses
  Winapi.Windows, System.SysUtils;

function SRRuntimeAvailable: Boolean;
{$IFDEF WIN64}
const
  Dlls: array[0..2] of string = (SRCoreDll, SRDisplaysDll, SRFaceTrackersDll);
var
  Dll: string;
begin
  for Dll in Dlls do
    if SafeLoadLibrary(Dll) = 0 then   // left loaded: the delayed imports reuse it
      Exit(False);
  Result := True;
end;
{$ELSE}
begin
  Result := False;
end;
{$ENDIF}

function SRSystemEventMessage(const Event: SR_systemEvent): string;
var
  Bytes: TBytes;
begin
  if (Event.message = nil) or (Event.messageLength = 0) then
    Exit('');
  SetLength(Bytes, Event.messageLength);
  System.Move(Event.message^, Bytes[0], Event.messageLength);
  Result := TEncoding.UTF8.GetString(Bytes);
end;

function SREventTypeName(EventType: SR_eventType): string;
const
  Names: array[0..17] of string = (
    'Info', 'ContextInvalid', 'SRUnavailable', 'SRRestored',
    'USBNotConnected', 'USBNotConnectedResolved',
    'DisplayNotConnected', 'DisplayNotConnectedResolved',
    'Duplicated', 'DuplicatedResolved',
    'NonNativeResolution', 'NonNativeResolutionResolved',
    'DeviceConnectedAndReady', 'DeviceDisconnected',
    'LensOn', 'LensOff', 'UserFound', 'UserLost');
begin
  if EventType <= High(Names) then
    Result := Names[EventType]
  else
    Result := 'Event' + UIntToStr(EventType);
end;

end.

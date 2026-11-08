//** @abstract(TLenticularDisplay: starts and stops a lenticular (glasses-free 3D) display for
//** a view on a form, and reports the display and the viewer's eyes.)
//**
//** The first of the Lenticular components, in the Lenticular package. It does what the
//** stereo renderer (Lenticular.StereoViewport) does to get the display going, without drawing
//** anything:
//**
//** @unorderedList(
//**   @item(Whether this computer has the display runtime at all (Installed). Where it has
//**     not, Start does nothing and raises no event: a program can hide everything to do with
//**     glasses-free 3D and run as if it had no glasses-free 3D support.)
//**   @item(Start checks for the display service and the display on a background thread (the
//**     bridge's lnb_Probe), so waiting for them never freezes the window, then starts the
//**     display on the main thread (lnb_Initialize), with the bridge's own window over Control.)
//**   @item(While running: the display, where Control lies on it in millimetres, the tracked
//**     eye positions and the runtime's events, in the log (OnLog) and through OnEyes.)
//**   @item(The user's settings, kept by Settings, shared by every Peardox program.)
//** )
//**
//** It weaves nothing itself: a renderer draws the two eyes' views, sets Weaving (the bridge's
//** window then covers Control and the lens comes on) and hands each frame to SubmitViews.
//** Until then the window stays hidden and the lens off, so Control shows what it always
//** shows.
//**
//** The display runtime is Windows 64-bit only. The unit compiles everywhere so the package
//** and the programs using it stay cross-platform; elsewhere Installed is False and Start does
//** nothing. It needs LenticularBridge.dll (the bridge, from the dll folder) beside the executable.
//** One per program: the bridge drives a single 3D view.
unit Lenticular.Display;

{
  TLenticularDisplay: starts and stops a lenticular (glasses-free 3D)
  display for a view on a form, and reports the display and the viewer's
  eyes.

  The first of the Lenticular components, in the Lenticular package. It
  does what the stereo renderer (Lenticular.StereoViewport) does to get the display going,
  without drawing anything: whether the display runtime is installed; a
  background check for the display service and the display, then the
  display started on the main thread with the bridge's window over
  Control; while running, the display, the view's place on it in
  millimetres, the tracked eyes and the runtime's events; and the user's
  settings, shared by every Peardox program.

  It weaves nothing itself: a renderer sets Weaving and hands each frame to
  SubmitViews; until then the bridge's window stays hidden and the lens off.

  The display runtime is Windows 64-bit only; the unit compiles everywhere,
  and elsewhere Installed is False and Start does nothing. It needs
  LenticularBridge.dll (the bridge, from the dll folder) beside the executable.
}

interface

uses
  System.SysUtils, System.Classes, System.Types, System.Math.Vectors,
  {$IFDEF MSWINDOWS}
  Winapi.Windows, Winapi.Messages,
  {$ENDIF}
  FMX.Types, FMX.Controls,
  LenticularBridge.Api, Lenticular.Display.Settings;

const
  //** @abstract(TLenticularDisplay.DisplayName while the display's own name is not known.)
  LENTICULAR_DISPLAY_DEFAULT_NAME = 'the 3D display';
  //** @abstract(The platforms the Lenticular components are offered for in the IDE: all of them,
  //** so a form using one compiles everywhere; the display itself runs on Windows 64-bit only.)
  LENTICULAR_DISPLAY_PLATFORMS = pidAllPlatforms;
  //** @abstract(Default for TLenticularDisplay.InitTimeout, in seconds, as the stereo renderer's.)
  LENTICULAR_DISPLAY_INIT_TIMEOUT = 5.0;
  //** @abstract(Default for TLenticularDisplay.PollInterval, in milliseconds.)
  LENTICULAR_DISPLAY_POLL_INTERVAL = 100;
  //** @abstract(Default for TLenticularDisplay.LogInterval, in milliseconds, as the stereo
  //** renderer's.)
  LENTICULAR_DISPLAY_LOG_INTERVAL = 1000;

type
  //** @abstract(Why glasses-free 3D did not start, as TLenticularDisplay.Problem.)
  TLenticularDisplayProblem = (
    //** @abstract(No problem.)
    ldpNone,
    //** @abstract(This computer has no display runtime, or this platform has no glasses-free 3D at
    //** all. Not an error: nothing is said to the user.)
    ldpNotInstalled,
    //** @abstract(A 32-bit Windows build: the display runtime is 64-bit only.)
    ldpNotWin64,
    //** @abstract(LenticularBridge.dll could not be loaded.)
    ldpBridgeMissing,
    //** @abstract(The display runtime is installed but its service is not running.)
    ldpNoService,
    //** @abstract(The display service is running but no 3D display was found.)
    ldpNoDisplay,
    //** @abstract(Control is not set, or not on a form that is showing.)
    ldpNoForm,
    //** @abstract(The display would not start for another reason; the message says which.)
    ldpStartFailed);

  //** @abstract(Where TLenticularDisplay is, as its State.)
  TLenticularDisplayState = (
    //** @abstract(Not running, not starting.)
    ldsOff,
    //** @abstract(Waiting for the background check of the display service and display.)
    ldsChecking,
    //** @abstract(The display is running.)
    ldsRunning);

  //** @abstract(The display's lens, as TLenticularDisplay.LensState.)
  TLenticularDisplayLensState = (
    //** @abstract(Not known: the display is not running, or has not said yet.)
    ldlUnknown,
    //** @abstract(On: everything on the 3D display is seen through the lens, and what is not
    //** woven looks blurred.)
    ldlOn,
    //** @abstract(Off: the display is an ordinary flat screen.)
    ldlOff);

  //** @abstract(A line for the log.)
  //**
  //** @param(Sender The TLenticularDisplay.)
  //**
  //** @param(AText The line.)
  TLenticularDisplayLogEvent = procedure(Sender: TObject; const AText: string) of object;

  //** @abstract(Glasses-free 3D could not start, for a reason the user should hear about.)
  //**
  //** @param(Sender The TLenticularDisplay.)
  //**
  //** @param(AProblem What went wrong.)
  //**
  //** @param(AMessage The details, for the user.)
  TLenticularDisplayProblemEvent = procedure(Sender: TObject; AProblem: TLenticularDisplayProblem;
    const AMessage: string) of object;

  //** @abstract(New eye positions from the tracker.)
  //**
  //** @param(Sender The TLenticularDisplay.)
  //**
  //** @param(ALeftMM The left eye, in millimetres from the display's centre: x right, y up, z
  //** towards the viewer.)
  //**
  //** @param(ARightMM The right eye, likewise.)
  TLenticularDisplayEyesEvent = procedure(Sender: TObject;
    const ALeftMM, ARightMM: TPoint3D) of object;

  //** @abstract(Starts and stops the lenticular display for a view on a form, and reports the
  //** display and the viewer's eyes; see the unit description.)
  //**
  //** Drop it on a form or create it in code, set Control to the view (the Gorilla3D viewport) and
  //** OnLog, then call Start once the form is showing, and Stop before the form closes.
  [ComponentPlatformsAttribute(LENTICULAR_DISPLAY_PLATFORMS)]
  TLenticularDisplay = class(TComponent)
  private
    //** @abstract(See Control.)
    FControl: TControl;
    //** @abstract(See Settings.)
    FSettings: TLenticularDisplaySettings;
    //** @abstract(See SettingsStatus.)
    FSettingsStatus: string;
    //** @abstract(See State.)
    FState: TLenticularDisplayState;
    //** @abstract(See Problem.)
    FProblem: TLenticularDisplayProblem;
    //** @abstract(See InitTimeout.)
    FInitTimeout: Single;
    //** @abstract(See PollInterval.)
    FPollInterval: Integer;
    //** @abstract(See LogInterval.)
    FLogInterval: Integer;
    //** @abstract(Polls the bridge while the display runs; made at run time only.)
    FTimer: TTimer;
    //** @abstract(See LeftEyeMM.)
    FLeftEyeMM: TPoint3D;
    //** @abstract(See RightEyeMM.)
    FRightEyeMM: TPoint3D;
    //** @abstract(See EyesTracked.)
    FEyesTracked: Boolean;
    //** @abstract(See WindowCenterMM.)
    FWindowCenterMM: TPointF;
    //** @abstract(See WindowSizeMM.)
    FWindowSizeMM: TSizeF;
    //** @abstract(See DisplayName.)
    FDisplayName: string;
    //** @abstract(Control's rectangle last given to the bridge, in physical pixels in the
    //** form's client area; empty until set.)
    FBounds: TRect;
    //** @abstract(When Start was called, for the log's timings (TThread.GetTickCount64).)
    FStartTick: UInt64;
    //** @abstract(When the last periodic log lines were written.)
    FLastLogTick: UInt64;
    //** @abstract(See OnLog.)
    FOnLog: TLenticularDisplayLogEvent;
    //** @abstract(See OnStarted.)
    FOnStarted: TNotifyEvent;
    //** @abstract(See OnStopped.)
    FOnStopped: TNotifyEvent;
    //** @abstract(See OnProblem.)
    FOnProblem: TLenticularDisplayProblemEvent;
    //** @abstract(See OnEyes.)
    FOnEyes: TLenticularDisplayEyesEvent;
    //** @abstract(See LensState.)
    FLensState: TLenticularDisplayLensState;
    //** @abstract(See OnLensChange.)
    FOnLensChange: TNotifyEvent;
    //** @abstract(True when the bridge has lnb_GetLensState, so the lens is read, not only
    //** followed through the runtime's events.)
    FCanReadLens: Boolean;
    //** @abstract(See Weaving.)
    FWeaving: Boolean;
    //** @abstract(See Flat.)
    FFlat: Boolean;
    //** @abstract(SubmitViews calls since the last periodic log line.)
    FSubmits: Integer;
    //** @abstract(Of FSubmits: woven, shown flat (The display unavailable), hidden window, failed.)
    FSubmitResults: array[0..3] of Integer;
    {$IFDEF MSWINDOWS}
    //** @abstract(A hidden window the background check posts its answer to: posted messages
    //** come ahead of paints, while a queued call waits until FMX is idle.)
    FMsgWnd: HWND;
    //** @abstract(The form's window, the parent of the bridge's own.)
    FFormWnd: HWND;
    //** @abstract(The background check's thread, kept to wait for it when freed; nil when none
    //** has run.)
    FProbe: TThread;
    {$ENDIF}
    //** @abstract(Sets Control, watching for it being freed.)
    //**
    //** @param(AValue The new view, or nil.)
    procedure SetControl(const AValue: TControl);
    //** @abstract(Sets PollInterval, at least 10 ms.)
    //**
    //** @param(AValue Milliseconds.)
    procedure SetPollInterval(const AValue: Integer);
    //** @abstract(Whether InitTimeout differs from its default and so is written to the .fmx.)
    //**
    //** @returns(True if it is not LENTICULAR_DISPLAY_INIT_TIMEOUT.)
    function StoreInitTimeout: Boolean;
    //** @abstract(Read by Running.)
    //**
    //** @returns(True while State is ldsRunning.)
    function GetRunning: Boolean;
    //** @abstract(FTimer's tick while the display runs: the runtime's events, Control's place, the
    //** eyes, and the periodic log lines.)
    //**
    //** @param(Sender FTimer.)
    procedure TimerTick(Sender: TObject);
    //** @abstract(Ends a start that failed: State back to ldsOff, Problem set, the reason
    //** logged and, when the user should hear of it, OnProblem.)
    //**
    //** @param(AProblem What went wrong.)
    //**
    //** @param(AMessage The details.)
    //**
    //** @param(ATell Whether to raise OnProblem; False for ldpNotInstalled.)
    procedure Fail(AProblem: TLenticularDisplayProblem; const AMessage: string; ATell: Boolean);
    //** @abstract(Sets Weaving: shows or hides the bridge's window over Control, with the
    //** lens on or off.)
    //**
    //** @param(AValue True to weave.)
    procedure SetWeaving(const AValue: Boolean);
    //** @abstract(Sets Flat: the lens off while weaving if True, on if False.)
    //**
    //** @param(AValue True for flat.)
    procedure SetFlat(const AValue: Boolean);
    //** @abstract(Sets LensState, logging and raising OnLensChange when it changes.)
    //**
    //** @param(AValue The lens's new state.)
    //**
    //** @param(AWhy What says so, for the log.)
    procedure SetLensState(AValue: TLenticularDisplayLensState; const AWhy: string);
    //** @abstract(Counts a weave's result for the once-a-second line, logging the first
    //** failure.)
    //**
    //** @param(AResult The bridge's answer.)
    //**
    //** @param(AWhat The call, for the log.)
    procedure CountSubmit(AResult: Integer; const AWhat: string);
    {$IFDEF MSWINDOWS}
    //** @abstract(Finds the window of the form Control is on.)
    //**
    //** @param(AWnd Set to the form's window.)
    //**
    //** @param(AWhy Set to why there is none, for the log.)
    //**
    //** @returns(True if Control is on a form that has its window, shown or hidden.)
    function FindFormWindow(out AWnd: HWND; out AWhy: string): Boolean;
    //** @abstract(FMsgWnd's window procedure: takes the background check's answer.)
    //**
    //** @param(AMessage The message.)
    procedure MsgWndProc(var AMessage: Winapi.Messages.TMessage);
    //** @abstract(The background check's answer: starts the display if it is there, or fails the
    //** start with the reason.)
    //**
    //** @param(ARC What lnb_Probe returned.)
    procedure ProbeDone(ARC: Integer);
    //** @abstract(Starts the display on this thread (lnb_Initialize), hides the bridge's window and
    //** turns the lens off, as nothing is woven yet, and starts polling.)
    //**
    //** @returns(True if the display is running.)
    function Initialize: Boolean;
    //** @abstract(Gives the bridge Control's rectangle when it has changed, and logs where it
    //** lies on the 3D display whenever that changes.)
    procedure UpdateBounds;
    //** @abstract(Logs every runtime event waiting in the bridge, and follows the lens's
    //** state from its LensOn and LensOff events.)
    procedure PollEvents;
    //** @abstract(Reads the lens's actual state from the bridge (lnb_GetLensState), where it
    //** can.)
    procedure ReadLens;
    //** @abstract(Reads the tracked eyes, logs when tracking is found or lost, and raises
    //** OnEyes.)
    procedure ReadEyes;
    //** @abstract(Logs the display runtime, the display and the settings once the display has
    //** started.)
    procedure LogStartDetails;
    {$ENDIF}
  protected
    //** @abstract(Forgets Control when it is freed, stopping the display first.)
    //**
    //** @param(AComponent The component going or coming.)
    //**
    //** @param(Operation Whether it is being inserted or removed.)
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
    //** @abstract(Passes a line to OnLog, unless the component is being destroyed.)
    //**
    //** @param(AText The line.)
    procedure Log(const AText: string);
  public
    //** @abstract(Creates the component and, at run time, reads Settings and makes the timer
    //** and the hidden message window.)
    //**
    //** @param(AOwner The owner, normally the form.)
    constructor Create(AOwner: TComponent); override;
    //** @abstract(Stops the display, waits for a background check still running, and frees
    //** everything.)
    destructor Destroy; override;
    //** @abstract(Whether glasses-free 3D can be offered here: a Windows 64-bit build on a
    //** computer with the display runtime installed.)
    //**
    //** Quick and safe anywhere: it loads the bridge (LenticularBridge.dll), which looks for the
    //** runtime's DLLs without running them, and never loads the runtime itself. Without the
    //** bridge beside the executable it is False. It says nothing about whether the display
    //** service is running or a display connected; Start finds that out.
    //**
    //** @returns(True if the display runtime is installed and this build can use it.)
    class function Installed: Boolean;
    //** @abstract(Starts glasses-free 3D.)
    //**
    //** Returns at once. Where the display runtime is not installed it does nothing more, raising
    //** no event. Otherwise the display service and display are checked on a background thread, for
    //** up to InitTimeout seconds; when they are there the display is started (OnStarted), and when
    //** not, or if anything else goes wrong, OnProblem says why. Call it once the form is showing.
    //**
    //** @returns(True if the display is starting or already running; False if it cannot start, with
    //** the reason in Problem and the log.)
    function Start: Boolean;
    //** @abstract(Stops glasses-free 3D (OnStopped if it was running); a background check
    //** still under way is let finish and its answer ignored.)
    procedure Stop;
    //** @abstract(Saves Settings, logging where to or why not.)
    procedure SaveSettings;
    //** @abstract(Sets Settings.LatencyFrames and, while running, tells the weaver at once.)
    //**
    //** The weaver predicts where the eyes will be when a frame reaches the display, this many
    //** frames after it was drawn; a renderer that reads its pictures back through the CPU is
    //** a frame or two behind. 0 keeps whatever was told last (the runtime's own until then). Not
    //** saved: call SaveSettings for that.
    //**
    //** @param(AFrames Frames of latency, 0 to 10.)
    procedure SetLatencyFrames(AFrames: Integer);
    //** @abstract(Sets Settings.FrameCap and, while running, tells the bridge at once.)
    //**
    //** Not saved: call SaveSettings for that.
    //**
    //** @param(AOn True to wait for the 3D display's vertical blank after each frame, False
    //** not to.)
    procedure SetFrameCap(AOn: Boolean);
    //** @abstract(Reads the tracked eyes now, rather than waiting for the next poll; for a
    //** renderer about to draw a frame. Raises OnEyes.)
    //**
    //** @returns(True if the display is running and the bridge answered.)
    function UpdateEyes: Boolean;
    //** @abstract(Zero copy: weaves two eye textures already on the bridge's device
    //** (BridgeDevice), copying them on the GPU (lnb_CopyEyeTexture, lnb_PresentViews); the
    //** results are counted and logged as SubmitViews's.)
    //**
    //** @param(ALeft The left eye's ID3D11Texture2D, AViewWidth x AViewHeight.)
    //**
    //** @param(ARight The right eye's.)
    //**
    //** @param(AViewWidth Width of each view in pixels.)
    //**
    //** @param(AViewHeight Height in pixels.)
    //**
    //** @returns(As SubmitViews.)
    function SubmitEyeTextures(ALeft, ARight: Pointer; AViewWidth, AViewHeight: Integer): Integer;
    //** @abstract(The bridge's Direct3D 11 device while the display runs, for making eye textures
    //** on for SubmitEyeTextures; nil when not running or the bridge is older than
    //** lnb_GetDevice. Not AddRef'd: valid until the display stops.)
    //**
    //** @returns(An ID3D11Device, or nil.)
    function BridgeDevice: Pointer;
    //** @abstract(Weaves and presents one frame: a side-by-side image, the left eye's view in
    //** the left half, the right eye's in the right.)
    //**
    //** Only while Weaving. The bridge stretches each view to its window over Control. The
    //** results are counted and summed up in the periodic log line.
    //**
    //** @param(APixels The image: AViewHeight rows of 2 * AViewWidth pixels, 4 bytes each.)
    //**
    //** @param(AViewWidth Width of ONE eye's view in pixels.)
    //**
    //** @param(AViewHeight Height in pixels.)
    //**
    //** @param(APitch Bytes from one row to the next.)
    //**
    //** @param(ARGBA True if the bytes are red, green, blue, alpha; False (the default) for
    //** blue, green, red, alpha, as FMX bitmaps on Windows.)
    //**
    //** @returns(The bridge's answer: LNB_OK (woven), LNB_S_2D_FALLBACK, LNB_S_OCCLUDED, or a
    //** negative error; LNB_E_NOT_INITIALIZED while not Weaving.)
    function SubmitViews(APixels: Pointer; AViewWidth, AViewHeight, APitch: Integer;
      ARGBA: Boolean = False): Integer;
    //** @abstract(The 3D display's properties, while the display runs.)
    //**
    //** @param(AInfo Set to the display's resolutions, size and recommended view size.)
    //**
    //** @returns(True if the display is running and the bridge answered.)
    function DisplayInfo(out AInfo: TLNBDisplayInfo): Boolean;
    //** @abstract(Where the 3D display is on the desktop, while the display runs.)
    //**
    //** @param(ARect Set to the display's rectangle in physical (desktop) pixels; empty if
    //** not known.)
    //**
    //** @returns(True if the display is running and the bridge knows where the display is.)
    function DisplayRect(out ARect: TRect): Boolean;
    //** @abstract(Where the component is: off, checking or running.)
    property State: TLenticularDisplayState read FState;
    //** @abstract(True while the display is running.)
    property Running: Boolean read GetRunning;
    //** @abstract(Why the last Start did not start the display; ldpNone otherwise.)
    property Problem: TLenticularDisplayProblem read FProblem;
    //** @abstract(The left eye, in millimetres from the display's centre (x right, y up, z
    //** towards the viewer), as last read while the display ran.)
    property LeftEyeMM: TPoint3D read FLeftEyeMM;
    //** @abstract(The right eye, likewise.)
    property RightEyeMM: TPoint3D read FRightEyeMM;
    //** @abstract(True while the tracker has the viewer's eyes; False before it finds them,
    //** when the display reports both eyes at one point.)
    property EyesTracked: Boolean read FEyesTracked;
    //** @abstract(The display's lens: read from the display at every poll (lnb_GetLensState, when
    //** the bridge has it), else as the display last reported it in its LensOn and LensOff
    //** events; ldlUnknown while the display is not running and until it is known. OnLensChange
    //** tells of each change.)
    property LensState: TLenticularDisplayLensState read FLensState;
    //** @abstract(Control's centre on the 3D display, in millimetres from the display's centre,
    //** x right and y up, as last read while the display ran.)
    property WindowCenterMM: TPointF read FWindowCenterMM;
    //** @abstract(Control's size on the 3D display, in millimetres.)
    property WindowSizeMM: TSizeF read FWindowSizeMM;
    //** @abstract(The 3D display's make and model as Windows names it from the monitor's EDID
    //** (as Settings, Display shows it), with the maker put in front from its EDID code where
    //** the name leaves it out; LENTICULAR_DISPLAY_DEFAULT_NAME until the display has started, or
    //** where Windows does not say.)
    property DisplayName: string read FDisplayName;
    //** @abstract(The user's saved display settings, read when the component is made at run
    //** time; change them and call SaveSettings.)
    property Settings: TLenticularDisplaySettings read FSettings;
    //** @abstract(What happened when Settings were read, for the program's log: the file read,
    //** or why the defaults are used.)
    property SettingsStatus: string read FSettingsStatus;
    //** @abstract(True while frames are woven: the bridge's window covers Control and the
    //** display's lens is on. Set it when a renderer starts handing frames to SubmitViews, and
    //** clear it when it stops; only possible while Running, and cleared by Stop.)
    property Weaving: Boolean read FWeaving write SetWeaving;
    //** @abstract(True to keep the display's lens off while Weaving, for a renderer that hands
    //** the same view to both eyes: an ordinary flat picture, which a screen recording can
    //** catch. False (the default) for glasses-free 3D. It can be changed while weaving.)
    property Flat: Boolean read FFlat write SetFlat;
  published
    //** @abstract(The view the display is for: the bridge's window is put over it, and its place on
    //** the display is what the eyes will look through. Normally the Gorilla3D viewport.)
    property Control: TControl read FControl write SetControl;
    //** @abstract(Seconds to wait for the display service and display when starting; default
    //** LENTICULAR_DISPLAY_INIT_TIMEOUT.)
    property InitTimeout: Single read FInitTimeout write FInitTimeout stored StoreInitTimeout;
    //** @abstract(Milliseconds between polls of the bridge while the display runs; default
    //** LENTICULAR_DISPLAY_POLL_INTERVAL.)
    property PollInterval: Integer read FPollInterval write SetPollInterval
      default LENTICULAR_DISPLAY_POLL_INTERVAL;
    //** @abstract(Milliseconds between the periodic log lines (eyes, view) while the display runs;
    //** 0 for none. Default LENTICULAR_DISPLAY_LOG_INTERVAL.)
    property LogInterval: Integer read FLogInterval write FLogInterval
      default LENTICULAR_DISPLAY_LOG_INTERVAL;
    //** @abstract(Every line of the log: the start, the display, the runtime's events, the eyes,
    //** the bridge's own lines (prefixed [bridge]) and failures. On the main thread.)
    property OnLog: TLenticularDisplayLogEvent read FOnLog write FOnLog;
    //** @abstract(The display has started.)
    property OnStarted: TNotifyEvent read FOnStarted write FOnStarted;
    //** @abstract(The display has stopped, after running.)
    property OnStopped: TNotifyEvent read FOnStopped write FOnStopped;
    //** @abstract(Glasses-free 3D could not start for a reason the user should hear about;
    //** not raised where the display runtime is simply not installed.)
    property OnProblem: TLenticularDisplayProblemEvent read FOnProblem write FOnProblem;
    //** @abstract(New eye positions, at every poll while the display runs.)
    property OnEyes: TLenticularDisplayEyesEvent read FOnEyes write FOnEyes;
    //** @abstract(LensState has changed: the lens has come on or gone off, or the display has
    //** stopped and it is no longer known.)
    property OnLensChange: TNotifyEvent read FOnLensChange write FOnLensChange;
  end;

implementation

uses
  System.Math, System.StrUtils,
  {$IFDEF MSWINDOWS}
  FMX.Platform.Win,
  {$ENDIF}
  FMX.Forms;

{$IFDEF MSWINDOWS}
const
  //** @abstract(Posted to the hidden window with the background check's answer in WParam.)
  WM_LENTICULAR_DISPLAY_PROBED = WM_APP + $51;

var
  //** @abstract(The component the bridge's log lines go to; nil when none. The bridge drives
  //** one 3D view per process, so there is one.)
  GBridgeLogOwner: TLenticularDisplay = nil;

// Windows' display configuration API, for the monitor's own name: declared
// here, laid out as in wingdi.h, as not every Delphi declares them
const
  //** @abstract(QueryDisplayConfig: the paths in use.)
  PDX_QDC_ONLY_ACTIVE_PATHS = $00000002;
  //** @abstract(DisplayConfigGetDeviceInfo: a source's GDI name (\\.\DISPLAYn).)
  PDX_DC_GET_SOURCE_NAME = 1;
  //** @abstract(DisplayConfigGetDeviceInfo: a target's (monitor's) names.)
  PDX_DC_GET_TARGET_NAME = 2;
  //** @abstract(DISPLAYCONFIG_TARGET_DEVICE_NAME flags: the EDID maker and product are valid.)
  PDX_DC_EDID_IDS_VALID = $4;
  //** @abstract(MonitorFromPoint: nil where no monitor holds the point.)
  PDX_MONITOR_DEFAULTTONULL = 0;

type
  //** @abstract(LUID.)
  TPdxDCLuid = record
    LowPart: DWORD;
    HighPart: Longint;
  end;
  //** @abstract(DISPLAYCONFIG_PATH_SOURCE_INFO, 20 bytes.)
  TPdxDCPathSource = record
    AdapterId: TPdxDCLuid;
    Id: Cardinal;
    ModeInfoIdx: Cardinal;
    StatusFlags: Cardinal;
  end;
  //** @abstract(DISPLAYCONFIG_PATH_TARGET_INFO, 48 bytes.)
  TPdxDCPathTarget = record
    AdapterId: TPdxDCLuid;
    Id: Cardinal;
    ModeInfoIdx: Cardinal;
    OutputTechnology: Cardinal;
    Rotation: Cardinal;
    Scaling: Cardinal;
    RefreshNumerator: Cardinal;
    RefreshDenominator: Cardinal;
    ScanLineOrdering: Cardinal;
    TargetAvailable: LongBool;
    StatusFlags: Cardinal;
  end;
  //** @abstract(DISPLAYCONFIG_PATH_INFO, 72 bytes.)
  TPdxDCPath = record
    Source: TPdxDCPathSource;
    Target: TPdxDCPathTarget;
    Flags: Cardinal;
  end;
  //** @abstract(DISPLAYCONFIG_MODE_INFO, 64 bytes, not looked into.)
  TPdxDCMode = array[0..63] of Byte;
  //** @abstract(DISPLAYCONFIG_DEVICE_INFO_HEADER, 20 bytes.)
  TPdxDCHeader = record
    InfoType: Cardinal;
    Size: Cardinal;
    AdapterId: TPdxDCLuid;
    Id: Cardinal;
  end;
  //** @abstract(DISPLAYCONFIG_SOURCE_DEVICE_NAME, 84 bytes.)
  TPdxDCSourceName = record
    Header: TPdxDCHeader;
    GdiName: array[0..31] of WideChar;
  end;
  //** @abstract(DISPLAYCONFIG_TARGET_DEVICE_NAME, 420 bytes.)
  TPdxDCTargetName = record
    Header: TPdxDCHeader;
    Flags: Cardinal;
    OutputTechnology: Cardinal;
    EdidManufactureId: Word;
    EdidProductCodeId: Word;
    ConnectorInstance: Cardinal;
    FriendlyName: array[0..63] of WideChar;
    DevicePath: array[0..127] of WideChar;
  end;
  //** @abstract(MONITORINFOEXW.)
  TPdxMonitorInfoEx = record
    Size: DWORD;
    Monitor: TRect;
    Work: TRect;
    Flags: DWORD;
    Device: array[0..31] of WideChar;
  end;

function PdxGetDisplayConfigBufferSizes(Flags: Cardinal; out NumPaths, NumModes: Cardinal): Longint;
  stdcall; external user32 name 'GetDisplayConfigBufferSizes';
function PdxQueryDisplayConfig(Flags: Cardinal; var NumPaths: Cardinal; Paths: Pointer;
  var NumModes: Cardinal; Modes: Pointer; TopologyId: Pointer): Longint; stdcall;
  external user32 name 'QueryDisplayConfig';
function PdxDisplayConfigGetDeviceInfo(Packet: Pointer): Longint; stdcall;
  external user32 name 'DisplayConfigGetDeviceInfo';
function PdxMonitorFromPoint(Pt: TPoint; Flags: DWORD): THandle; stdcall;
  external user32 name 'MonitorFromPoint';
function PdxGetMonitorInfo(Monitor: THandle; Info: Pointer): BOOL; stdcall;
  external user32 name 'GetMonitorInfoW';

//** @abstract(A maker's name from its three-letter EDID (PnP) code, for the makers of 3D
//** displays and a few others.)
//**
//** @param(ACode The code, as SAM.)
//**
//** @returns(The maker, or the code itself for one not known here.)
function MakerName(const ACode: string): string;
const
  Codes: array[0..9, 0..1] of string = (('SAM', 'Samsung'), ('SEC', 'Samsung'),
    ('ACR', 'Acer'), ('LEN', 'Lenovo'), ('AUS', 'ASUS'), ('ASU', 'ASUS'), ('DEL', 'Dell'),
    ('LGD', 'LG'), ('GSM', 'LG'), ('BOE', 'BOE'));
var
  I: Integer;
begin
  for I := Low(Codes) to High(Codes) do
    if Codes[I, 0] = ACode then
      Exit(Codes[I, 1]);
  Result := ACode;
end;

//** @abstract(The make and model of the monitor at a point of the desktop, as Windows names
//** it from the monitor's EDID.)
//**
//** @param(APoint A point on the monitor, desktop pixels.)
//**
//** @returns(Its name, with the maker in front where the name leaves it out; empty if
//** Windows does not say.)
function MonitorNameAt(const APoint: TPoint): string;
var
  Mon: THandle;
  MI: TPdxMonitorInfoEx;
  NumPaths, NumModes: Cardinal;
  Paths: TArray<TPdxDCPath>;
  Modes: TArray<TPdxDCMode>;
  I: Integer;
  SrcName: TPdxDCSourceName;
  TgtName: TPdxDCTargetName;
  Id: Word;
  Maker: string;
begin
  Result := '';
  Mon := PdxMonitorFromPoint(APoint, PDX_MONITOR_DEFAULTTONULL);
  if Mon = 0 then
    Exit;
  FillChar(MI, SizeOf(MI), 0);
  MI.Size := SizeOf(MI);
  if not PdxGetMonitorInfo(Mon, @MI) then
    Exit;
  if (PdxGetDisplayConfigBufferSizes(PDX_QDC_ONLY_ACTIVE_PATHS, NumPaths, NumModes) <> 0) or
    (NumPaths = 0) or (NumModes = 0) then
    Exit;
  SetLength(Paths, NumPaths);
  SetLength(Modes, NumModes);
  if PdxQueryDisplayConfig(PDX_QDC_ONLY_ACTIVE_PATHS, NumPaths, @Paths[0], NumModes,
    @Modes[0], nil) <> 0 then
    Exit;
  for I := 0 to Integer(NumPaths) - 1 do
  begin
    FillChar(SrcName, SizeOf(SrcName), 0);
    SrcName.Header.InfoType := PDX_DC_GET_SOURCE_NAME;
    SrcName.Header.Size := SizeOf(SrcName);
    SrcName.Header.AdapterId := Paths[I].Source.AdapterId;
    SrcName.Header.Id := Paths[I].Source.Id;
    if (PdxDisplayConfigGetDeviceInfo(@SrcName) <> 0) or
      not SameText(string(PWideChar(@SrcName.GdiName[0])), string(PWideChar(@MI.Device[0]))) then
      Continue;
    FillChar(TgtName, SizeOf(TgtName), 0);
    TgtName.Header.InfoType := PDX_DC_GET_TARGET_NAME;
    TgtName.Header.Size := SizeOf(TgtName);
    TgtName.Header.AdapterId := Paths[I].Target.AdapterId;
    TgtName.Header.Id := Paths[I].Target.Id;
    if PdxDisplayConfigGetDeviceInfo(@TgtName) <> 0 then
      Exit;
    Result := Trim(string(PWideChar(@TgtName.FriendlyName[0])));
    if (TgtName.Flags and PDX_DC_EDID_IDS_VALID) <> 0 then
    begin
      // Three letters of five bits each, A = 1, the bytes swapped
      Id := Swap(TgtName.EdidManufactureId);
      Maker := MakerName(Char(Ord('A') - 1 + ((Id shr 10) and 31)) +
        Char(Ord('A') - 1 + ((Id shr 5) and 31)) + Char(Ord('A') - 1 + (Id and 31)));
      if Result = '' then
        Result := Maker
      else if not ContainsText(Result, Maker) then
        Result := Maker + ' ' + Result;
    end;
    Exit;
  end;
end;

//** @abstract(Receives the bridge's log lines, on any thread, and passes them to the main
//** thread's log.)
//**
//** @param(Line The line, zero-terminated UTF-8.)
procedure BridgeLogCallback(Line: PAnsiChar); cdecl;
var
  Text: string;
begin
  try
    Text := UTF8ToString(Line);
    TThread.Queue(nil,
      procedure
      begin
        if GBridgeLogOwner <> nil then
          GBridgeLogOwner.Log('[bridge] ' + Text);
      end);
  except
    // Never let an exception back into the bridge's C++
  end;
end;
{$ENDIF}

//** @abstract(A point for the log.)
//**
//** @param(P The point, in millimetres.)
//**
//** @returns(Its coordinates to one place, in brackets.)
function FmtMM(const P: TPoint3D): string;
begin
  Result := Format('(%.1f, %.1f, %.1f)', [P.X, P.Y, P.Z]);
end;

{ TLenticularDisplay }

constructor TLenticularDisplay.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FInitTimeout := LENTICULAR_DISPLAY_INIT_TIMEOUT;
  FDisplayName := LENTICULAR_DISPLAY_DEFAULT_NAME;
  FPollInterval := LENTICULAR_DISPLAY_POLL_INTERVAL;
  FLogInterval := LENTICULAR_DISPLAY_LOG_INTERVAL;
  FSettings := TLenticularDisplaySettings.Create;
  if csDesigning in ComponentState then
    Exit;
  if FSettings.Load then
    FSettingsStatus := 'Display settings read from ' + FSettings.FileName
  else
    FSettingsStatus := Format('Display settings: %s, defaults used (%s)',
      [FSettings.LastError, FSettings.FileName]);
  FTimer := TTimer.Create(Self);
  FTimer.Enabled := False;
  FTimer.Interval := FPollInterval;
  FTimer.OnTimer := TimerTick;
  {$IFDEF MSWINDOWS}
  FMsgWnd := AllocateHWnd(MsgWndProc);
  {$ENDIF}
end;

destructor TLenticularDisplay.Destroy;
begin
  {$IFDEF MSWINDOWS}
  // The bridge's lines from here on go nowhere: the owner may be half gone
  if GBridgeLogOwner = Self then
    GBridgeLogOwner := nil;
  {$ENDIF}
  Stop;
  {$IFDEF MSWINDOWS}
  // A check still under way must finish before the bridge is unloaded
  if FProbe <> nil then
  begin
    FProbe.WaitFor;
    FreeAndNil(FProbe);
  end;
  if FMsgWnd <> 0 then
    DeallocateHWnd(FMsgWnd);
  {$ENDIF}
  FSettings.Free;
  inherited Destroy;
end;

procedure TLenticularDisplay.Notification(AComponent: TComponent; Operation: TOperation);
begin
  inherited Notification(AComponent, Operation);
  if (Operation = opRemove) and (AComponent = FControl) then
  begin
    if FState <> ldsOff then
    begin
      Log('Control is being freed: stopping the display');
      Stop;
    end;
    FControl := nil;
  end;
end;

procedure TLenticularDisplay.SetControl(const AValue: TControl);
begin
  if AValue = FControl then
    Exit;
  if FControl <> nil then
    FControl.RemoveFreeNotification(Self);
  FControl := AValue;
  if FControl <> nil then
    FControl.FreeNotification(Self);
  FBounds := TRect.Empty;
end;

procedure TLenticularDisplay.SetPollInterval(const AValue: Integer);
begin
  FPollInterval := Max(10, AValue);
  if FTimer <> nil then
    FTimer.Interval := FPollInterval;
end;

function TLenticularDisplay.StoreInitTimeout: Boolean;
begin
  Result := not SameValue(FInitTimeout, LENTICULAR_DISPLAY_INIT_TIMEOUT);
end;

function TLenticularDisplay.GetRunning: Boolean;
begin
  Result := FState = ldsRunning;
end;

procedure TLenticularDisplay.Log(const AText: string);
begin
  if Assigned(FOnLog) and not (csDestroying in ComponentState) then
    FOnLog(Self, AText);
end;

class function TLenticularDisplay.Installed: Boolean;
begin
  {$IFDEF WIN64}
  Result := LenticularRuntimeInstalled;
  {$ELSE}
  Result := False;
  {$ENDIF}
end;

procedure TLenticularDisplay.Fail(AProblem: TLenticularDisplayProblem; const AMessage: string;
  ATell: Boolean);
begin
  FState := ldsOff;
  FProblem := AProblem;
  Log('Glasses-free 3D not started: ' + AMessage);
  if ATell and Assigned(FOnProblem) then
    FOnProblem(Self, AProblem, AMessage);
end;

procedure TLenticularDisplay.SetLensState(AValue: TLenticularDisplayLensState; const AWhy: string);
const
  Names: array[TLenticularDisplayLensState] of string = ('not known', 'ON', 'off');
begin
  if AValue = FLensState then
    Exit;
  FLensState := AValue;
  Log(Format('Lens %s (%s)', [Names[AValue], AWhy]));
  if Assigned(FOnLensChange) then
    FOnLensChange(Self);
end;

function TLenticularDisplay.Start: Boolean;
{$IFDEF WIN64}
var
  Wnd, PostTo: HWND;
  Why: string;
  Timeout: Integer;
{$ENDIF}
begin
  Result := False;
  if csDesigning in ComponentState then
    Exit;
  if FState <> ldsOff then
    Exit(True);
  FProblem := ldpNone;
  {$IF not DEFINED(MSWINDOWS)}
  Fail(ldpNotInstalled, 'glasses-free 3D is available on Windows only', False);
  {$ELSEIF not DEFINED(WIN64)}
  Fail(ldpNotWin64, LenticularBridgeLastError, True);
  {$ELSE}
  // The bridge first: it is the one that knows whether the runtime is there
  if not LenticularBridgeAvailable then
  begin
    Fail(ldpBridgeMissing, LenticularBridgeLastError, True);
    Exit;
  end;
  if not LenticularRuntimeInstalled then
  begin
    Fail(ldpNotInstalled, 'the display runtime is not installed (the bridge did not find its ' +
      'DLLs); nothing shown to the user', False);
    Exit;
  end;
  if not FindFormWindow(Wnd, Why) then
  begin
    Fail(ldpNoForm, Why, True);
    Exit;
  end;
  FFormWnd := Wnd;
  FStartTick := TThread.GetTickCount64;
  // A check from an earlier start has long finished: its answer was posted
  if FProbe <> nil then
  begin
    FProbe.WaitFor;
    FreeAndNil(FProbe);
  end;
  if not LenticularBridgeHasExport('lnb_Probe') then
  begin
    Log('This LenticularBridge.dll has no lnb_Probe: starting ' +
      'on this thread, which can freeze the window for up to InitTimeout');
    Exit(Initialize);
  end;
  // The wait for the display (a service starting, a display) happens on a background
  // thread: lnb_Initialize would wait on this one, with the window frozen
  FState := ldsChecking;
  Timeout := Max(0, Round(FInitTimeout * 1000));
  PostTo := FMsgWnd;
  Log(Format('Checking for the display service and display on a background thread (up to %d ms)',
    [Timeout]));
  FProbe := TThread.CreateAnonymousThread(
    procedure
    var
      RC: Integer;
    begin
      RC := lnb_Probe(Timeout);
      // If the component has gone, its window has too and this fails
      // harmlessly
      PostMessage(PostTo, WM_LENTICULAR_DISPLAY_PROBED, WPARAM(RC), 0);
    end);
  FProbe.FreeOnTerminate := False;
  FProbe.Start;
  Result := True;
  {$ENDIF}
end;

procedure TLenticularDisplay.Stop;
var
  WasRunning: Boolean;
begin
  if FTimer <> nil then
    FTimer.Enabled := False;
  WasRunning := FState = ldsRunning;
  if FState = ldsChecking then
    Log('Glasses-free 3D turned off during the display check: its answer will be ignored');
  FState := ldsOff;
  FEyesTracked := False;
  FWeaving := False;
  if not WasRunning then
    Exit;
  {$IFDEF MSWINDOWS}
  lnb_Finalize;
  lnb_SetLogCallback(nil);
  {$ENDIF}
  Log('Display stopped');
  // The display says nothing more once its context is gone
  if not (csDestroying in ComponentState) then
    SetLensState(ldlUnknown, 'the display stopped');
  if Assigned(FOnStopped) and not (csDestroying in ComponentState) then
    FOnStopped(Self);
end;

procedure TLenticularDisplay.SetFlat(const AValue: Boolean);
begin
  if AValue = FFlat then
    Exit;
  FFlat := AValue;
  if not FWeaving then
    Exit;
  {$IFDEF MSWINDOWS}
  lnb_SetLens(Ord(not FFlat));
  {$ENDIF}
  if FFlat then
    Log('Flat: the lens is asked off while weaving')
  else
    Log('Glasses-free 3D: the lens is asked on while weaving');
end;

procedure TLenticularDisplay.SetWeaving(const AValue: Boolean);
begin
  if (AValue = FWeaving) or (AValue and not Running) then
    Exit;
  FWeaving := AValue;
  {$IFDEF MSWINDOWS}
  // The window over Control shows the woven frames; the lens makes them 3D
  // (and blurs everything else on the panel)
  lnb_SetVisible(Ord(AValue));
  lnb_SetLens(Ord(AValue and not FFlat));
  {$ENDIF}
  FSubmits := 0;
  FillChar(FSubmitResults, SizeOf(FSubmitResults), 0);
  if AValue and FFlat then
    Log('Weaving flat: the bridge''s window covers the view and the lens stays off')
  else if AValue then
    Log('Weaving: the bridge''s window covers the view and the lens is asked to come on')
  else
    Log('Not weaving: the bridge''s window is hidden and the lens asked off');
end;

procedure TLenticularDisplay.SetFrameCap(AOn: Boolean);
begin
  FSettings.FrameCap := AOn;
  {$IFDEF MSWINDOWS}
  if Running then
    lnb_SetFrameCap(Ord(AOn));
  {$ENDIF}
  if AOn then
    Log('Frame cap on: one frame per vertical blank of the 3D display')
  else
    Log('Frame cap off: no wait for the 3D display''s vertical blank after each frame ' +
      '(vsync still on)');
end;

procedure TLenticularDisplay.SetLatencyFrames(AFrames: Integer);
begin
  AFrames := EnsureRange(AFrames, 0, 10);
  FSettings.LatencyFrames := AFrames;
  {$IFDEF MSWINDOWS}
  if Running and (AFrames > 0) then
    lnb_SetLatencyInFrames(AFrames);
  {$ENDIF}
  if AFrames > 0 then
    Log(Format('Weaver latency %d frames', [AFrames]))
  else
    Log('Weaver latency 0: the weaver keeps the latency it was last told (the runtime''s own ' +
      'until then)');
end;

function TLenticularDisplay.UpdateEyes: Boolean;
begin
  Result := False;
  if not Running then
    Exit;
  {$IFDEF MSWINDOWS}
  ReadEyes;
  Result := True;
  {$ENDIF}
end;

function TLenticularDisplay.SubmitViews(APixels: Pointer; AViewWidth, AViewHeight, APitch: Integer;
  ARGBA: Boolean): Integer;
begin
  Result := LNB_E_NOT_INITIALIZED;
  if not FWeaving then
    Exit;
  {$IFDEF MSWINDOWS}
  if ARGBA then
    Result := lnb_SubmitViews(APixels, AViewWidth, AViewHeight, APitch, LNB_FMT_RGBA8)
  else
    Result := lnb_SubmitViews(APixels, AViewWidth, AViewHeight, APitch, LNB_FMT_BGRA8);
  CountSubmit(Result, 'lnb_SubmitViews');
  {$ENDIF}
end;

function TLenticularDisplay.SubmitEyeTextures(ALeft, ARight: Pointer; AViewWidth,
  AViewHeight: Integer): Integer;
begin
  Result := LNB_E_NOT_INITIALIZED;
  if not FWeaving then
    Exit;
  {$IFDEF MSWINDOWS}
  Result := lnb_CopyEyeTexture(0, ALeft, AViewWidth, AViewHeight);
  if Result = LNB_OK then
    Result := lnb_CopyEyeTexture(1, ARight, AViewWidth, AViewHeight);
  if Result = LNB_OK then
    Result := lnb_PresentViews(AViewWidth, AViewHeight);
  CountSubmit(Result, 'lnb_CopyEyeTexture / lnb_PresentViews');
  {$ENDIF}
end;

function TLenticularDisplay.BridgeDevice: Pointer;
begin
  Result := nil;
  {$IFDEF MSWINDOWS}
  if Running and LenticularBridgeHasExport('lnb_GetDevice') then
    Result := lnb_GetDevice;
  {$ENDIF}
end;

procedure TLenticularDisplay.CountSubmit(AResult: Integer; const AWhat: string);
const
  // Slots of FSubmitResults
  RES_WOVEN = 0;
  RES_FLAT = 1;
  RES_HIDDEN = 2;
  RES_FAILED = 3;
begin
  {$IFDEF MSWINDOWS}
  Inc(FSubmits);
  case AResult of
    LNB_OK: Inc(FSubmitResults[RES_WOVEN]);
    LNB_S_2D_FALLBACK: Inc(FSubmitResults[RES_FLAT]);
    LNB_S_OCCLUDED: Inc(FSubmitResults[RES_HIDDEN]);
  else
    begin
      if FSubmitResults[RES_FAILED] = 0 then
        Log(Format('%s failed (%d): %s', [AWhat, AResult, LenticularBridgeLastError]));
      Inc(FSubmitResults[RES_FAILED]);
    end;
  end;
  {$ENDIF}
end;

procedure TLenticularDisplay.SaveSettings;
begin
  try
    FSettings.Save;
    Log('Display settings saved to ' + FSettings.FileName);
  except
    on E: Exception do
      Log(Format('Display settings NOT saved to %s: %s: %s',
        [FSettings.FileName, E.ClassName, E.Message]));
  end;
end;

function TLenticularDisplay.DisplayRect(out ARect: TRect): Boolean;
{$IFDEF MSWINDOWS}
var
  DR: TLNBRect;
{$ENDIF}
begin
  ARect := TRect.Empty;
  {$IFDEF MSWINDOWS}
  Result := Running and (lnb_GetDisplayRect(DR) = LNB_OK);
  if Result then
    ARect := TRect.Create(DR[0], DR[1], DR[2], DR[3]);
  {$ELSE}
  Result := False;
  {$ENDIF}
end;

function TLenticularDisplay.DisplayInfo(out AInfo: TLNBDisplayInfo): Boolean;
begin
  FillChar(AInfo, SizeOf(AInfo), 0);
  {$IFDEF MSWINDOWS}
  Result := Running and (lnb_GetDisplayInfo(@AInfo) = LNB_OK);
  {$ELSE}
  Result := False;
  {$ENDIF}
end;

procedure TLenticularDisplay.TimerTick(Sender: TObject);
{$IFDEF MSWINDOWS}
var
  NowTick: UInt64;
{$ENDIF}
begin
  if FState <> ldsRunning then
    Exit;
  {$IFDEF MSWINDOWS}
  PollEvents;
  ReadLens;
  UpdateBounds;
  ReadEyes;
  NowTick := TThread.GetTickCount64;
  if (FLogInterval > 0) and (NowTick - FLastLogTick >= UInt64(FLogInterval)) then
  begin
    FLastLogTick := NowTick;
    Log(Format('Eyes L%s R%s mm, separation %.1f mm%s | view centre (%.1f, %.1f) mm, ' +
      '%.1f x %.1f mm', [FmtMM(FLeftEyeMM), FmtMM(FRightEyeMM),
      FLeftEyeMM.Distance(FRightEyeMM), IfThen(FEyesTracked, '', ' NOT TRACKED'),
      FWindowCenterMM.X, FWindowCenterMM.Y, FWindowSizeMM.Width, FWindowSizeMM.Height]));
    if FWeaving then
    begin
      Log(Format('  submitted %d frames: woven %d, flat %d, hidden %d, failed %d',
        [FSubmits, FSubmitResults[0], FSubmitResults[1], FSubmitResults[2],
         FSubmitResults[3]]));
      FSubmits := 0;
      FillChar(FSubmitResults, SizeOf(FSubmitResults), 0);
    end;
  end;
  {$ENDIF}
end;

{$IFDEF MSWINDOWS}

function TLenticularDisplay.FindFormWindow(out AWnd: HWND; out AWhy: string): Boolean;
var
  Form: TCommonCustomForm;
begin
  AWnd := 0;
  Result := False;
  if FControl = nil then
  begin
    AWhy := 'Control is not set: nothing to show glasses-free 3D in';
    Exit;
  end;
  if (FControl.Root = nil) or not (FControl.Root.GetObject is TCommonCustomForm) then
  begin
    AWhy := Format('%s is not on a form', [FControl.Name]);
    Exit;
  end;
  Form := TCommonCustomForm(FControl.Root.GetObject);
  // A hidden form will do: a program can start the display on a form it shows only
  // while weaving (StereoModel's full-screen form, owner, 7 November 2026),
  // so that showing it is quick; the bridge's window, a child of the form's,
  // stays hidden until Weaving
  if Form.Handle = nil then
  begin
    AWhy := Format('the form %s has no window yet', [Form.Name]);
    Exit;
  end;
  AWnd := FormToHWND(Form);
  if AWnd = 0 then
  begin
    AWhy := Format('the form %s has no window', [Form.Name]);
    Exit;
  end;
  AWhy := '';
  Result := True;
end;

procedure TLenticularDisplay.MsgWndProc(var AMessage: Winapi.Messages.TMessage);
begin
  if AMessage.Msg = WM_LENTICULAR_DISPLAY_PROBED then
  begin
    AMessage.Result := 0;
    ProbeDone(Integer(AMessage.WParam));
  end
  else
    AMessage.Result := DefWindowProc(FMsgWnd, AMessage.Msg, AMessage.WParam, AMessage.LParam);
end;

procedure TLenticularDisplay.ProbeDone(ARC: Integer);
var
  Ms: UInt64;
begin
  Ms := TThread.GetTickCount64 - FStartTick;
  if FState <> ldsChecking then
  begin
    Log(Format('Display check answered %d after %d ms, no longer wanted', [ARC, Int64(Ms)]));
    Exit;
  end;
  case ARC of
    LNB_OK:
      begin
        Log(Format('Display check: service running and 3D display found, after %d ms',
          [Int64(Ms)]));
        Initialize;
      end;
    LNB_E_RUNTIME_MISSING:
      Fail(ldpNotInstalled, 'the bridge could not load the display runtime: ' +
        LenticularBridgeLastError, False);
    LNB_E_NO_SERVICE:
      Fail(ldpNoService, 'The display service is not running. It normally ' +
        'starts with Windows: restarting the display software, or the computer, starts it ' +
        'again.', True);
    LNB_E_NO_DISPLAY:
      Fail(ldpNoDisplay, 'No 3D display was found. Check that it is switched on and connected ' +
        '(video cable and USB), and set to its native resolution.', True);
  else
    begin
      Log(Format('Display check: unexpected answer %d after %d ms (%s); starting anyway',
        [ARC, Int64(Ms), LenticularBridgeLastError]));
      Initialize;
    end;
  end;
end;

function TLenticularDisplay.Initialize: Boolean;
var
  Wnd: HWND;
  Why: string;
  RC: Integer;
  T0: UInt64;
begin
  Result := False;
  // The form may have gone while the check ran
  if not FindFormWindow(Wnd, Why) then
  begin
    Fail(ldpNoForm, Why, True);
    Exit;
  end;
  FFormWnd := Wnd;
  GBridgeLogOwner := Self;
  lnb_SetLogCallback(BridgeLogCallback);
  // Gorilla3D does not draw through FMX's Direct3D 11 device, so there is
  // nothing to share: the bridge makes its own device on the GPU that drives
  // the 3D display, and the views will be uploaded to it
  if LenticularBridgeHasExport('lnb_SetExternalDevice') then
    lnb_SetExternalDevice(nil);
  // The lens off BEFORE the display starts: the bridge makes its lens hint inside
  // lnb_Initialize in the state last asked for, which is on until told
  // otherwise, so the whole panel was blurred for as long as the start took
  // (owner, 16:26). Nothing is woven yet, so it stays off
  lnb_SetLens(0);
  Log(Format('Starting the display (lnb_Initialize, timeout %.1f s, lens off); the bridge uses a ' +
    'Direct3D 11 device of its own', [FInitTimeout]));
  T0 := TThread.GetTickCount64;
  RC := lnb_Initialize(Pointer(FFormWnd), FInitTimeout);
  Log(Format('lnb_Initialize returned %d after %d ms (%d ms after Start)',
    [RC, Int64(TThread.GetTickCount64 - T0), Int64(TThread.GetTickCount64 - FStartTick)]));
  if RC <> LNB_OK then
  begin
    lnb_SetLogCallback(nil);
    case RC of
      LNB_E_NO_SERVICE:
        Fail(ldpNoService, 'The display would not start: ' + LenticularBridgeLastError, True);
      LNB_E_NO_DISPLAY:
        Fail(ldpNoDisplay, 'The display would not start: ' + LenticularBridgeLastError, True);
    else
      Fail(ldpStartFailed, Format('The display would not start (%d): %s',
        [RC, LenticularBridgeLastError]), True);
    end;
    Exit;
  end;
  // Nothing is woven yet, so the bridge's window stays hidden (Control shows
  // as Gorilla3D draws it) and the lens off (it would blur the whole panel)
  lnb_SetVisible(0);
  if FSettings.LatencyFrames > 0 then
    lnb_SetLatencyInFrames(FSettings.LatencyFrames);
  // The bridge waits by default; the settings say whether to
  lnb_SetFrameCap(Ord(FSettings.FrameCap));
  FState := ldsRunning;
  FCanReadLens := LenticularBridgeHasExport('lnb_GetLensState');
  if FCanReadLens then
    Log('The lens is read from the display (lnb_GetLensState)')
  else
    Log('This LenticularBridge.dll has no lnb_GetLensState: ' +
      'the lens is known only from the runtime''s LensOn / LensOff events');
  ReadLens;
  FBounds := TRect.Empty;
  FEyesTracked := False;
  FWindowCenterMM := PointF(0, 0);
  FWindowSizeMM := TSizeF.Create(0, 0);
  LogStartDetails;
  UpdateBounds;
  FLastLogTick := TThread.GetTickCount64;
  FTimer.Interval := FPollInterval;
  FTimer.Enabled := True;
  Result := True;
  if Assigned(FOnStarted) then
    FOnStarted(Self);
end;

procedure TLenticularDisplay.LogStartDetails;
var
  Info: TLNBDisplayInfo;
  DR: TLNBRect;
  Shown: TRect;
  Centre: TPoint;
begin
  Log('Display runtime ' + UTF8ToString(lnb_GetPlatformVersion));
  if lnb_GetDisplayInfo(@Info) = LNB_OK then
    Log(Format('3D display %d x %d px (panel %d x %d), %.1f x %.1f mm, recommended view ' +
      '%d x %d per eye', [Info.resolutionWidth, Info.resolutionHeight,
      Info.physicalResolutionWidth, Info.physicalResolutionHeight, Info.physicalWidthMM,
      Info.physicalHeightMM, Info.recommendedViewWidth, Info.recommendedViewHeight]))
  else
    Log('3D display properties not available: ' + LenticularBridgeLastError);
  if lnb_GetDisplayRect(DR) = LNB_OK then
  begin
    Log(Format('3D display on the desktop at (%d, %d)-(%d, %d)', [DR[0], DR[1], DR[2], DR[3]]));
    // Owner (20:29): name the display, not just "the 3D display"
    try
      FDisplayName := MonitorNameAt(TRect.Create(DR[0], DR[1], DR[2], DR[3]).CenterPoint);
    except
      FDisplayName := '';
    end;
    if FDisplayName = '' then
    begin
      FDisplayName := LENTICULAR_DISPLAY_DEFAULT_NAME;
      Log('The 3D display''s name: Windows does not say');
    end
    else
      Log('The 3D display is ' + FDisplayName);
    if not IsWindowVisible(FFormWnd) then
      Log('The form is hidden for now: where it goes is up to the program')
    else if GetWindowRect(FFormWnd, Shown) then
    begin
      Centre := Shown.CenterPoint;
      if TRect.Create(DR[0], DR[1], DR[2], DR[3]).Contains(Centre) then
        Log('The form is on the 3D display')
      else
        Log(Format('The form''s centre (%d, %d) is NOT on the 3D display: move it there for ' +
          'glasses-free 3D', [Centre.X, Centre.Y]));
    end;
  end
  else
    Log('The 3D display''s place on the desktop not known');
  Log(Format('Settings: eye separation %.1f mm (0 = tracked), look-around %s, latency %d ' +
    'frames (0 = the runtime''s), lens mode %d (0 off over controls, 1 on, 2 off), ' +
    'full screen %s, ' +
    'frame cap %s, per-eye view %s, render scale %.2f, hide cursor %s, weave %s',
    [FSettings.EyeSeparationMM, BoolToStr(FSettings.LookAround, True), FSettings.LatencyFrames,
     FSettings.LensMode, BoolToStr(FSettings.FullScreen, True),
     BoolToStr(FSettings.FrameCap, True), BoolToStr(FSettings.PerEyeView, True),
     FSettings.RenderScale, BoolToStr(FSettings.HideCursor, True),
     BoolToStr(FSettings.Weave, True)]));
  Log('Nothing woven until a renderer sets Weaving: the bridge''s window is hidden and the ' +
    'lens off');
end;

procedure TLenticularDisplay.UpdateBounds;
var
  Scale: Single;
  P: TPointF;
  R: TRect;
  Cx, Cy, W, H: Double;
begin
  if (FControl = nil) or (FControl.Scene = nil) then
    Exit;
  // The bridge wants physical pixels in the form's client area
  Scale := FControl.Scene.GetSceneScale;
  P := FControl.LocalToAbsolute(PointF(0, 0));
  R := TRect.Create(Round(P.X * Scale), Round(P.Y * Scale),
    Round((P.X + FControl.Width) * Scale), Round((P.Y + FControl.Height) * Scale));
  if (R.Width <= 0) or (R.Height <= 0) then
    Exit;
  if R <> FBounds then
  begin
    if lnb_SetBounds(R.Left, R.Top, R.Width, R.Height) <> LNB_OK then
    begin
      Log('lnb_SetBounds failed: ' + LenticularBridgeLastError);
      Exit;
    end;
    Log(Format('View at (%d, %d), %d x %d physical pixels (scale %.2f)',
      [R.Left, R.Top, R.Width, R.Height, Scale]));
    FBounds := R;
  end;
  // Moving the form moves the view on the display without changing R
  if lnb_GetWindowRectMM(Cx, Cy, W, H) = LNB_OK then
    if (Abs(Cx - FWindowCenterMM.X) > 0.5) or (Abs(Cy - FWindowCenterMM.Y) > 0.5) or
      (Abs(W - FWindowSizeMM.Width) > 0.5) or (Abs(H - FWindowSizeMM.Height) > 0.5) then
    begin
      FWindowCenterMM := PointF(Cx, Cy);
      FWindowSizeMM := TSizeF.Create(W, H);
      Log(Format('View on the 3D display: centre (%.1f, %.1f) mm, %.1f x %.1f mm',
        [Cx, Cy, W, H]));
    end;
end;

procedure TLenticularDisplay.PollEvents;
var
  Ev: TLNBSystemEvent;
begin
  while lnb_PollSystemEvent(@Ev) = 1 do
  begin
    Log(Format('runtime event %s: %s', [LenticularEventTypeName(Ev.eventType),
      UTF8ToString(PAnsiChar(@Ev.message[0]))]));
    if Ev.eventType = LNB_EVENT_LENS_ON then
      SetLensState(ldlOn, 'runtime event LensOn')
    else if Ev.eventType = LNB_EVENT_LENS_OFF then
      SetLensState(ldlOff, 'runtime event LensOff');
  end;
end;

procedure TLenticularDisplay.ReadLens;
begin
  if not FCanReadLens then
    Exit;
  case lnb_GetLensState of
    1: SetLensState(ldlOn, 'read from the display');
    0: SetLensState(ldlOff, 'read from the display');
  end;
end;

procedure TLenticularDisplay.ReadEyes;
var
  L, R: TLNBVec3;
  Tracked: Boolean;
begin
  if lnb_GetEyePositions(L, R) <> LNB_OK then
    Exit;
  FLeftEyeMM := Point3D(L[0], L[1], L[2]);
  FRightEyeMM := Point3D(R[0], R[1], R[2]);
  // Before the tracker finds the viewer the display reports both eyes at one point
  Tracked := FLeftEyeMM.Distance(FRightEyeMM) > 1;
  if Tracked <> FEyesTracked then
  begin
    FEyesTracked := Tracked;
    if Tracked then
      Log(Format('Eyes found: L%s R%s mm', [FmtMM(FLeftEyeMM), FmtMM(FRightEyeMM)]))
    else
      Log(Format('Eyes NOT tracked: both at %s mm', [FmtMM(FLeftEyeMM)]));
  end;
  if Assigned(FOnEyes) then
    FOnEyes(Self, FLeftEyeMM, FRightEyeMM);
end;

{$ENDIF}

end.

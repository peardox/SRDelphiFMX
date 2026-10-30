{ @abstract(Shows an FMX @code(TViewport3D) on a LeiaSR eye-tracked
  lenticular display, in 3D without glasses.)

  @link(TSRStereoRenderer) is pointed at an existing viewport; the scene,
  camera and lights stay as designed. Each frame it asks the SR weaver for the
  predicted eye positions, renders the viewport's 3D children once per eye
  into the viewport's own context with an off-axis (window) projection,
  copies both images side by side into one buffer, and hands that to
  SRFmxBridge.dll (@link(SRFmxBridge.Api)), which weaves it for the lens in a
  native child window placed exactly over the viewport.

  The viewport's current camera is the reference: the plane
  @link(TSRStereoRenderer.FocusDistance) units in front of it falls on the
  display glass and fills the viewport as it does in 2D. Nearer objects come
  out of the screen; farther ones go behind it.

  Needs Win64, FMX's DirectX 11 context (the Windows default) and a
  Per-Monitor v2 DPI-aware manifest, so the woven pattern lines up with the
  panel's pixels. }
unit FMX.SRStereoViewport;

interface

uses
  Winapi.Windows,
  System.SysUtils, System.Classes, System.Types, System.UITypes, System.Math,
  System.Math.Vectors, System.Diagnostics, FMX.Types, FMX.Types3D, FMX.Controls3D,
  FMX.Viewport3D, FMX.Forms, FMX.Graphics, SRFmxBridge.Api;

type
  { How @link(TSRStereoRenderer) drives its frames. }
  TSRLoopMode = (
    { Continuously from @code(Application.OnIdle), paced by the vertical
      blank. Smoothest. }
    lmIdle,
    { From an FMX @code(TTimer), about 60 frames a second at most. }
    lmTimer,
    { Only when the program calls @link(TSRStereoRenderer.RenderFrame). }
    lmManual);

  { When @link(TSRStereoRenderer) wants the display's lens on. The lens
    covers the whole panel and switches only as a whole, so while it is on,
    everything outside the viewport (the program's own controls included) is
    seen through it and looks soft. }
  TSRLensMode = (
    { Lens on while the pointer is over the viewport, or off the SR display,
      and always in @link(TSRStereoRenderer.FullScreen); off while it is
      over anything else on the SR display (the program's controls, its
      drop-down lists, other programs), so they are sharp. The viewport is
      drawn flat while the lens is off. The default. }
    lensOffOverControls,
    { Lens always on. }
    lensAlwaysOn,
    { Lens always off: the viewport is drawn flat, in 2D. }
    lensAlwaysOff);

  { A stage of each frame that can be skipped, to narrow down a fault. }
  TSRDiagnosticSkip = (
    { Ignore the eye tracker and use the nominal eyes. }
    dsTracking,
    { Do not render the scene (the views are left as they were). }
    dsRender,
    { Do not hand the views to the bridge (nothing is woven or presented). }
    dsSubmit);
  { The stages of each frame to skip. }
  TSRDiagnosticSkips = set of TSRDiagnosticSkip;

  { Reports an SR system event.
    @param(Sender the renderer)
    @param(EventType the SR event type)
    @param(EventName its readable name)
    @param(Msg the event's message) }
  TSRSystemEventNotify = procedure(Sender: TObject; EventType: UInt64;
    const EventName, Msg: string) of object;

  { Reports an error or a log line.
    @param(Sender the renderer)
    @param(Msg the text) }
  TSRTextNotify = procedure(Sender: TObject; const Msg: string) of object;

  { Reports the eye positions used for a frame.
    @param(Sender the renderer)
    @param(LeftMM left eye in millimetres)
    @param(RightMM right eye in millimetres) }
  TSREyesNotify = procedure(Sender: TObject; const LeftMM, RightMM: TPoint3D) of object;

  { What one eye's render measured and used; kept for the log. }
  TSREyeCalibration = record
    { Sign of the camera's local x axis on screen (1 = right). }
    SgnR: Single;
    { Sign of the camera's local y axis on screen (1 = up). }
    SgnU: Single;
    { Sign of the camera's local z axis (1 = forward). }
    SgnF: Single;
    { Tangent of half the reference camera's vertical field of view. }
    TanRef: Single;
    { World units per millimetre. }
    Scale: Single;
    { Zoom built into the view matrix so FMX's fixed projection gives the
      eye's field of view (reference tangent over the eye's). }
    Zoom: Single;
    { Where the viewport's top-right corner lands, in normalised device
      coordinates: (1, 1) when the projection is right. }
    CornerNdc: TPointF;
    { Shear applied in x (screen centre offset over depth). }
    ShearX: Single;
    { Shear applied in y. }
    ShearY: Single;
  end;

  { Drives a @code(TViewport3D) on a LeiaSR display. Set
    @link(TSRStereoRenderer.Viewport), then @link(TSRStereoRenderer.Active). }
  TSRStereoRenderer = class(TComponent)
  private
    { The viewport shown in 3D. }
    FViewport: TViewport3D;
    { Whether the program wants 3D on. }
    FActive: Boolean;
    { Whether the bridge is initialised and frames are being drawn. }
    FRunning: Boolean;
    { Whether a start is waiting for the form's window to exist. }
    FStartPending: Boolean;
    { How frames are driven. }
    FLoopMode: TSRLoopMode;
    { Timer for @link(lmTimer). }
    FTimer: TTimer;
    { The @code(Application.OnIdle) handler that was there before ours. }
    FPrevIdle: TIdleEvent;
    { Whether our idle handler is installed. }
    FIdleHooked: Boolean;
    { Side-by-side pixels for both eyes. }
    FBuffer: TBytes;
    { See @link(TSRStereoRenderer.FocusDistance). }
    FFocusDistance: Single;
    { See @link(TSRStereoRenderer.EyeSeparationScale). }
    FEyeSeparationScale: Single;
    { See @link(TSRStereoRenderer.InitTimeout). }
    FInitTimeout: Double;
    { See @link(TSRStereoRenderer.VSync). }
    FVSync: Boolean;
    { See @link(TSRStereoRenderer.LatencyFrames). }
    FLatencyFrames: Integer;
    { See @link(TSRStereoRenderer.LogInterval). }
    FLogInterval: Integer;
    { Left eye used for the last frame, millimetres. }
    FLeftEyeMM: TPoint3D;
    { Right eye used for the last frame, millimetres. }
    FRightEyeMM: TPoint3D;
    { Whether the last frame was woven. }
    FWeaving: Boolean;
    { Whether the last frame found the window hidden. }
    FOccluded: Boolean;
    { Last visibility given to the bridge, -1 before the first. }
    FWindowVisible: Integer;
    { The form's native window. }
    FFormWnd: HWND;
    { Last error text. }
    FLastError: string;
    { Guards against re-entering @link(TSRStereoRenderer.RenderFrame). }
    FInRender: Boolean;
    { Whether the last frame had no valid tracking and used the nominal eyes. }
    FUsingNominalEyes: Boolean;
    { Whether the last frame's eyes were too close together or too far apart
      and were rebuilt around their midpoint. }
    FIpdRepaired: Boolean;
    { See @link(TSRStereoRenderer.EyeSeparationMM). }
    FEyeSeparationMM: Single;
    { Side-by-side test image shown instead of the scene, nil for the scene. }
    FStereoImage: TBitmap;
    { File the test image came from. }
    FStereoImageFile: string;
    { Whether the test image still has to be copied into the buffer. }
    FStereoImageDirty: Boolean;
    { Pixel format of the test image's pixels, as an @code(SRB_FMT_...) value. }
    FStereoImageFormat: Integer;
    { Viewport size in pixels the test image was last fitted to. }
    FStereoImageFitSize: TSize;
    { See @link(TSRStereoRenderer.LookAround). }
    FLookAround: Boolean;
    { See @link(TSRStereoRenderer.PlaceFormOnSRDisplay). }
    FPlaceFormOnSRDisplay: Boolean;
    { See @link(TSRStereoRenderer.LensMode). }
    FLensMode: TSRLensMode;
    { See @link(TSRStereoRenderer.LensSwitchDelay). }
    FLensSwitchDelay: Integer;
    { Whether the lens was last asked to be on. }
    FLensOn: Boolean;
    { Clock reading (ms) since which the wanted lens state has differed from
      @link(FLensOn); -1 while they agree. }
    FLensWantSince: Int64;
    { Why the lens is in its current state, for the log. }
    FLensReason: string;
    { Whether the eye tracker has found the eyes and they have held steady
      for @link(TSRStereoRenderer.SettleTime); until then the view is
      flat. }
    FEyesSettled: Boolean;
    { Eye midpoint (mm) the settling is measured against. }
    FSettleMid: TPoint3D;
    { Clock reading (ms) since the eyes have been valid and within
      @link(SettleToleranceMM) of @link(FSettleMid); -1 while not. }
    FSettleSince: Int64;
    { Clock reading (ms) since tracking was lost; -1 while tracked. }
    FLostSince: Int64;
    { See @link(TSRStereoRenderer.SettleTime). }
    FSettleTime: Integer;
    { See @link(TSRStereoRenderer.FullScreen). }
    FFullScreen: Boolean;
    { Whether the viewport's centre is on the SR display (@true when the
      display's position is unknown). }
    FViewportOnSR: Boolean;
    { See @link(TSRStereoRenderer.FullScreenGap). }
    FFullScreenGap: Integer;
    { Whether @link(FViewportOnSR) has been logged since starting. }
    FViewportOnSRLogged: Boolean;
    { The viewport's rectangle given to the bridge last frame, client
      physical pixels; empty before the first. }
    FLastBounds: TRect;
    { Where the form was before full screen (normal or maximised). }
    FSavedPlacement: TWindowPlacement;
    { The viewport in the form's client area, physical pixels. }
    FViewportClientRect: TRect;
    { The SR display's desktop rectangle, physical pixels. }
    FSRRect: TRect;
    { Whether @link(FSRRect) is known. }
    FSRRectKnown: Boolean;
    { What the left eye's render measured. }
    FCalLeft: TSREyeCalibration;
    { What the right eye's render measured. }
    FCalRight: TSREyeCalibration;
    { Reference camera position for the log. }
    FRefCameraPos: TPoint3D;
    { Viewport rectangle on the display: centre, millimetres. }
    FWinCenterMM: TPointF;
    { Viewport rectangle on the display: size, millimetres. }
    FWinSizeMM: TSizeF;
    { Per-eye view size last rendered, pixels. }
    FViewSize: TSize;
    { Times log intervals and frame rate. }
    FClock: TStopwatch;
    { Clock reading at the last log line, milliseconds. }
    FLastLogMs: Int64;
    { Frames drawn since the last log line. }
    FFramesSinceLog: Integer;
    { Longest frame since the last log line, milliseconds. }
    FWorstFrameMs: Double;
    { Clock reading at the start of the previous frame, milliseconds. }
    FPrevFrameMs: Double;
    { Results of @code(srb_SubmitViews) since the last log line, by kind. }
    FResultCounts: array[0..3] of Integer;
    { See @link(TSRStereoRenderer.TraceFrames). }
    FTraceFrames: Integer;
    { Frames still to trace since starting. }
    FTraceLeft: Integer;
    { Frames drawn since starting. }
    FFrameNo: Int64;
    { See @link(TSRStereoRenderer.DiagnosticSkip). }
    FDiagnosticSkip: TSRDiagnosticSkips;
    { See @link(TSRStereoRenderer.OnSystemEvent). }
    FOnSystemEvent: TSRSystemEventNotify;
    { See @link(TSRStereoRenderer.OnError). }
    FOnError: TSRTextNotify;
    { See @link(TSRStereoRenderer.OnLog). }
    FOnLog: TSRTextNotify;
    { See @link(TSRStereoRenderer.OnEyesUpdated). }
    FOnEyesUpdated: TSREyesNotify;
    { See @link(TSRStereoRenderer.OnStarted). }
    FOnStarted: TNotifyEvent;
    { Sets @link(TSRStereoRenderer.Viewport).
      @param(Value the viewport) }
    procedure SetViewport(const Value: TViewport3D);
    { Sets @link(TSRStereoRenderer.Active), starting or stopping.
      @param(Value whether 3D should be on) }
    procedure SetActive(const Value: Boolean);
    { Sets @link(TSRStereoRenderer.VSync).
      @param(Value whether to wait for the vertical blank) }
    procedure SetVSync(const Value: Boolean);
    { Sets @link(TSRStereoRenderer.LoopMode), moving the hook.
      @param(Value the new mode) }
    procedure SetLoopMode(const Value: TSRLoopMode);
    { Sets @link(TSRStereoRenderer.LatencyFrames).
      @param(Value frames, 0 for the SR default) }
    procedure SetLatencyFrames(const Value: Integer);
    { Sets @link(TSRStereoRenderer.FocusDistance), at least 0.01.
      @param(Value world units) }
    procedure SetFocusDistance(const Value: Single);
    { Timer handler for @link(lmTimer).
      @param(Sender the timer) }
    procedure TimerTick(Sender: TObject);
    { Idle handler for @link(lmIdle); calls the previous handler first.
      @param(Sender the application)
      @param(Done set to @false to keep the idle loop running) }
    procedure AppIdle(Sender: TObject; var Done: Boolean);
    { One loop step: completes a pending start, then draws a frame. }
    procedure Tick;
    { Installs the timer or idle handler for the current
      @link(TSRStereoRenderer.LoopMode). }
    procedure HookLoop;
    { Removes the timer or idle handler. }
    procedure UnhookLoop;
    { Initialises the bridge once the form's window exists.
      @returns(@true if running) }
    function TryStart: Boolean;
    { Moves the bridge's child window over the viewport.
      @returns(@true if the viewport is visible and placed) }
    function UpdateWindowBounds: Boolean;
    { Renders one eye's view into the context and copies it out.
      @param(Ctx the viewport's context)
      @param(RefCamera the viewport's current camera)
      @param(EyeMM the eye, millimetres from the display centre)
      @param(Dest where the first pixel goes)
      @param(Pitch bytes per row of the destination)
      @param(Cal receives what was measured and used) }
    procedure RenderEye(const Ctx: TContext3D; const RefCamera: TCamera;
      const EyeMM: TPoint3D; Dest: Pointer; Pitch: Integer; out Cal: TSREyeCalibration);
    { Clears the context, sets the viewport's lights and renders its 3D
      children.
      @param(Ctx the viewport's context) }
    procedure RenderScene(const Ctx: TContext3D);
    { Passes queued SR system events to @link(TSRStereoRenderer.OnSystemEvent)
      and the log. }
    procedure PollEvents;
    { Records an error and reports it through
      @link(TSRStereoRenderer.OnError) and the log.
      @param(Msg the error) }
    procedure DoError(const Msg: string);
    { Sends one line to @link(TSRStereoRenderer.OnLog).
      @param(Msg the line) }
    procedure Log(const Msg: string);
    { Logs a stage of the current frame while
      @link(TSRStereoRenderer.TraceFrames) frames remain to be traced.
      @param(Stage what is about to happen or just happened) }
    procedure TraceStage(const Stage: string);
    { Copies the test image into the side-by-side buffer, letterboxed or
      pillarboxed in black so each eye's view has the viewport's shape and the
      picture keeps its own.
      @param(ViewportW the viewport's width in pixels)
      @param(ViewportH the viewport's height in pixels)
      @param(W receives the width of one eye's view)
      @param(H receives the height)
      @param(Pitch receives the bytes per row) }
    procedure CopyStereoImage(ViewportW, ViewportH: Integer; out W, H, Pitch: Integer);
    { Moves the form onto the SR display if it is on another monitor,
      keeping it maximised if it was.
      @param(Form the viewport's form) }
    procedure MoveFormToSRDisplay(const Form: TCommonCustomForm);
    { Logs the display and window details once after starting. }
    procedure LogStartDetails;
    { Logs one summary line when @link(TSRStereoRenderer.LogInterval) has
      passed. }
    procedure LogPeriodic;
    { @returns(whether @link(TSRStereoRenderer.FocusDistance) differs from
      the default) }
    function StoreFocusDistance: Boolean;
    { @returns(whether @link(TSRStereoRenderer.EyeSeparationScale) differs
      from the default) }
    function StoreEyeSeparationScale: Boolean;
    { @returns(whether @link(TSRStereoRenderer.InitTimeout) differs from the
      default) }
    function StoreInitTimeout: Boolean;
    { @returns(whether @link(TSRStereoRenderer.EyeSeparationMM) is set) }
    function StoreEyeSeparationMM: Boolean;
    { Sets @link(TSRStereoRenderer.LensMode), applying it at once.
      @param(Value the new mode) }
    procedure SetLensMode(const Value: TSRLensMode);
    { Works out whether the lens should be on now, from
      @link(TSRStereoRenderer.LensMode) and the pointer.
      @param(Reason receives why, for the log)
      @returns(@true for on) }
    function LensWanted(out Reason: string): Boolean;
    { Switches the lens when the wanted state has held for
      @link(TSRStereoRenderer.LensSwitchDelay), or at once if Immediate.
      @param(Immediate switch without waiting) }
    procedure UpdateLens(Immediate: Boolean);
    { Follows whether the tracker has found the eyes and they are steady.
      @param(Valid whether this frame's tracked eyes were real (not nominal
        or rebuilt))
      @param(Mid this frame's eye midpoint, mm) }
    procedure UpdateSettling(Valid: Boolean; const Mid: TPoint3D);
    { Sets @link(TSRStereoRenderer.FullScreen).
      @param(Value whether to cover the display) }
    procedure SetFullScreen(const Value: Boolean);
    { Makes the form's window match @link(TSRStereoRenderer.FullScreen), if
      it exists and does not already. }
    procedure ApplyFullScreen;
    { The form the viewport is on.
      @returns(the form, or nil if there is none yet) }
    function ViewportForm: TCommonCustomForm;
  protected
    { Starts after loading if @link(TSRStereoRenderer.Active) was set. }
    procedure Loaded; override;
    { Forgets the viewport when it is freed.
      @param(AComponent the component going away)
      @param(Operation what is happening to it) }
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
  public
    { Creates the renderer, inactive.
      @param(AOwner the owner) }
    constructor Create(AOwner: TComponent); override;
    { Stops and frees the renderer. }
    destructor Destroy; override;
    { Initialises SR and starts drawing. If the form has no window yet, the
      start completes on the first loop step.
      @returns(@true if running now; on failure see
        @link(TSRStereoRenderer.LastError), and the viewport carries on in 2D) }
    function Start: Boolean;
    { Stops drawing and shuts SR down. }
    procedure Stop;
    { Renders, weaves and presents one stereo frame. }
    procedure RenderFrame;
    { Shows a side-by-side stereo image (left view in the left half) instead
      of the scene, woven exactly as given: a test of the weaving on its own,
      independent of the 3D rendering. An empty name goes back to the scene.
      @param(FileName the image file, PNG or JPEG)
      @raises(Exception if the file cannot be read, or is not twice as wide
        as it is high or wider) }
    procedure ShowStereoImage(const FileName: string);
    { The SR display's rectangle on the desktop, in physical pixels.
      @param(R receives it)
      @returns(@true while running, if the display was found) }
    function SRDisplayRect(out R: TRect): Boolean;
    { The SR display's properties.
      @param(Info receives them)
      @returns(@true while running) }
    function DisplayInfo(out Info: TSRBDisplayInfo): Boolean;
    { Whether the bridge is running. }
    property Running: Boolean read FRunning;
    { Whether the last frame was woven (@false: 2D fallback). }
    property Weaving: Boolean read FWeaving;
    { Left eye used for the last frame: millimetres from the display centre,
      y up, z towards the viewer. }
    property LeftEyeMM: TPoint3D read FLeftEyeMM;
    { Right eye used for the last frame. }
    property RightEyeMM: TPoint3D read FRightEyeMM;
    { Whether the form covers the whole SR display, borderless (the
      display's monitor before SR is running). Done on the form's existing
      window, in physical pixels: FMX's own @code(FullScreen) re-creates the
      window and, at display scaling above 100%, sizes it in steps, and a
      weaver created part way through weaves for the wrong size. Set it
      before the form is shown and it is applied once SR starts. The
      program hides its own controls if it wants only the viewport. }
    property FullScreen: Boolean read FFullScreen write SetFullScreen;
    { Rows of the display left uncovered at the bottom in
      @link(TSRStereoRenderer.FullScreen) (default 1). Every time the window
      covered the whole SR display exactly, the picture came out wrong: each
      eye got one half of the left view, stretched to full width, as if the
      SR system took the window for a full-screen side-by-side picture (SR
      displays can weave side-by-side input themselves). A window one row
      short never did. 0 covers the display exactly, for testing. }
    property FullScreenGap: Integer read FFullScreenGap write FFullScreenGap;
    { Whether the lens is on now (asked to be: it takes the panel a moment
      to switch). While it is off the viewport is drawn flat. }
    property LensOn: Boolean read FLensOn;
    { Whether the viewport is on the SR display. While its centre is on
      another monitor the lens is off and the viewport is drawn flat; it is
      logged each time it changes. }
    property ViewportOnSRDisplay: Boolean read FViewportOnSR;
    { The last error. }
    property LastError: string read FLastError;
    { The stereo image being shown, empty while the scene is shown. }
    property StereoImageFile: string read FStereoImageFile;
  published
    { The viewport to show in 3D. }
    property Viewport: TViewport3D read FViewport write SetViewport;
    { Whether 3D is on. }
    property Active: Boolean read FActive write SetActive default False;
    { How frames are driven. }
    property LoopMode: TSRLoopMode read FLoopMode write SetLoopMode default lmIdle;
    { Distance in world units in front of the viewport's camera of the plane
      that falls on the display glass. }
    property FocusDistance: Single read FFocusDistance write SetFocusDistance
      stored StoreFocusDistance;
    { 1 is physically correct stereo; less is gentler, more exaggerates. }
    property EyeSeparationScale: Single read FEyeSeparationScale write FEyeSeparationScale
      stored StoreEyeSeparationScale;
    { Eye separation in millimetres to use instead of the tracker's, keeping
      the tracked midpoint and direction; 0 uses the tracked eyes as they are.
      Set it to the separation configured in the SR software (63 mm, say) if
      the tracker's reading wanders. }
    property EyeSeparationMM: Single read FEyeSeparationMM write FEyeSeparationMM
      stored StoreEyeSeparationMM;
    { @true (the default) draws the scene from where the head is, so moving
      the head looks around objects (motion parallax). @false draws from a
      fixed position in front of the viewport, still with the eye
      separation, so there is depth but the picture does not move with the
      head. }
    property LookAround: Boolean read FLookAround write FLookAround default True;
    { Whether starting moves the form onto the SR display when it is on
      another monitor. }
    property PlaceFormOnSRDisplay: Boolean read FPlaceFormOnSRDisplay
      write FPlaceFormOnSRDisplay default True;
    { When the lens is on; see @link(TSRLensMode). }
    property LensMode: TSRLensMode read FLensMode write SetLensMode
      default lensOffOverControls;
    { Milliseconds the pointer must stay on one side of the viewport's edge
      before @link(lensOffOverControls) switches the lens, so passing over
      the controls does not make it flicker. }
    property LensSwitchDelay: Integer read FLensSwitchDelay write FLensSwitchDelay
      default 250;
    { Milliseconds the tracked eyes must be found and steady (within 20 mm)
      before 3D is shown, at start and after tracking is lost for more than
      a second. Until then the viewport is drawn flat from a fixed viewer,
      so the picture does not slide while the tracker searches; the lens is
      not switched for this. 0 shows 3D at once. }
    property SettleTime: Integer read FSettleTime write FSettleTime default 300;
    { Seconds to wait for the SR service and display when starting. }
    property InitTimeout: Double read FInitTimeout write FInitTimeout stored StoreInitTimeout;
    { Whether presenting waits for the vertical blank. }
    property VSync: Boolean read FVSync write SetVSync default True;
    { Frames of rendering latency for the weaver's eye prediction; 0 leaves
      the SR default. }
    property LatencyFrames: Integer read FLatencyFrames write SetLatencyFrames default 0;
    { Milliseconds between summary lines on
      @link(TSRStereoRenderer.OnLog); 0 turns them off. }
    property LogInterval: Integer read FLogInterval write FLogInterval default 1000;
    { How many frames after starting to log stage by stage on
      @link(TSRStereoRenderer.OnLog), so the last line before a crash shows
      where it happened. }
    property TraceFrames: Integer read FTraceFrames write FTraceFrames default 0;
    { Stages of each frame to skip, to narrow down a fault. }
    property DiagnosticSkip: TSRDiagnosticSkips read FDiagnosticSkip write FDiagnosticSkip default [];
    { Called once the bridge is running. }
    property OnStarted: TNotifyEvent read FOnStarted write FOnStarted;
    { Called with each SR system event. }
    property OnSystemEvent: TSRSystemEventNotify read FOnSystemEvent write FOnSystemEvent;
    { Called when starting or drawing fails. }
    property OnError: TSRTextNotify read FOnError write FOnError;
    { Called with diagnostic lines: start-up details, a summary every
      @link(TSRStereoRenderer.LogInterval), events and errors. }
    property OnLog: TSRTextNotify read FOnLog write FOnLog;
    { Called after each frame with the eye positions used. }
    property OnEyesUpdated: TSREyesNotify read FOnEyesUpdated write FOnEyesUpdated;
  end;

implementation

uses
  Winapi.MultiMon, Winapi.ShlObj, System.Win.ComObj, FMX.Platform.Win, SimulatedReality.Api;

const
  { Default @link(TSRStereoRenderer.FocusDistance): FMX's usual camera sits
    20 units from the origin. }
  DefaultFocusDistance = 20.0;
  { Default @link(TSRStereoRenderer.EyeSeparationScale). }
  DefaultEyeScale = 1.0;
  { Default @link(TSRStereoRenderer.InitTimeout), seconds. }
  DefaultInitTimeout = 5.0;
  { Eyes nearer the screen than this (millimetres) are treated as no
    tracking. }
  MinEyeDistanceMM = 100.0;
  { Nominal left eye when there is no tracking. }
  NominalLeftX = -31.5;
  { Nominal right eye when there is no tracking. }
  NominalRightX = 31.5;
  { Nominal viewing distance, millimetres. }
  NominalZ = 650.0;
  { Eye separations outside MinIpdMM..MaxIpdMM are treated as bad tracking. }
  MinIpdMM = 45.0;
  { See @link(MinIpdMM). }
  MaxIpdMM = 85.0;
  { Separation used to rebuild bad eye pairs around their midpoint, mm. }
  NominalIpdMM = 63.0;
  { How far (mm) the eye midpoint may wander while counting as steady for
    @link(TSRStereoRenderer.SettleTime). }
  SettleToleranceMM = 20.0;
  { Milliseconds without tracking before 3D waits to settle again. }
  LostResettleMs = 1000;
  { Frames traced stage by stage after the viewport changes size. }
  ResizeTraceFrames = 3;

{ Formats a point with no decimals for the log.
  @param(P the point)
  @returns(text such as (-31, 2, 612)) }
function FmtPt(const P: TPoint3D): string;
begin
  Result := Format('(%.0f, %.0f, %.0f)', [P.X, P.Y, P.Z]);
end;

{ Picks one of two strings (System.StrUtils.IfThen would hide
  System.Math.IfThen, which this unit uses for numbers).
  @param(Condition which to pick)
  @param(WhenTrue the string for @true)
  @param(WhenFalse the string for @false)
  @returns(the chosen string) }
function StrIf(Condition: Boolean; const WhenTrue, WhenFalse: string): string;
begin
  if Condition then
    Result := WhenTrue
  else
    Result := WhenFalse;
end;

{ Formats a sign as + or -.
  @param(S the sign)
  @returns(+ or -) }
function FmtSign(const S: Single): string;
begin
  if S >= 0 then
    Result := '+'
  else
    Result := '-';
end;

{ TSRStereoRenderer }

constructor TSRStereoRenderer.Create(AOwner: TComponent);
begin
  inherited;
  FFocusDistance := DefaultFocusDistance;
  FEyeSeparationScale := DefaultEyeScale;
  FInitTimeout := DefaultInitTimeout;
  FVSync := True;
  FLoopMode := lmIdle;
  FLogInterval := 1000;
  FLookAround := True;
  FPlaceFormOnSRDisplay := True;
  FLensMode := lensOffOverControls;
  FLensSwitchDelay := 250;
  FLensOn := True;
  FLensWantSince := -1;
  FSettleTime := 300;
  FFullScreenGap := 1;
  FViewportOnSR := True;
  FWindowVisible := -1;
  FLeftEyeMM := Point3D(NominalLeftX, 0, NominalZ);
  FRightEyeMM := Point3D(NominalRightX, 0, NominalZ);
  FClock := TStopwatch.StartNew;
end;

destructor TSRStereoRenderer.Destroy;
begin
  Stop;
  FTimer.Free;
  FStereoImage.Free;
  inherited;
end;

function TSRStereoRenderer.StoreFocusDistance: Boolean;
begin
  Result := not SameValue(FFocusDistance, DefaultFocusDistance);
end;

function TSRStereoRenderer.StoreEyeSeparationScale: Boolean;
begin
  Result := not SameValue(FEyeSeparationScale, DefaultEyeScale);
end;

function TSRStereoRenderer.StoreEyeSeparationMM: Boolean;
begin
  Result := FEyeSeparationMM <> 0;
end;

procedure TSRStereoRenderer.ShowStereoImage(const FileName: string);
var
  Bmp: TBitmap;
begin
  if FileName = '' then
  begin
    FreeAndNil(FStereoImage);
    FStereoImageFile := '';
    Log('Showing the 3D scene');
    Exit;
  end;
  Bmp := TBitmap.CreateFromFile(FileName);
  try
    if Bmp.Width < 2 * Bmp.Height then
      raise Exception.CreateFmt('%s is %d x %d: a side-by-side image must be at least twice ' +
        'as wide as it is high', [ExtractFileName(FileName), Bmp.Width, Bmp.Height]);
  except
    Bmp.Free;
    raise;
  end;
  FStereoImage.Free;
  FStereoImage := Bmp;
  FStereoImageFile := FileName;
  FStereoImageDirty := True;
  Log(Format('Showing stereo image %s, %d x %d (each eye %d x %d)',
    [ExtractFileName(FileName), Bmp.Width, Bmp.Height, Bmp.Width div 2, Bmp.Height]));
end;

procedure TSRStereoRenderer.CopyStereoImage(ViewportW, ViewportH: Integer; out W, H, Pitch: Integer);
var
  Data: TBitmapData;
  SrcW, SrcH, OffX, OffY, Y: Integer;
  Aspect: Double;
  Src: PByte;
begin
  // Each eye's picture keeps its shape: the view gets the viewport's shape,
  // with black bars either side or above and below. The weaver stretches the
  // view to the viewport, so the picture ends up undistorted.
  SrcW := FStereoImage.Width div 2;
  SrcH := FStereoImage.Height;
  Aspect := ViewportW / Max(1, ViewportH);
  if SrcW / SrcH < Aspect then
  begin
    W := Round(SrcH * Aspect);
    H := SrcH;
  end
  else
  begin
    W := SrcW;
    H := Round(SrcW / Aspect);
  end;
  Pitch := W * 2 * 4;
  if not FStereoImageDirty and (Length(FBuffer) = Pitch * H) and
    (FStereoImageFitSize.cx = ViewportW) and (FStereoImageFitSize.cy = ViewportH) then
    Exit;
  OffX := (W - SrcW) div 2;
  OffY := (H - SrcH) div 2;
  SetLength(FBuffer, Pitch * H);
  FillChar(FBuffer[0], Length(FBuffer), 0);
  if FStereoImage.Map(TMapAccess.Read, Data) then
  try
    if Data.PixelFormat = TPixelFormat.RGBA then
      FStereoImageFormat := SRB_FMT_RGBA8
    else
      FStereoImageFormat := SRB_FMT_BGRA8;
    for Y := 0 to SrcH - 1 do
    begin
      Src := Data.GetScanline(Y);
      // left half of the image into the left view, right half into the
      // right; with the lens off, the left half into both, so it is flat
      System.Move(Src^, FBuffer[(Y + OffY) * Pitch + OffX * 4], SrcW * 4);
      if FLensOn then
        System.Move((Src + SrcW * 4)^, FBuffer[(Y + OffY) * Pitch + (W + OffX) * 4], SrcW * 4)
      else
        System.Move(Src^, FBuffer[(Y + OffY) * Pitch + (W + OffX) * 4], SrcW * 4);
    end;
  finally
    FStereoImage.Unmap(Data);
  end;
  FStereoImageFitSize := TSize.Create(ViewportW, ViewportH);
  FStereoImageDirty := False;
  Log(Format('Stereo image fitted: %d x %d per eye in a %d x %d view (viewport %d x %d), format %d%s',
    [SrcW, SrcH, W, H, ViewportW, ViewportH, FStereoImageFormat,
     StrIf(FLensOn, '', ', flat (lens off)')]));
end;

procedure TSRStereoRenderer.SetLensMode(const Value: TSRLensMode);
begin
  FLensMode := Value;
  if FRunning then
    UpdateLens(True);
end;

function TSRStereoRenderer.LensWanted(out Reason: string): Boolean;
var
  P, C: TPoint;
  Over: HWND;
begin
  // The lens is the SR display's: with the viewport on another monitor
  // there is nothing to look at through it
  if not FViewportOnSR then
  begin
    Reason := 'the viewport is not on the SR display';
    Exit(False);
  end;
  case FLensMode of
    lensAlwaysOn:
      begin
        Reason := 'LensMode always on';
        Exit(True);
      end;
    lensAlwaysOff:
      begin
        Reason := 'LensMode always off';
        Exit(False);
      end;
  end;
  // Full screen shows nothing but the viewport, so keep the lens on. Each
  // of the three broken full-screen pictures so far came right after the
  // lens went off and on again while the window covered the whole display,
  // and the one that worked had no switch.
  if FFullScreen then
  begin
    Reason := 'full screen';
    Exit(True);
  end;
  if not GetCursorPos(P) then
  begin
    Reason := 'pointer position unknown';
    Exit(FLensOn);
  end;
  // While a button is held (dragging a slider, say) nothing changes
  if (GetAsyncKeyState(VK_LBUTTON) < 0) or (GetAsyncKeyState(VK_RBUTTON) < 0) then
  begin
    Reason := FLensReason;
    Exit(FLensOn);
  end;
  if FSRRectKnown and not FSRRect.Contains(P) then
  begin
    Reason := 'pointer is off the SR display';
    Exit(True);
  end;
  // Over the viewport only if no other window (a drop-down list, another
  // program) is in the way: the window under the pointer must be our form
  // or the bridge's child window in it
  Over := WindowFromPoint(P);
  if (Over = 0) or (GetAncestor(Over, GA_ROOT) <> FFormWnd) then
  begin
    Reason := 'pointer is over another window';
    Exit(False);
  end;
  C := P;
  ScreenToClient(FFormWnd, C);
  Result := FViewportClientRect.Contains(C);
  if Result then
    Reason := 'pointer is over the viewport'
  else
    Reason := 'pointer is over the controls';
end;

procedure TSRStereoRenderer.UpdateSettling(Valid: Boolean; const Mid: TPoint3D);
var
  NowMs: Int64;
begin
  NowMs := FClock.ElapsedMilliseconds;
  if not Valid then
  begin
    FSettleSince := -1;
    if FLostSince < 0 then
      FLostSince := NowMs;
    if FEyesSettled and (NowMs - FLostSince > LostResettleMs) then
    begin
      FEyesSettled := False;
      Log(Format('Eyes lost for over %d ms: drawn flat until they are found again', [LostResettleMs]));
    end;
    Exit;
  end;
  FLostSince := -1;
  if FEyesSettled then
    Exit;
  if (FSettleSince < 0) or (Mid.Distance(FSettleMid) > SettleToleranceMM) then
  begin
    FSettleSince := NowMs;
    FSettleMid := Mid;
  end;
  if NowMs - FSettleSince >= FSettleTime then
  begin
    FEyesSettled := True;
    Log(Format('Eyes found and steady for %d ms at %s: 3D on%s', [FSettleTime, FmtPt(Mid),
      StrIf(FLensOn, '', ' (once the lens is on)')]));
  end;
end;

function TSRStereoRenderer.ViewportForm: TCommonCustomForm;
begin
  Result := nil;
  if (FViewport <> nil) and (FViewport.Root <> nil) and
    (FViewport.Root.GetObject is TCommonCustomForm) then
    Result := TCommonCustomForm(FViewport.Root.GetObject);
end;

{ Tells the shell a window is full screen, so the taskbar stays out of its
  way while it is in front (the documented way: ITaskbarList2).
  @param(Wnd the window)
  @param(Value whether it is full screen)
  @returns(empty on success, else what went wrong) }
function MarkFullscreen(Wnd: HWND; Value: Boolean): string;
var
  TaskBar: ITaskbarList2;
  HR: HRESULT;
begin
  Result := '';
  try
    TaskBar := CreateComObject(CLSID_TaskbarList) as ITaskbarList2;
    HR := TaskBar.HrInit;
    if Succeeded(HR) then
      HR := TaskBar.MarkFullscreenWindow(Wnd, Value);
    if Failed(HR) then
      Result := Format('ITaskbarList2 failed, HRESULT $%.8x', [Cardinal(HR)]);
  except
    on E: Exception do
      Result := 'ITaskbarList2 not available: ' + E.Message;
  end;
end;

procedure TSRStereoRenderer.SetFullScreen(const Value: Boolean);
begin
  FFullScreen := Value;
  if not (csDesigning in ComponentState) then
    ApplyFullScreen;
end;

procedure TSRStereoRenderer.ApplyFullScreen;
var
  Form: TCommonCustomForm;
  Wnd: HWND;
  Style: NativeInt;
  R, WR: TRect;
  Mon: HMONITOR;
  MI: TMonitorInfo;
  Source, TaskbarError: string;
begin
  Form := ViewportForm;
  if (Form = nil) or (Form.Handle = nil) then
    Exit;   // applied when SR starts
  Wnd := FormToHWND(Form);
  Style := GetWindowLongPtr(Wnd, GWL_STYLE);
  if FFullScreen = ((Style and WS_CAPTION) = 0) then
  begin
    // Already as wanted; but full screen set before SR started covers the
    // monitor the form opened on, so move it to the SR display now
    if FFullScreen and FRunning and SRDisplayRect(R) then
    begin
      R.Bottom := R.Bottom - Max(0, FFullScreenGap);
      GetWindowRect(Wnd, WR);
      if WR <> R then
      begin
        SetWindowPos(Wnd, HWND_TOP, R.Left, R.Top, R.Width, R.Height, SWP_NOOWNERZORDER);
        Log(Format('Full screen moved to the SR display: (%d, %d), %d x %d physical pixels',
          [R.Left, R.Top, R.Width, R.Height]));
      end;
    end;
    Exit;
  end;
  if FFullScreen then
  begin
    if FRunning and SRDisplayRect(R) then
      Source := 'the SR display'
    else
    begin
      Mon := MonitorFromWindow(Wnd, MONITOR_DEFAULTTONEAREST);
      MI.cbSize := SizeOf(MI);
      if not GetMonitorInfo(Mon, @MI) then
      begin
        Log('Full screen: no monitor found for the window');
        Exit;
      end;
      R := MI.rcMonitor;
      Source := 'its monitor (SR display not known yet)';
    end;
    R.Bottom := R.Bottom - Max(0, FFullScreenGap);
    Source := Format('%s, %d row(s) left uncovered', [Source, Max(0, FFullScreenGap)]);
    // Lens on before the window changes, not after (see LensWanted)
    if FRunning then
      UpdateLens(True);
    FSavedPlacement.length := SizeOf(FSavedPlacement);
    GetWindowPlacement(Wnd, @FSavedPlacement);
    // Clear WS_MAXIMIZE as well: a maximised window is held to the work
    // area, which leaves the taskbar showing. The saved placement brings
    // the maximised state back on the way out.
    SetWindowLongPtr(Wnd, GWL_STYLE, Style and not (WS_OVERLAPPEDWINDOW or WS_MAXIMIZE));
    SetWindowPos(Wnd, HWND_TOP, R.Left, R.Top, R.Width, R.Height,
      SWP_NOOWNERZORDER or SWP_FRAMECHANGED);
    TaskbarError := MarkFullscreen(Wnd, True);
    Source := Source + ', ' + StrIf(TaskbarError = '', 'taskbar told', TaskbarError);
    GetWindowRect(Wnd, WR);
    Log(Format('Full screen on %s: wanted (%d, %d) %d x %d, window now (%d, %d) %d x %d ' +
      'physical pixels, maximised %s, not re-created',
      [Source, R.Left, R.Top, R.Width, R.Height, WR.Left, WR.Top, WR.Width, WR.Height,
       BoolToStr(IsZoomed(Wnd), True)]));
  end
  else
  begin
    MarkFullscreen(Wnd, False);
    SetWindowLongPtr(Wnd, GWL_STYLE, Style or WS_OVERLAPPEDWINDOW);
    if FSavedPlacement.length = SizeOf(FSavedPlacement) then
      SetWindowPlacement(Wnd, @FSavedPlacement);
    SetWindowPos(Wnd, 0, 0, 0, 0, 0, SWP_NOMOVE or SWP_NOSIZE or SWP_NOZORDER or
      SWP_NOOWNERZORDER or SWP_FRAMECHANGED);
    GetWindowRect(Wnd, R);
    Log(Format('Full screen off: window back at (%d, %d), %d x %d physical pixels',
      [R.Left, R.Top, R.Width, R.Height]));
  end;
end;

procedure TSRStereoRenderer.UpdateLens(Immediate: Boolean);
var
  Want: Boolean;
  Reason: string;
  NowMs: Int64;
begin
  Want := LensWanted(Reason);
  if Want = FLensOn then
  begin
    FLensWantSince := -1;
    Exit;
  end;
  NowMs := FClock.ElapsedMilliseconds;
  if FLensWantSince < 0 then
    FLensWantSince := NowMs;
  if not Immediate and (NowMs - FLensWantSince < FLensSwitchDelay) then
    Exit;
  FLensOn := Want;
  FLensWantSince := -1;
  FLensReason := Reason;
  srb_SetLens(Ord(FLensOn));
  FStereoImageDirty := True;   // a test image is copied flat while the lens is off
  Log(Format('Lens %s (%s)', [StrIf(FLensOn, 'ON', 'OFF: viewport drawn flat'), Reason]));
end;

function TSRStereoRenderer.StoreInitTimeout: Boolean;
begin
  Result := not SameValue(FInitTimeout, DefaultInitTimeout);
end;

procedure TSRStereoRenderer.Loaded;
begin
  inherited;
  if FActive and not (csDesigning in ComponentState) then
  begin
    FStartPending := True;
    HookLoop;
  end;
end;

procedure TSRStereoRenderer.Notification(AComponent: TComponent; Operation: TOperation);
begin
  inherited;
  if (Operation = opRemove) and (AComponent = FViewport) then
  begin
    Stop;
    FViewport := nil;
  end;
end;

procedure TSRStereoRenderer.SetViewport(const Value: TViewport3D);
begin
  if FViewport = Value then
    Exit;
  if FRunning then
    Stop;
  if FViewport <> nil then
    FViewport.RemoveFreeNotification(Self);
  FViewport := Value;
  if FViewport <> nil then
    FViewport.FreeNotification(Self);
end;

procedure TSRStereoRenderer.SetActive(const Value: Boolean);
begin
  if FActive = Value then
    Exit;
  FActive := Value;
  if (csDesigning in ComponentState) or (csLoading in ComponentState) then
    Exit;
  if FActive then
    Start
  else
    Stop;
end;

procedure TSRStereoRenderer.SetVSync(const Value: Boolean);
begin
  FVSync := Value;
  if FRunning then
    srb_SetVSync(Ord(FVSync));
end;

procedure TSRStereoRenderer.SetLatencyFrames(const Value: Integer);
begin
  FLatencyFrames := Max(0, Value);
  if FRunning and (FLatencyFrames > 0) then
    srb_SetLatencyInFrames(FLatencyFrames);
end;

procedure TSRStereoRenderer.SetFocusDistance(const Value: Single);
begin
  FFocusDistance := Max(0.01, Value);
end;

procedure TSRStereoRenderer.SetLoopMode(const Value: TSRLoopMode);
var
  WasHooked: Boolean;
begin
  if FLoopMode = Value then
    Exit;
  WasHooked := FIdleHooked or ((FTimer <> nil) and FTimer.Enabled);
  UnhookLoop;
  FLoopMode := Value;
  if WasHooked then
    HookLoop;
end;

procedure TSRStereoRenderer.Log(const Msg: string);
begin
  if Assigned(FOnLog) then
    FOnLog(Self, Msg);
end;

procedure TSRStereoRenderer.DoError(const Msg: string);
begin
  FLastError := Msg;
  Log('ERROR ' + Msg);
  if Assigned(FOnError) then
    FOnError(Self, Msg);
end;

procedure TSRStereoRenderer.HookLoop;
begin
  case FLoopMode of
    lmIdle:
      if not FIdleHooked then
      begin
        FPrevIdle := Application.OnIdle;
        Application.OnIdle := AppIdle;
        FIdleHooked := True;
      end;
    lmTimer:
      begin
        if FTimer = nil then
        begin
          FTimer := TTimer.Create(nil);
          FTimer.Interval := 1;
          FTimer.OnTimer := TimerTick;
        end;
        FTimer.Enabled := True;
      end;
    lmManual:
      ; // RenderFrame, called by the program, also completes a pending start
  end;
end;

procedure TSRStereoRenderer.UnhookLoop;
begin
  if FIdleHooked then
  begin
    if TMethod(Application.OnIdle).Data = Pointer(Self) then
      Application.OnIdle := FPrevIdle;
    FPrevIdle := nil;
    FIdleHooked := False;
  end;
  if FTimer <> nil then
    FTimer.Enabled := False;
end;

procedure TSRStereoRenderer.AppIdle(Sender: TObject; var Done: Boolean);
begin
  if Assigned(FPrevIdle) then
    FPrevIdle(Sender, Done);
  Tick;
  // Keep the loop running while drawing (Present with vsync paces it); when
  // hidden or minimised let the program sleep until the next message.
  if FRunning and (FWindowVisible = 1) and not FOccluded then
    Done := False;
end;

procedure TSRStereoRenderer.TimerTick(Sender: TObject);
begin
  Tick;
end;

procedure TSRStereoRenderer.Tick;
begin
  if FStartPending or FRunning then
    RenderFrame;
end;

function TSRStereoRenderer.Start: Boolean;
begin
  if csDesigning in ComponentState then
    Exit(False);
  if FRunning then
    Exit(True);
  FStartPending := True;
  Result := TryStart;
  if FStartPending then
    HookLoop;
end;

function TSRStereoRenderer.TryStart: Boolean;
var
  Form: TCommonCustomForm;
  Wnd: HWND;
  RC: Integer;
begin
  Result := False;
  if FViewport = nil then
  begin
    FStartPending := False;
    DoError('Viewport is not assigned');
    Exit;
  end;
  if (FViewport.Root = nil) or not (FViewport.Root.GetObject is TCommonCustomForm) then
    Exit;
  Form := TCommonCustomForm(FViewport.Root.GetObject);
  if (Form.Handle = nil) or not Form.Visible then
    Exit;

  FStartPending := False;
  if not SRBridgeAvailable then
  begin
    FActive := False;
    UnhookLoop;
    DoError(SRBridgeLastError);
    Exit;
  end;

  Wnd := FormToHWND(Form);
  FFormWnd := Wnd;
  srb_SetVSync(Ord(FVSync));
  Log(Format('Starting LeiaSR (timeout %.1f s)', [FInitTimeout]));
  RC := srb_Initialize(Pointer(Wnd), FInitTimeout);
  if RC <> SRB_OK then
  begin
    FActive := False;
    UnhookLoop;
    DoError(Format('LeiaSR initialisation failed (%d): %s', [RC, SRBridgeLastError]));
    Exit;
  end;
  if FLatencyFrames > 0 then
    srb_SetLatencyInFrames(FLatencyFrames);

  FRunning := True;
  FActive := True;
  FWindowVisible := -1;
  FSRRectKnown := SRDisplayRect(FSRRect);

  FViewportOnSR := True;
  FViewportOnSRLogged := False;
  FLastBounds := TRect.Empty;
  FLensOn := True;
  FLensWantSince := -1;
  FLensReason := 'starting';
  FEyesSettled := FSettleTime <= 0;
  FSettleSince := -1;
  FLostSince := -1;
  srb_SetLens(1);
  FLastLogMs := FClock.ElapsedMilliseconds;
  FPrevFrameMs := FClock.Elapsed.TotalMilliseconds;
  FFramesSinceLog := 0;
  FWorstFrameMs := 0;
  FillChar(FResultCounts, SizeOf(FResultCounts), 0);
  FTraceLeft := FTraceFrames;
  FFrameNo := 0;
  HookLoop;
  LogStartDetails;
  if FPlaceFormOnSRDisplay then
    MoveFormToSRDisplay(Form);
  if FFullScreen then
    ApplyFullScreen;
  Result := True;
  if Assigned(FOnStarted) then
    FOnStarted(Self);
end;

procedure TSRStereoRenderer.Stop;
begin
  FStartPending := False;
  UnhookLoop;
  if FRunning then
  begin
    FRunning := False;
    FWeaving := False;
    srb_Finalize;
    Log('Stopped LeiaSR');
    if (FViewport <> nil) and not (csDestroying in FViewport.ComponentState) then
      FViewport.Repaint;
  end;
  FActive := False;
end;

function TSRStereoRenderer.DisplayInfo(out Info: TSRBDisplayInfo): Boolean;
begin
  FillChar(Info, SizeOf(Info), 0);
  Result := FRunning and (srb_GetDisplayInfo(@Info) = SRB_OK);
end;

procedure TSRStereoRenderer.TraceStage(const Stage: string);
begin
  if FTraceLeft > 0 then
    Log(Format('frame %d: %s', [FFrameNo, Stage]));
end;

function TSRStereoRenderer.SRDisplayRect(out R: TRect): Boolean;
var
  B: TSRBRect;
begin
  R := TRect.Empty;
  Result := FRunning and (srb_GetDisplayRect(B) = SRB_OK);
  if Result then
    R := TRect.Create(B[0], B[1], B[2], B[3]);
end;

procedure TSRStereoRenderer.MoveFormToSRDisplay(const Form: TCommonCustomForm);
var
  SR, WR: TRect;
  WasMaximized: Boolean;
  W, H: Integer;
begin
  if not SRDisplayRect(SR) then
  begin
    Log('SR display position unknown; the window stays where it is');
    Exit;
  end;
  GetWindowRect(FFormWnd, WR);
  if SR.Contains(WR.CenterPoint) then
  begin
    Log(Format('Window is on the SR display (%d, %d)-(%d, %d)', [SR.Left, SR.Top, SR.Right, SR.Bottom]));
    Exit;
  end;
  Log(Format('Window centre (%d, %d) is not on the SR display (%d, %d)-(%d, %d); moving it there',
    [WR.CenterPoint.X, WR.CenterPoint.Y, SR.Left, SR.Top, SR.Right, SR.Bottom]));
  WasMaximized := Form.WindowState = TWindowState.wsMaximized;
  if WasMaximized then
    Form.WindowState := TWindowState.wsNormal;
  GetWindowRect(FFormWnd, WR);
  W := Min(WR.Width, SR.Width);
  H := Min(WR.Height, SR.Height);
  SetWindowPos(FFormWnd, 0, SR.Left + (SR.Width - W) div 2, SR.Top + (SR.Height - H) div 2, W, H,
    SWP_NOZORDER or SWP_NOACTIVATE);
  if WasMaximized then
    Form.WindowState := TWindowState.wsMaximized;
end;

procedure TSRStereoRenderer.LogStartDetails;
var
  Info: TSRBDisplayInfo;
  Cx, Cy, W, H: Double;
begin
  Log('SR platform ' + UTF8ToString(srb_GetPlatformVersion));
  if DisplayInfo(Info) then
    Log(Format('Display %dx%d px (panel %dx%d), %.1f x %.1f mm, recommended view %dx%d',
      [Info.resolutionWidth, Info.resolutionHeight, Info.physicalResolutionWidth,
       Info.physicalResolutionHeight, Info.physicalWidthMM, Info.physicalHeightMM,
       Info.recommendedViewWidth, Info.recommendedViewHeight]));
  UpdateWindowBounds;
  if srb_GetWindowRectMM(Cx, Cy, W, H) = SRB_OK then
    Log(Format('Viewport on display: centre (%.1f, %.1f) mm, %.1f x %.1f mm',
      [Cx, Cy, W, H]));
  Log(Format('FocusDistance %.2f, EyeSeparationScale %.2f, EyeSeparationMM %.1f (0 = tracked), ' +
    'LookAround %s, LatencyFrames %d, VSync %s, loop %d, LensMode %d (0 off over controls, ' +
    '1 always on, 2 always off), LensSwitchDelay %d ms, SettleTime %d ms', [FFocusDistance,
    FEyeSeparationScale, FEyeSeparationMM, BoolToStr(FLookAround, True), FLatencyFrames,
    BoolToStr(FVSync, True), Ord(FLoopMode), Ord(FLensMode), FLensSwitchDelay, FSettleTime]));
  if FSRRectKnown then
    Log(Format('Lens control uses the SR display at (%d, %d)-(%d, %d)',
      [FSRRect.Left, FSRRect.Top, FSRRect.Right, FSRRect.Bottom]))
  else
    Log('SR display position unknown: the lens treats every point as on it');
end;

procedure TSRStereoRenderer.LogPeriodic;
const
  NominalTag: array[Boolean] of string = ('', ' NOMINAL');
  IpdTag: array[Boolean] of string = ('', ' IPD-REBUILT');
  LookTag: array[Boolean] of string = (' FIXED-VIEWER', '');
  LensTag: array[Boolean] of string = (' LENS-OFF', '');
var
  NowMs: Int64;
  Secs: Double;
  Stats: TSRBStats;
  Ipd: Single;
begin
  if (FLogInterval <= 0) or not Assigned(FOnLog) then
    Exit;
  NowMs := FClock.ElapsedMilliseconds;
  if NowMs - FLastLogMs < FLogInterval then
    Exit;
  Secs := (NowMs - FLastLogMs) / 1000;
  Ipd := FLeftEyeMM.Distance(FRightEyeMM);
  if FStereoImage <> nil then
    Log('  showing stereo image ' + ExtractFileName(FStereoImageFile));
  Log(Format('%.1f fps (worst %.0f ms) | woven %d 2D %d hidden %d | eyes L%s R%s ipd %.1f%s | ' +
    'cam %s%s',
    [FFramesSinceLog / Secs, FWorstFrameMs, FResultCounts[0], FResultCounts[1],
     FResultCounts[2], FmtPt(FLeftEyeMM), FmtPt(FRightEyeMM), Ipd,
     NominalTag[FUsingNominalEyes], FmtPt(FRefCameraPos), IpdTag[FIpdRepaired] + LookTag[FLookAround] + LensTag[FLensOn]]));
  Log(Format('  viewport c(%.1f, %.1f) %.1fx%.1f mm, view %dx%d | cal R%s U%s F%s tanRef %.4f ' +
    'scale %.5f | L zoom %.4f corner (%.4f, %.4f) shear (%.4f, %.4f) | R zoom %.4f corner (%.4f, %.4f) shear (%.4f, %.4f)',
    [FWinCenterMM.X, FWinCenterMM.Y, FWinSizeMM.Width, FWinSizeMM.Height, FViewSize.cx,
     FViewSize.cy, FmtSign(FCalLeft.SgnR), FmtSign(FCalLeft.SgnU), FmtSign(FCalLeft.SgnF),
     FCalLeft.TanRef, FCalLeft.Scale, FCalLeft.Zoom, FCalLeft.CornerNdc.X, FCalLeft.CornerNdc.Y,
     FCalLeft.ShearX, FCalLeft.ShearY, FCalRight.Zoom, FCalRight.CornerNdc.X, FCalRight.CornerNdc.Y,
     FCalRight.ShearX, FCalRight.ShearY]));
  if srb_GetStats(@Stats) = SRB_OK then
    Log(Format('  bridge: presented %d woven %d 2D %d hidden %d | reinit %d/%d exceptions %d | ' +
      'latency %d us | present hr $%.8x | back buffer %dx%d | weaver %d invalid %d',
      [Int64(Stats.framesSubmitted), Int64(Stats.framesWoven), Int64(Stats.frames2D),
       Int64(Stats.framesOccluded), Int64(Stats.reinitSuccesses), Int64(Stats.reinitAttempts),
       Int64(Stats.exceptions), Int64(Stats.weaverLatencyUs),
       Stats.lastPresentHr, Stats.backBufferWidth, Stats.backBufferHeight, Stats.weaving,
       Stats.contextInvalid]));
  FLastLogMs := NowMs;
  FFramesSinceLog := 0;
  FWorstFrameMs := 0;
  FillChar(FResultCounts, SizeOf(FResultCounts), 0);
end;

function TSRStereoRenderer.UpdateWindowBounds: Boolean;
var
  Scale: Single;
  P: TPointF;
  L, T, R, B, Vis: Integer;
  Centre: TPoint;
  OnSR: Boolean;
begin
  Result := False;
  if (FViewport = nil) or (FViewport.Scene = nil) then
    Exit;
  Scale := FViewport.Scene.GetSceneScale;
  P := FViewport.LocalToAbsolute(PointF(0, 0));
  L := Round(P.X * Scale);
  T := Round(P.Y * Scale);
  R := Round((P.X + FViewport.Width) * Scale);
  B := Round((P.Y + FViewport.Height) * Scale);
  Vis := Ord(FViewport.ParentedVisible and (R > L) and (B > T) and
    IsWindowVisible(FFormWnd) and not IsIconic(FFormWnd));
  if Vis <> FWindowVisible then
  begin
    srb_SetVisible(Vis);
    FWindowVisible := Vis;
  end;
  if Vis = 0 then
    Exit;
  FViewportClientRect := TRect.Create(L, T, R, B);
  Centre := FViewportClientRect.CenterPoint;
  ClientToScreen(FFormWnd, Centre);
  OnSR := (not FSRRectKnown) or FSRRect.Contains(Centre);
  if (OnSR <> FViewportOnSR) or not FViewportOnSRLogged then
  begin
    FViewportOnSR := OnSR;
    FViewportOnSRLogged := True;
    if OnSR then
      Log(Format('Viewport centre (%d, %d) is on the SR display', [Centre.X, Centre.Y]))
    else
      Log(Format('Viewport centre (%d, %d) is NOT on the SR display (%d, %d)-(%d, %d): ' +
        'lens off and drawn flat until it is back', [Centre.X, Centre.Y, FSRRect.Left,
        FSRRect.Top, FSRRect.Right, FSRRect.Bottom]));
  end;
  if (R - L <> FLastBounds.Width) or (B - T <> FLastBounds.Height) then
  begin
    if FLastBounds.Width > 0 then
    begin
      Log(Format('Viewport size changed from %d x %d to %d x %d physical pixels; tracing %d frames',
        [FLastBounds.Width, FLastBounds.Height, R - L, B - T, ResizeTraceFrames]));
      FTraceLeft := Max(FTraceLeft, ResizeTraceFrames);
    end;
  end;
  FLastBounds := TRect.Create(L, T, R, B);
  Result := srb_SetBounds(L, T, R - L, B - T) = SRB_OK;
end;

procedure TSRStereoRenderer.RenderFrame;
var
  Ctx: TContext3D;
  VP: IViewport3D;
  Cam: TCamera;
  L, R: TSRBVec3;
  EL, ER, Mid, Dir: TPoint3D;
  Cx, Cy, Wmm, Hmm, NowMs, Sep: Double;
  W, H, Pitch, Fmt, RC: Integer;
  Form: TCommonCustomForm;
begin
  if FInRender or (FViewport = nil) then
    Exit;
  if FStartPending and not TryStart then
    Exit;
  if not FRunning then
    Exit;
  // FMX re-creates the native window when BorderStyle, FullScreen and so on
  // change; the child window died with the old one, so start again.
  if (FViewport.Root <> nil) and (FViewport.Root.GetObject is TCommonCustomForm) then
  begin
    Form := TCommonCustomForm(FViewport.Root.GetObject);
    if (Form.Handle <> nil) and (FormToHWND(Form) <> FFormWnd) then
    begin
      Log('Form window was re-created; restarting LeiaSR');
      Stop;
      Start;
      Exit;
    end;
  end;
  FInRender := True;
  Inc(FFrameNo);
  try
    try
      // Keep full screen exactly on the SR display: moving a window between
      // monitors of different scaling makes Windows resize it (the owner's
      // 00:39 run went from 3840 x 2160 to 3441 x 1440 that way)
      if FFullScreen then
        ApplyFullScreen;
      TraceStage('placing window');
      if not UpdateWindowBounds then
        Exit;
      if not Supports(FViewport, IViewport3D, VP) then
        Exit;
      Ctx := VP.Context;
      Cam := VP.CurrentCamera;
      if (Ctx = nil) or (Cam = nil) then
        Exit;
      W := Round(Ctx.Width);
      H := Round(Ctx.Height);
      if (W < 2) or (H < 2) then
        Exit;
      TraceStage(Format('context %d x %d (%.1f x %.1f), format %d', [W, H, Ctx.Width, Ctx.Height,
        Ord(Ctx.PixelFormat)]));

      NowMs := FClock.Elapsed.TotalMilliseconds;
      FWorstFrameMs := Max(FWorstFrameMs, NowMs - FPrevFrameMs);
      FPrevFrameMs := NowMs;

      if dsTracking in FDiagnosticSkip then
      begin
        EL := Point3D(0, 0, 0);
        ER := EL;
      end
      else
      begin
        srb_GetEyePositions(L, R);
        EL := Point3D(L[0], L[1], L[2]);
        ER := Point3D(R[0], R[1], R[2]);
      end;
      TraceStage('eyes L' + FmtPt(EL) + ' R' + FmtPt(ER));
      FUsingNominalEyes := (EL.Z < MinEyeDistanceMM) or (ER.Z < MinEyeDistanceMM);
      if FUsingNominalEyes then
      begin
        EL := Point3D(NominalLeftX, 0, NominalZ);
        ER := Point3D(NominalRightX, 0, NominalZ);
      end;
      // Before the tracker locks on, the weaver reports both eyes at the same
      // point (the first log had L = R = (0, 100, 600)), and while it acquires
      // the separation can be far off (16 mm). Keep the head position but use
      // a normal separation, so the two views are never the same picture.
      FIpdRepaired := not InRange(EL.Distance(ER), MinIpdMM, MaxIpdMM);
      if FIpdRepaired then
      begin
        Mid := (EL + ER) * 0.5;
        EL := Mid - Point3D(NominalIpdMM * 0.5, 0, 0);
        ER := Mid + Point3D(NominalIpdMM * 0.5, 0, 0);
        TraceStage('eye separation out of range; rebuilt around the midpoint');
      end;
      if FEyeSeparationMM > 0 then
      begin
        Mid := (EL + ER) * 0.5;
        Dir := (ER - EL).Normalize;
        EL := Mid - Dir * (FEyeSeparationMM * 0.5);
        ER := Mid + Dir * (FEyeSeparationMM * 0.5);
      end;
      if not SameValue(FEyeSeparationScale, 1.0) then
      begin
        Mid := (EL + ER) * 0.5;
        EL := Mid + (EL - Mid) * FEyeSeparationScale;
        ER := Mid + (ER - Mid) * FEyeSeparationScale;
      end;
      FLeftEyeMM := EL;
      FRightEyeMM := ER;

      if srb_GetWindowRectMM(Cx, Cy, Wmm, Hmm) <> SRB_OK then
        Exit;
      TraceStage(Format('window c(%.1f, %.1f) %.1f x %.1f mm', [Cx, Cy, Wmm, Hmm]));
      if (Wmm <= 0) or (Hmm <= 0) then
        Exit;
      FWinCenterMM := PointF(Cx, Cy);
      FWinSizeMM := TSizeF.Create(Wmm, Hmm);
      if not FLookAround then
      begin
        // Fixed viewer straight in front of the viewport, real separation:
        // depth, but the picture no longer moves with the head
        Sep := EL.Distance(ER);
        EL := Point3D(Cx - Sep * 0.5, Cy, NominalZ);
        ER := Point3D(Cx + Sep * 0.5, Cy, NominalZ);
        FLeftEyeMM := EL;
        FRightEyeMM := ER;
      end;
      UpdateSettling(not (FUsingNominalEyes or FIpdRepaired or (dsTracking in FDiagnosticSkip)),
        (EL + ER) * 0.5);
      UpdateLens(False);
      if not (FLensOn and FEyesSettled) then
      begin
        // No lens: both eyes see the same pixels, so draw one view; the
        // weave of two equal views is that view. Also while the tracker
        // searches (the lens is left as it is, to avoid switching it): from
        // a fixed viewer, so the picture does not slide.
        if FEyesSettled then
          Mid := (EL + ER) * 0.5
        else
          Mid := Point3D(Cx, Cy, NominalZ);
        EL := Mid;
        ER := Mid;
      end;
      FViewSize := TSize.Create(W, H);
      FRefCameraPos := Point3D(Cam.AbsolutePosition.X, Cam.AbsolutePosition.Y,
        Cam.AbsolutePosition.Z);

      if FStereoImage <> nil then
      begin
        // Test image: weave it exactly as given, no 3D rendering
        CopyStereoImage(Round(Ctx.Width), Round(Ctx.Height), W, H, Pitch);
        Fmt := FStereoImageFormat;
      end
      else
      begin
        Pitch := W * 2 * 4;
        if Length(FBuffer) <> Pitch * H then
          SetLength(FBuffer, Pitch * H);
        if not (dsRender in FDiagnosticSkip) then
        begin
          TraceStage(Format('rendering left eye into %d-byte buffer, pitch %d', [Length(FBuffer), Pitch]));
          RenderEye(Ctx, Cam, EL, @FBuffer[0], Pitch, FCalLeft);
          TraceStage('rendering right eye');
          RenderEye(Ctx, Cam, ER, @FBuffer[W * 4], Pitch, FCalRight);
          TraceStage('both eyes copied');
          // Put the normal camera back so picking (ObjectAtPoint, Pick) works
          Ctx.SetCameraMatrix(Cam.CameraMatrix);
          Ctx.SetCameraAngleOfView(Cam.AngleOfView);
        end;

        if Ctx.PixelFormat = TPixelFormat.RGBA then
          Fmt := SRB_FMT_RGBA8
        else
          Fmt := SRB_FMT_BGRA8;
        // The scene overwrote the buffer: a test image must be copied again
        FStereoImageDirty := True;
      end;
      if dsSubmit in FDiagnosticSkip then
        RC := SRB_S_2D_FALLBACK
      else
      begin
        TraceStage('submitting');
        RC := srb_SubmitViews(@FBuffer[0], W, H, Pitch, Fmt);
        TraceStage(Format('submitted, result %d', [RC]));
      end;
      FWeaving := RC = SRB_OK;
      FOccluded := RC = SRB_S_OCCLUDED;
      if RC < 0 then
      begin
        DoError(Format('LeiaSR present failed (%d): %s', [RC, SRBridgeLastError]));
        Stop;
        Exit;
      end;
      if RC <= 2 then
        Inc(FResultCounts[RC]);
      Inc(FFramesSinceLog);

      PollEvents;
      LogPeriodic;
      if Assigned(FOnEyesUpdated) then
        FOnEyesUpdated(Self, FLeftEyeMM, FRightEyeMM);
      TraceStage('done');
      if FTraceLeft > 0 then
        Dec(FTraceLeft);
    except
      on E: Exception do
      begin
        Stop;
        DoError('LeiaSR render error: ' + E.ClassName + ': ' + E.Message);
      end;
    end;
  finally
    FInRender := False;
  end;
end;

procedure TSRStereoRenderer.RenderEye(const Ctx: TContext3D; const RefCamera: TCamera;
  const EyeMM: TPoint3D; Dest: Pointer; Pitch: Integer; out Cal: TSREyeCalibration);
var
  RefView, EyeView, OffAxis, Proj: TMatrix3D;
  V: TVector3D;
  Eye: TPoint3D;
  Dx, Dy, Ez, A, B, C, TanEye: Single;

  { Takes a point in the reference camera's view space to clip space.
    @param(X view x)
    @param(Y view y)
    @param(Z view z)
    @returns(the clip-space point) }
  function ClipOfView(const X, Y, Z: Single): TVector3D;
  begin
    Result := TVector3D.Create(X, Y, Z, 1) * Proj;
  end;

begin
  FillChar(Cal, SizeOf(Cal), 0);
  if not Ctx.BeginScene then
  begin
    TraceStage('  BeginScene returned False');
    Exit;
  end;
  try
    { How FMX draws (FMX.Types3D, Delphi 13): the shaders get
        CurrentMatrix * CurrentCameraMatrix * CurrentProjectionMatrix,
      so the matrix given to SetCameraMatrix IS the view matrix (world to
      view); TCamera.CameraMatrix is one, made with CreateLookAtDirRH. The
      projection is made from the angle of view only when the context is
      created or resized, so SetCameraAngleOfView has no effect between
      frames: the projection stays the viewport camera's. So the eye's whole
      off-axis projection is built into the view matrix, and FMX's own
      projection is used as it is. }
    RefView := RefCamera.CameraMatrix;
    Ctx.SetCameraMatrix(RefView);
    Proj := Ctx.CurrentProjectionMatrix;

    // Measure the view space's conventions rather than assume them: which
    // axis points forward, which right and which up on the screen
    V := ClipOfView(0, 0, 1);
    Cal.SgnF := IfThen(V.W >= 0, 1, -1);
    V := ClipOfView(1, 0, 10 * Cal.SgnF);
    Cal.SgnR := IfThen(V.X * V.W >= 0, 1, -1);
    V := ClipOfView(0, 1, 10 * Cal.SgnF);
    Cal.SgnU := IfThen(V.Y * V.W >= 0, 1, -1);   // clip +y is the top of the image
    Cal.TanRef := 1 / Abs(Proj.m22);

    // The viewport's rectangle lies FocusDistance in front of the reference
    // camera and fills its vertical field of view there.
    Cal.Scale := (FFocusDistance * Cal.TanRef) / (FWinSizeMM.Height * 0.5);
    Dx := (EyeMM.X - FWinCenterMM.X) * Cal.Scale;
    Dy := (EyeMM.Y - FWinCenterMM.Y) * Cal.Scale;
    Ez := EyeMM.Z * Cal.Scale;

    // The eye in the reference camera's view space (the glass plane is
    // FocusDistance ahead), and the view from there: the reference view
    // moved so the eye is at the origin.
    Eye := Point3D(Cal.SgnR * Dx, Cal.SgnU * Dy, Cal.SgnF * (FFocusDistance - Ez));
    EyeView := RefView * TMatrix3D.CreateTranslation(Point3D(-Eye.X, -Eye.Y, -Eye.Z));

    // Off-axis: from the eye, the viewport's centre is at (A, B, C). The
    // shear x' = x - (A/C)z, y' = y - (B/C)z moves it onto the view axis, so
    // FMX's symmetric frustum becomes the asymmetric window frustum
    // (Kooima's generalised perspective projection, as in the SDK sample),
    // and the zoom TanRef / TanEye makes the reference field of view the
    // eye's, so the viewport exactly fills the image from where the eye is.
    A := -Cal.SgnR * Dx;
    B := -Cal.SgnU * Dy;
    C := Cal.SgnF * Ez;
    Cal.ShearX := A / C;
    Cal.ShearY := B / C;
    TanEye := (FWinSizeMM.Height * 0.5) / EyeMM.Z;
    Cal.Zoom := Cal.TanRef / TanEye;
    OffAxis := TMatrix3D.Identity;
    OffAxis.m11 := Cal.Zoom;
    OffAxis.m22 := Cal.Zoom;
    OffAxis.m31 := -Cal.Zoom * Cal.ShearX;
    OffAxis.m32 := -Cal.Zoom * Cal.ShearY;
    Ctx.SetCameraMatrix(EyeView * OffAxis);

    // Check with the formula the shaders use: the viewport's top-right
    // corner on the glass must land on the image's top-right corner, (1, 1)
    // in normalised device coordinates.
    V := TVector3D.Create(Cal.SgnR * FWinSizeMM.Width * 0.5 * Cal.Scale,
      Cal.SgnU * FWinSizeMM.Height * 0.5 * Cal.Scale, Cal.SgnF * FFocusDistance, 1) *
      RefView.Inverse * Ctx.CurrentCameraMatrix * Ctx.CurrentProjectionMatrix;
    if V.W <> 0 then
      Cal.CornerNdc := PointF(V.X / V.W, V.Y / V.W);
    TraceStage(Format('  projection set: scale %.5f zoom %.4f shear (%.4f, %.4f) corner (%.4f, %.4f)',
      [Cal.Scale, Cal.Zoom, Cal.ShearX, Cal.ShearY, Cal.CornerNdc.X, Cal.CornerNdc.Y]));
    RenderScene(Ctx);
    TraceStage('  scene rendered');
  finally
    Ctx.EndScene;
  end;
  TraceStage(Format('  copying %d x %d to buffer', [Round(Ctx.Width), Round(Ctx.Height)]));
  Ctx.CopyToBits(Dest, Pitch, Rect(0, 0, Round(Ctx.Width), Round(Ctx.Height)));
  TraceStage('  copied');
end;

procedure TSRStereoRenderer.RenderScene(const Ctx: TContext3D);
var
  VP: IViewport3D;
  Light: TLight;
  Child: TFmxObject;
  P, D: TVector3D;
  I: Integer;
begin
  Ctx.Clear([TClearTarget.Color, TClearTarget.Depth], FViewport.Color, 1.0, 0);
  Ctx.Lights.Clear;
  if Supports(FViewport, IViewport3D, VP) then
    for I := 0 to VP.LightCount - 1 do
    begin
      Light := VP.Lights[I];
      if (Light = nil) or not Light.Enabled then
        Continue;
      P := Light.AbsolutePosition;
      D := Light.AbsoluteDirection;
      Ctx.Lights.Add(TLightDescription.Create(True, Light.Color, Light.LightType,
        Light.SpotCutOff, Light.SpotExponent, Point3D(P.X, P.Y, P.Z), Point3D(D.X, D.Y, D.Z)));
    end;
  for I := 0 to FViewport.ChildrenCount - 1 do
  begin
    Child := FViewport.Children[I];
    if (Child is TControl3D) and TControl3D(Child).Visible then
      TControl3D(Child).RenderInternal;
  end;
end;

procedure TSRStereoRenderer.PollEvents;
var
  Ev: TSRBSystemEvent;
  EvName, Msg: string;
begin
  while srb_PollSystemEvent(@Ev) = 1 do
  begin
    EvName := SREventTypeName(Ev.eventType);
    Msg := UTF8ToString(PAnsiChar(@Ev.message[0]));
    Log('SR event ' + EvName + ': ' + Msg);
    if Assigned(FOnSystemEvent) then
      FOnSystemEvent(Self, Ev.eventType, EvName, Msg);
  end;
end;

end.

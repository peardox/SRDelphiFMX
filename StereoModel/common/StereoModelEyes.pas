//** @abstract(Glasses-free 3D for a Gorilla3D view: TPeardoxGorillaEyes draws it once per eye,
//** from where each eye really is, and hands the pair to TLenticularDisplay to weave.)
//**
//** Kept in the program until it is settled; then it becomes a component in lib. Each frame
//** it:
//**
//** @orderedList(
//**   @item(reads the tracked eyes (millimetres from the display's centre) from
//**     TLenticularDisplay, or uses a fixed viewer in front of the view when the eyes are not
//**     tracked or LookAround is off, with the saved eye separation;)
//**   @item(for each eye, puts the orbital camera's own Gorilla3D camera where that eye is,
//**     looking straight ahead (parallel to the orbit camera), renders the viewport
//**     (ManualRendering, RenderManual), and takes the part of the picture where the display's
//**     glass is, scaled to the view the display weaves;)
//**   @item(puts the camera back exactly as it was;)
//**   @item(hands the two views to the bridge: on the GPU (zero copy, TPeardoxGLInterop) where
//**     the bridge and OpenGL allow, otherwise through screenshots copied side by side.)
//** )
//**
//** The geometry is the per-eye off-axis view of the stereo renderer, Lenticular.StereoViewport
//** (Kooima's generalised perspective projection). The orbit centre, the target, is at the target depth
//** D in front of the orbit camera, and that plane is the glass: the view's rectangle on the
//** display fills the orbit camera's vertical field of view there, which sets the scale, scene
//** units per millimetre. An eye at (dx, dy, dz) mm from the view's centre goes to
//** (dx, -dy, -dz) times the scale in the orbit camera's own frame (FMX's Y is down, the
//** display's up). Seen from there the glass is off to one side and smaller than the picture;
//** that part of the picture, cut out and scaled to fill the view, is exactly what the eye
//** would see through the glass. The stereo renderer builds the cut and the zoom into FMX's view
//** matrix; Gorilla3D 1.5.3 takes no matrix of ours and draws no change of field of view made while
//** running, so here the cut is made when the picture is copied, and the picture is rendered
//** RenderScale times the view's size each way so the part is still sharp.
//**
//** Three of the display settings change this (TLenticularDisplaySettings): PerEyeView off puts
//** each eye at the orbit camera's distance in the direction the real eye is, so the glass
//** fills the picture (no zoom, rendered at the view's size: full speed, the depth
//** exaggerated); RenderScale sets how much larger than the view the picture is rendered;
//** Weave off draws one view from between the eyes for both, with the lens off
//** (TLenticularDisplay.Flat), for screen recordings.
//**
//** Frames are drawn whenever the program is idle (Application.OnIdle, any handler already
//** there still called), so they come as fast as they can be drawn while mouse, keyboard,
//** paints and timers are still handled in between. A timer draws one if none has come for
//** PEARDOX_EYES_WATCHDOG_MS, in case something keeps the program from going idle.
unit StereoModelEyes;

{
  Glasses-free 3D for a Gorilla3D view: per eye, the orbital camera's
  Gorilla3D camera goes where the tracked eye is (scaled so the view fills
  the field of view at the target depth, the glass), parallel to the orbit
  camera; RenderManual; the glass's part of the picture is cut out and
  scaled to the woven view - on the GPU (TPeardoxGLInterop) or from a
  screenshot. The per-eye off-axis view of the stereo renderer, made in the copy as
  Gorilla3D takes no projection of ours. Frames when idle, a timer as
  watchdog.
}

interface

uses
  System.SysUtils, System.Classes, System.Types, System.UITypes, System.Math,
  System.Math.Vectors, System.Diagnostics,
  FMX.Types, FMX.Types3D, FMX.Controls3D, FMX.Graphics, FMX.Forms,
  Gorilla.Viewport, Gorilla.Camera, Gorilla.Model, Spritely.OrbitalCamera, Lenticular.Display,
  Lenticular.Display.Settings, LenticularBridge.Api, StereoModelGLInterop;

const
  //** @abstract(Milliseconds without a frame after which the watchdog timer draws one.)
  PEARDOX_EYES_WATCHDOG_MS = 50;
  //** @abstract(Distance in millimetres of the fixed viewer used when the eyes are not tracked
  //** or LookAround is off.)
  PEARDOX_EYES_NOMINAL_VIEWER_MM = 650;
  //** @abstract(The nearest an eye is taken to be to the glass, in millimetres, so a bad reading
  //** cannot throw the camera far out.)
  PEARDOX_EYES_MIN_EYE_DISTANCE_MM = 100;
  //** @abstract(The view size used when the display does not give its recommended one.)
  PEARDOX_EYES_DEFAULT_VIEW_WIDTH = 1920;
  //** @abstract(See PEARDOX_EYES_DEFAULT_VIEW_WIDTH.)
  PEARDOX_EYES_DEFAULT_VIEW_HEIGHT = 1080;

type
  //** @abstract(A line for the log.)
  //**
  //** @param(Sender The TPeardoxGorillaEyes.)
  //**
  //** @param(AText The line.)
  TPeardoxGorillaEyesLogEvent = procedure(Sender: TObject; const AText: string) of object;

  //** @abstract(Where one eye is drawn from and what of its picture is kept.)
  TPeardoxEyeView = record
    //** @abstract(The eye's camera, in the orbit camera's own frame (its parent's
    //** coordinates), scene units.)
    Camera: TPoint3D;
    //** @abstract(The glass's part of the picture, as fractions of its width and height from
    //** its top-left corner; it may reach outside 0..1, where the picture has nothing.)
    Part: TRectF;
  end;

  //** @abstract(Draws the Gorilla3D view once per eye and hands the pair to TLenticularDisplay to
  //** weave; see the unit description.)
  //**
  //** Set Display, Camera and Viewport, then Start once Display is running (its OnStarted), and
  //** Stop before it stops.
  TPeardoxGorillaEyes = class(TComponent)
  private
    //** @abstract(See Display.)
    FDisplay: TLenticularDisplay;
    //** @abstract(See Camera.)
    FCamera: TSpritelyOrbitalCamera;
    //** @abstract(See Viewport.)
    FViewport: TGorillaViewport;
    //** @abstract(See Active.)
    FActive: Boolean;
    //** @abstract(Draws a frame when none has come from the idle loop for a while.)
    FWatchdog: TTimer;
    //** @abstract(The Application.OnIdle handler there before Start, called first and put back
    //** by Stop.)
    FSavedIdle: TIdleEvent;
    //** @abstract(True while AppIdle is Application.OnIdle.)
    FIdleHooked: Boolean;
    //** @abstract(When the last frame was drawn (TThread.GetTickCount64).)
    FLastFrameTick: UInt64;
    //** @abstract(Frames drawn by the watchdog since the last log line.)
    FWatchdogFrames: Integer;
    //** @abstract(See ZeroCopy.)
    FZeroCopy: Boolean;
    //** @abstract(True once zero copy has failed to start on this device: the screenshot route
    //** is used until the bridge's device changes.)
    FZeroCopyFailed: Boolean;
    //** @abstract(The device zero copy failed on, so a new one is tried again.)
    FZeroCopyFailedOn: Pointer;
    //** @abstract(The eye textures OpenGL draws into for zero copy; nil until first used.)
    FInterop: TPeardoxGLInterop;
    //** @abstract(OpenGL errors seen so far after RenderManual (Gorilla3D's) and after the
    //** copy (ours), each logged the first time: they are taken, as FMX's next BeginScene
    //** fails on any.)
    FGLErrorsLogged: array[0..1] of Cardinal;
    //** @abstract(Each eye's view as the display weaves it, in pixels: its recommended view,
    //** read at Start.)
    FViewWidth: Integer;
    //** @abstract(See FViewWidth.)
    FViewHeight: Integer;
    //** @abstract(See OnLog.)
    FOnLog: TPeardoxGorillaEyesLogEvent;
    //** @abstract(The side-by-side image handed to the bridge on the screenshot route, kept
    //** between frames.)
    FBuffer: TBytes;
    //** @abstract(The source column for each column of a view on the screenshot route, -1 for
    //** none, kept between frames.)
    FColumns: TArray<Integer>;
    //** @abstract(The viewport's UseFixedFrameRate before Start, put back by Stop.)
    FSavedFixedRate: Boolean;
    //** @abstract(The viewport's ManualRendering before Start, put back by Stop.)
    FSavedManual: Boolean;
    //** @abstract(True while a frame is being drawn, so a timer tick cannot start another.)
    FInFrame: Boolean;
    //** @abstract(Frames since the last log line.)
    FFrames: Integer;
    //** @abstract(See WovenFrames.)
    FWovenFrames: Int64;
    //** @abstract(Milliseconds spent since the last log line in RenderManual, both eyes.)
    FRenderMs: Double;
    //** @abstract(Milliseconds spent getting the glass's part into the views: the GPU copy, or
    //** MakeScreenshot and the copy through the CPU.)
    FCopyMs: Double;
    //** @abstract(Milliseconds spent handing the views to the bridge.)
    FSubmitMs: Double;
    //** @abstract(The longest whole frame since the last log line, in milliseconds.)
    FWorstMs: Double;
    //** @abstract(When the last log line was written (TThread.GetTickCount64).)
    FLastLogTick: UInt64;
    //** @abstract(The last frame's scale, scene units per millimetre.)
    FLastScale: Single;
    //** @abstract(The depth the scale is worked out at, scene units along the line of sight:
    //** the model's (ModelDepth), set by ViewScale each frame.)
    FScaleDepth: Single;
    //** @abstract(The orbit camera's projection, read by ViewScale each frame: 1 / tan(half the
    //** field of view) across.)
    FProjX: Single;
    //** @abstract(The same up and down.)
    FProjY: Single;
    //** @abstract(The last frame's views: left, right.)
    FLastViews: array[0..1] of TPeardoxEyeView;
    //** @abstract(The last frame's view size and route, for the log.)
    FLastViewInfo: string;
    //** @abstract(Where the last frame's eyes came from, for the log.)
    FLastEyesFrom: string;
    //** @abstract(The eyes the last frame was drawn from (after the saved separation),
    //** millimetres: left, right.)
    FLastEyes: array[0..1] of TPoint3D;
    //** @abstract(The last frame's rate and timings, as logged once a second, for LogSnapshot.)
    FLastRateText: string;
    //** @abstract(Sets Viewport, watching for it being freed.)
    //**
    //** @param(AValue The viewport.)
    procedure SetViewport(const AValue: TGorillaViewport);
    //** @abstract(Sets Camera, watching for it being freed.)
    //**
    //** @param(AValue The orbital camera.)
    procedure SetCamera(const AValue: TSpritelyOrbitalCamera);
    //** @abstract(Sets Display, watching for it being freed.)
    //**
    //** @param(AValue The TLenticularDisplay.)
    procedure SetDisplay(const AValue: TLenticularDisplay);
    //** @abstract(Passes a line to OnLog.)
    //**
    //** @param(AText The line.)
    procedure Log(const AText: string);
    //** @abstract(Draws and submits one frame.)
    procedure Frame;
    //** @abstract(Application.OnIdle while Active: calls the handler that was there, draws a
    //** frame and asks to be called again.)
    //**
    //** @param(Sender The application.)
    //**
    //** @param(Done Set to False, so idle calls keep coming.)
    procedure AppIdle(Sender: TObject; var Done: Boolean);
    //** @abstract(The watchdog: draws a frame if none has come for PEARDOX_EYES_WATCHDOG_MS.)
    //**
    //** @param(Sender FWatchdog.)
    procedure WatchdogTick(Sender: TObject);
    //** @abstract(The two eyes to draw from, in millimetres from the display's centre.)
    //**
    //** @param(ALeft Set to the left eye.)
    //**
    //** @param(ARight Set to the right eye.)
    procedure EyePair(out ALeft, ARight: TPoint3D);
    //** @abstract(The scale of this frame: the view's height on the display over the height
    //** the orbit camera's field of view takes in at the model's depth (ModelDepth), so a
    //** right drag of the target, the glass, moves the glass and the viewer together without
    //** sliding the model across the view.)
    //**
    //** The field of view is read through the camera's own projection
    //** (TSpritelyOrbitalGorillaCamera.ProjectToView), into FProjX and FProjY, so Gorilla3D's
    //** convention and the viewport's shape are as Gorilla3D draws them.
    //**
    //** @param(AScale Set to scene units per millimetre.)
    //**
    //** @returns(False if the view's place on the display or the viewport's size is not known
    //** yet.)
    function ViewScale(out AScale: Single): Boolean;
    //** @abstract(How far the model's middle is in front of the orbit camera, along its line of
    //** sight: Camera.Subject's box; the target depth if there is no Subject, or it is behind
    //** the camera or round it.)
    //**
    //** @returns(The depth in scene units.)
    function ModelDepth: Single;
    //** @abstract(Where one eye is drawn from and the glass's part of its picture.)
    //**
    //** @param(AEyeMM The eye, millimetres from the display's centre.)
    //**
    //** @param(AScale The frame's scale (ViewScale).)
    //**
    //** @param(AView Set to the camera's place and the part.)
    //**
    //** @returns(False if the glass cannot be seen from there.)
    function EyeView(const AEyeMM: TPoint3D; AScale: Single; out AView: TPeardoxEyeView): Boolean;
    //** @abstract(Renders the view from one eye: the camera put there, parallel to the orbit
    //** camera, and RenderManual.)
    //**
    //** @param(ACamera The camera's place (TPeardoxEyeView.Camera).)
    procedure RenderFrom(const ACamera: TPoint3D);
    //** @abstract(Renders one eye's view and takes its picture.)
    //**
    //** @param(ACamera The camera's place.)
    //**
    //** @returns(The picture, for the caller to free; nil if Gorilla3D gave none.)
    function RenderEye(const ACamera: TPoint3D): TBitmap;
    //** @abstract(Zero copy: renders one eye's view and copies the glass's part into the eye's
    //** texture.)
    //**
    //** @param(AEye 0 left, 1 right.)
    //**
    //** @param(AView The eye's view.)
    //**
    //** @returns(False if the picture was not where, or the size, the textures expect.)
    function RenderEyeGPU(AEye: Integer; const AView: TPeardoxEyeView): Boolean;
    //** @abstract(Straight after a RenderManual (OpenGL current): makes FInterop for the
    //** bridge's device and the size Gorilla3D draws at, if zero copy is wanted and not made
    //** yet or out of date.)
    procedure PrepareZeroCopy;
    //** @abstract(True if this frame can go by zero copy: FInterop ready on the bridge's
    //** current device.)
    //**
    //** @returns(Whether to.)
    function CanZeroCopy: Boolean;
    //** @abstract(TPeardoxGLInterop's lines, to the log.)
    //**
    //** @param(AText The line.)
    procedure InteropLog(const AText: string);
    //** @abstract(Logs an OpenGL error the first time it is seen at a place.)
    //**
    //** @param(AWhere 0 after RenderManual, 1 after the copy.)
    //**
    //** @param(AError The error, 0 for none.)
    procedure NoteGLError(AWhere: Integer; AError: Cardinal);
    //** @abstract(Copies the glass's part of one picture into its half of FBuffer, scaled to
    //** the view (the nearest pixel), black where the part reaches outside the picture.)
    //**
    //** @param(AData The picture, mapped for reading.)
    //**
    //** @param(AWidth The picture's width in pixels.)
    //**
    //** @param(AHeight The picture's height in pixels.)
    //**
    //** @param(APart The part, as fractions of the picture (TPeardoxEyeView.Part).)
    //**
    //** @param(AX0 Byte offset of its half within each row of FBuffer.)
    //**
    //** @param(APitch Bytes per row of FBuffer.)
    procedure CopyPart(const AData: TBitmapData; AWidth, AHeight: Integer; const APart: TRectF;
      AX0, APitch: Integer);
    //** @abstract(Copies the glass's parts of the two pictures side by side into FBuffer and
    //** submits them.)
    //**
    //** @param(ALeft The left eye's picture.)
    //**
    //** @param(ARight The right eye's picture.)
    procedure Submit(ALeft, ARight: TBitmap);
  protected
    //** @abstract(Forgets a linked component when it is freed, stopping first.)
    //**
    //** @param(AComponent The component going or coming.)
    //**
    //** @param(Operation Whether it is being inserted or removed.)
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
  public
    //** @abstract(Creates it, not active.)
    //**
    //** @param(AOwner The owner, normally the form.)
    constructor Create(AOwner: TComponent); override;
    //** @abstract(Stops and frees it.)
    destructor Destroy; override;
    //** @abstract(Starts drawing: the viewport to manual rendering, Display set Weaving, the
    //** frames begun.)
    //**
    //** @returns(True if it started; False, with the reason logged, if the display is not running
    //** or something is not set.)
    function Start: Boolean;
    //** @abstract(Stops drawing: Display's Weaving off and the viewport's rendering put back.)
    procedure Stop;
    //** @abstract(Logs everything that sets what the viewer sees, as one block marked
    //** SNAPSHOT, in the same terms as the stereo renderer's (Lenticular.StereoViewport)
    //** LogSnapshot, so a view that looks right there can be compared with this one.)
    //**
    //** @param(ANote A line from the program to head the block (the view's angles, say); empty
    //** for none.)
    procedure LogSnapshot(const ANote: string);
    //** @abstract(True while frames are drawn.)
    property Active: Boolean read FActive;
    //** @abstract(Frames the bridge has woven (it answered LNB_OK) since Start.)
    property WovenFrames: Int64 read FWovenFrames;
    //** @abstract(The TLenticularDisplay the frames are woven by.)
    property Display: TLenticularDisplay read FDisplay write SetDisplay;
    //** @abstract(The orbital camera: its Gorilla3D camera is the one moved for each eye, and its
    //** Distance is the target depth, the glass.)
    property Camera: TSpritelyOrbitalCamera read FCamera write SetCamera;
    //** @abstract(The viewport drawn.)
    property Viewport: TGorillaViewport read FViewport write SetViewport;
    //** @abstract(True (the default) to hand the bridge Gorilla3D's pictures on the GPU
    //** (TPeardoxGLInterop) where the bridge, the driver and OpenGL allow, instead of
    //** MakeScreenshot, a copy through the CPU and an upload; False always to take the
    //** screenshots.)
    property ZeroCopy: Boolean read FZeroCopy write FZeroCopy;
    //** @abstract(True if zero copy can be tried: wanted, and the bridge gives its device
    //** (TLenticularDisplay.BridgeDevice). The program then sizes the viewport in logical units,
    //** as Gorilla3D draws it in those.)
    //**
    //** @returns(Whether.)
    function ZeroCopyPossible: Boolean;
    //** @abstract(How many times the woven view's size, each way, the program should make the
    //** viewport while weaving: the display setting RenderScale, kept to
    //** LENTICULAR_MIN_RENDER_SCALE .. LENTICULAR_MAX_RENDER_SCALE, with PerEyeView; 1 without it,
    //** as the whole picture is then woven.)
    //**
    //** The glass takes up only part of each eye's picture with PerEyeView: about half its
    //** height with a 45 degree field of view and the viewer some 85 cm away, so at 2 that
    //** part is about the view's size and stays sharp (owner, 7 November 2026: sharp rather
    //** than fast; 46-48 fps against about 100 at 1).
    //**
    //** @returns(The scale.)
    function RenderScale: Single;
    //** @abstract(Lets go of zero copy's textures and its OpenGL objects (its context made
    //** current for it): call while the viewport's OpenGL context still exists, in FormClose
    //** before the display stops, and when the display has stopped.)
    procedure ReleaseZeroCopy;
    //** @abstract(Every line of its log: the start, and once a second the frame rate, the time
    //** in each stage, the scale and each eye's part of the picture.)
    property OnLog: TPeardoxGorillaEyesLogEvent read FOnLog write FOnLog;
  end;

implementation

uses
  System.StrUtils;

{ TPeardoxGorillaEyes }

constructor TPeardoxGorillaEyes.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FZeroCopy := True;
  FViewWidth := PEARDOX_EYES_DEFAULT_VIEW_WIDTH;
  FViewHeight := PEARDOX_EYES_DEFAULT_VIEW_HEIGHT;
  FWatchdog := TTimer.Create(Self);
  FWatchdog.Enabled := False;
  FWatchdog.Interval := PEARDOX_EYES_WATCHDOG_MS;
  FWatchdog.OnTimer := WatchdogTick;
end;

destructor TPeardoxGorillaEyes.Destroy;
begin
  Stop;
  FInterop.Free;
  inherited Destroy;
end;

procedure TPeardoxGorillaEyes.ReleaseZeroCopy;
begin
  FreeAndNil(FInterop);
end;

procedure TPeardoxGorillaEyes.NoteGLError(AWhere: Integer; AError: Cardinal);
const
  Places: array[0..1] of string = ('after RenderManual (Gorilla3D''s)',
    'after the zero-copy blit (ours)');
begin
  if (AError = 0) or (FGLErrorsLogged[AWhere] = AError) then
    Exit;
  FGLErrorsLogged[AWhere] := AError;
  Log(Format('OpenGL error $%x %s, taken so FMX''s next BeginScene does not fail on it',
    [AError, Places[AWhere]]));
end;

procedure TPeardoxGorillaEyes.InteropLog(const AText: string);
begin
  Log(AText);
end;

function TPeardoxGorillaEyes.RenderScale: Single;
begin
  Result := 1;
  if (FDisplay <> nil) and FDisplay.Settings.PerEyeView then
    Result := EnsureRange(FDisplay.Settings.RenderScale, LENTICULAR_MIN_RENDER_SCALE,
      LENTICULAR_MAX_RENDER_SCALE);
end;

function TPeardoxGorillaEyes.ZeroCopyPossible: Boolean;
begin
  Result := FZeroCopy and (FDisplay <> nil) and (FDisplay.BridgeDevice <> nil);
end;

function TPeardoxGorillaEyes.CanZeroCopy: Boolean;
begin
  Result := FZeroCopy and (FInterop <> nil) and FInterop.Ready and
    (FInterop.Device = FDisplay.BridgeDevice) and (FInterop.Device <> nil);
end;

procedure TPeardoxGorillaEyes.PrepareZeroCopy;
var
  Dev: Pointer;
  W, H: Integer;
begin
  if not FZeroCopy then
    Exit;
  Dev := FDisplay.BridgeDevice;
  if Dev = nil then
    Exit;
  // A failure is not tried again on the same device
  if FZeroCopyFailed and (FZeroCopyFailedOn = Dev) then
    Exit;
  if not TPeardoxGLInterop.SourceSize(W, H) then
  begin
    FZeroCopyFailed := True;
    FZeroCopyFailedOn := Dev;
    Log('Zero copy: no picture found in OpenGL after RenderManual; screenshots instead');
    Exit;
  end;
  if (FInterop <> nil) and FInterop.Ready and (FInterop.Device = Dev) and
    (FInterop.SourceWidth = W) and (FInterop.SourceHeight = H) and
    (FInterop.Width = FViewWidth) and (FInterop.Height = FViewHeight) then
    Exit;
  if FInterop = nil then
    FInterop := TPeardoxGLInterop.Create(InteropLog);
  if FInterop.Start(Dev, W, H, FViewWidth, FViewHeight) then
    FZeroCopyFailed := False
  else
  begin
    FZeroCopyFailed := True;
    FZeroCopyFailedOn := Dev;
    Log('Zero copy not available; screenshots instead');
  end;
end;

procedure TPeardoxGorillaEyes.RenderFrom(const ACamera: TPoint3D);
var
  Watch: TStopwatch;
begin
  // Parallel to the orbit camera: only its place changes (Frame keeps and
  // puts back the rest)
  FCamera.Camera.Position.Point := ACamera;
  Watch := TStopwatch.StartNew;
  FViewport.RenderManual;
  FRenderMs := FRenderMs + Watch.Elapsed.TotalMilliseconds;
end;

function TPeardoxGorillaEyes.RenderEyeGPU(AEye: Integer; const AView: TPeardoxEyeView): Boolean;
var
  Watch: TStopwatch;
  W, H: Integer;
begin
  RenderFrom(AView.Camera);
  Watch := TStopwatch.StartNew;
  NoteGLError(0, TPeardoxGLInterop.TakeErrors);
  // The picture must still be the size the textures were made for (a
  // resize makes them again, next frame)
  Result := TPeardoxGLInterop.SourceSize(W, H) and (W = FInterop.SourceWidth) and
    (H = FInterop.SourceHeight) and FInterop.CopyEye(AEye, AView.Part.Left * W,
    AView.Part.Top * H, AView.Part.Right * W, AView.Part.Bottom * H);
  // Owner (21:06): "cannot begin rendering scene for TContextOpenGLWindows:
  // 1282" - an OpenGL error left pending fails FMX's next BeginScene
  NoteGLError(1, TPeardoxGLInterop.TakeErrors);
  FCopyMs := FCopyMs + Watch.Elapsed.TotalMilliseconds;
end;

function TPeardoxGorillaEyes.RenderEye(const ACamera: TPoint3D): TBitmap;
var
  Watch: TStopwatch;
begin
  RenderFrom(ACamera);
  // OpenGL is current now: the next frame may go by zero copy
  PrepareZeroCopy;
  Watch := TStopwatch.StartNew;
  Result := FViewport.MakeScreenshot;
  FCopyMs := FCopyMs + Watch.Elapsed.TotalMilliseconds;
end;

procedure TPeardoxGorillaEyes.AppIdle(Sender: TObject; var Done: Boolean);
begin
  if Assigned(FSavedIdle) then
    FSavedIdle(Sender, Done);
  Frame;
  // Keep the idle calls coming while frames are wanted
  Done := not FActive;
end;

procedure TPeardoxGorillaEyes.WatchdogTick(Sender: TObject);
begin
  if FActive and (TThread.GetTickCount64 - FLastFrameTick >= PEARDOX_EYES_WATCHDOG_MS) then
  begin
    Inc(FWatchdogFrames);
    Frame;
  end;
end;

procedure TPeardoxGorillaEyes.Notification(AComponent: TComponent; Operation: TOperation);
begin
  inherited Notification(AComponent, Operation);
  if Operation <> opRemove then
    Exit;
  if (AComponent = FDisplay) or (AComponent = FCamera) or (AComponent = FViewport) then
    Stop;
  if AComponent = FDisplay then
    FDisplay := nil;
  if AComponent = FCamera then
    FCamera := nil;
  if AComponent = FViewport then
    FViewport := nil;
end;

procedure TPeardoxGorillaEyes.SetViewport(const AValue: TGorillaViewport);
begin
  if AValue = FViewport then
    Exit;
  Stop;
  if FViewport <> nil then
    FViewport.RemoveFreeNotification(Self);
  FViewport := AValue;
  if FViewport <> nil then
    FViewport.FreeNotification(Self);
end;

procedure TPeardoxGorillaEyes.SetCamera(const AValue: TSpritelyOrbitalCamera);
begin
  if AValue = FCamera then
    Exit;
  Stop;
  if FCamera <> nil then
    FCamera.RemoveFreeNotification(Self);
  FCamera := AValue;
  if FCamera <> nil then
    FCamera.FreeNotification(Self);
end;

procedure TPeardoxGorillaEyes.SetDisplay(const AValue: TLenticularDisplay);
begin
  if AValue = FDisplay then
    Exit;
  Stop;
  if FDisplay <> nil then
    FDisplay.RemoveFreeNotification(Self);
  FDisplay := AValue;
  if FDisplay <> nil then
    FDisplay.FreeNotification(Self);
end;

procedure TPeardoxGorillaEyes.Log(const AText: string);
begin
  if Assigned(FOnLog) and not (csDestroying in ComponentState) then
    FOnLog(Self, AText);
end;

function TPeardoxGorillaEyes.Start: Boolean;
var
  Info: TLNBDisplayInfo;
begin
  Result := FActive;
  if FActive then
    Exit;
  if (FDisplay = nil) or not FDisplay.Running then
  begin
    Log('Eyes NOT started: the display is not running');
    Exit;
  end;
  if (FCamera = nil) or (FCamera.Camera = nil) or (FViewport = nil) or
    not (FCamera.Camera.Parent is TControl3D) then
  begin
    Log('Eyes NOT started: the camera or the viewport is not set');
    Exit;
  end;
  if FCamera.ProjectionMode <> TGorillaCameraProjection.cpPerspective then
    Log('Eyes: the camera is not in perspective; the two views will differ only sideways');
  // Gorilla3D renders only when told: two renders a frame, one per eye
  FSavedFixedRate := FViewport.UseFixedFrameRate;
  FSavedManual := FViewport.ManualRendering;
  FViewport.UseFixedFrameRate := False;
  FViewport.ManualRendering := True;
  FFrames := 0;
  FWovenFrames := 0;
  FRenderMs := 0;
  FCopyMs := 0;
  FSubmitMs := 0;
  FWorstMs := 0;
  FLastLogTick := TThread.GetTickCount64;
  // Each eye is woven at the display's recommended view size
  FViewWidth := PEARDOX_EYES_DEFAULT_VIEW_WIDTH;
  FViewHeight := PEARDOX_EYES_DEFAULT_VIEW_HEIGHT;
  if FDisplay.DisplayInfo(Info) and (Info.recommendedViewWidth > 0) and
    (Info.recommendedViewHeight > 0) then
  begin
    FViewWidth := Info.recommendedViewWidth;
    FViewHeight := Info.recommendedViewHeight;
  end;
  // Flat first, so the lens never comes on when it is not wanted
  FDisplay.Flat := not FDisplay.Settings.Weave;
  FDisplay.Weaving := True;
  FActive := True;
  FWatchdogFrames := 0;
  FLastFrameTick := TThread.GetTickCount64;
  FSavedIdle := Application.OnIdle;
  Application.OnIdle := AppIdle;
  FIdleHooked := True;
  FWatchdog.Enabled := True;
  Log(Format('Eyes started: %s, woven at %d x %d (the display''s view), rendered at %.2f ' +
    'times it, target depth %.3f (the glass)%s', [IfThen(FDisplay.Settings.PerEyeView,
    'each eye drawn from where it is (per-eye view)',
    'each eye drawn from the orbit camera''s distance (full speed)'), FViewWidth, FViewHeight,
    RenderScale, FCamera.Distance, IfThen(FDisplay.Settings.Weave, '',
    '; flat (weave off): one view from between the eyes, the lens off')]));
  Result := True;
end;

procedure TPeardoxGorillaEyes.Stop;
var
  Mine: TIdleEvent;
begin
  if FWatchdog <> nil then
    FWatchdog.Enabled := False;
  if FIdleHooked then
  begin
    // Put back what was there, unless someone has replaced it since
    Mine := AppIdle;
    if (TMethod(Application.OnIdle).Code = TMethod(Mine).Code) and
      (TMethod(Application.OnIdle).Data = TMethod(Mine).Data) then
      Application.OnIdle := FSavedIdle;
    FIdleHooked := False;
  end;
  if not FActive then
    Exit;
  FActive := False;
  if (FDisplay <> nil) and not (csDestroying in FDisplay.ComponentState) then
    FDisplay.Weaving := False;
  if (FViewport <> nil) and not (csDestroying in FViewport.ComponentState) then
  begin
    FViewport.ManualRendering := FSavedManual;
    FViewport.UseFixedFrameRate := FSavedFixedRate;
    FViewport.Invalidate;
  end;
  Log('Eyes stopped: the viewport renders by itself again');
end;

procedure TPeardoxGorillaEyes.EyePair(out ALeft, ARight: TPoint3D);
var
  Mid, Dir: TPoint3D;
  Sep: Single;
  Fixed: Boolean;
begin
  Sep := FDisplay.Settings.EyeSeparationMM;
  Fixed := not (FDisplay.Settings.LookAround and FDisplay.EyesTracked);
  if Fixed then
  begin
    // A viewer straight in front of the view's centre
    if Sep <= 0 then
      Sep := LENTICULAR_DEFAULT_EYE_SEPARATION_MM;
    Mid := Point3D(FDisplay.WindowCenterMM.X, FDisplay.WindowCenterMM.Y,
      PEARDOX_EYES_NOMINAL_VIEWER_MM);
    ALeft := Mid - Point3D(Sep / 2, 0, 0);
    ARight := Mid + Point3D(Sep / 2, 0, 0);
    if FDisplay.EyesTracked then
      FLastEyesFrom := 'fixed viewer (LookAround off)'
    else
      FLastEyesFrom := 'fixed viewer (eyes not tracked)';
  end
  else
  begin
    ALeft := FDisplay.LeftEyeMM;
    ARight := FDisplay.RightEyeMM;
    FLastEyesFrom := 'tracked';
    // The saved separation instead of the tracker's, which wanders, about
    // the tracked midpoint
    if Sep > 0 then
    begin
      Mid := (ALeft + ARight) * 0.5;
      Dir := (ARight - ALeft).Normalize;
      ALeft := Mid - Dir * (Sep / 2);
      ARight := Mid + Dir * (Sep / 2);
      FLastEyesFrom := Format('tracked, separation %.0f mm', [Sep]);
    end;
  end;
end;

function TPeardoxGorillaEyes.ViewScale(out AScale: Single): Boolean;
var
  D, PX, PY: Single;
begin
  AScale := 0;
  Result := False;
  D := FCamera.Distance;
  if (FDisplay.WindowSizeMM.Height <= 0) or (FViewport.Width <= 0) or (FViewport.Height <= 0) or
    (D <= 0) then
    Exit;
  // The point one unit right, one down and one ahead of the orbit camera,
  // in its own axes: it falls SX of the half width right of the middle and
  // SY of the half height below, SX and SY being the projection's
  // 1 / tan(half the field of view) across and up
  if not FCamera.Camera.ProjectToView(FCamera.Camera.CameraPosition +
    FCamera.Camera.Orientation.Rotate(Point3D(1, 1, 1)), nil, FViewport.Width,
    FViewport.Height, PX, PY) then
    Exit;
  FProjX := Abs(2 * PX / FViewport.Width - 1);
  FProjY := Abs(2 * PY / FViewport.Height - 1);
  if (FProjX <= 0) or (FProjY <= 0) then
    Exit;
  // The field of view takes in 2 D / SY units at depth D: at the model's
  // depth, that is the view's height on the display. Not at the target's:
  // a right drag moves the target (the glass) with the camera still, and
  // a scale that followed it moved every eye's camera sideways - the model
  // slid across the 3D view (owner, 22:59 and 23:10: "it still moves").
  // With the scale kept, the glass and the viewer move along the line of
  // sight together and the model only comes out of the screen or goes in
  FScaleDepth := ModelDepth;
  AScale := 2 * FScaleDepth / (FProjY * FDisplay.WindowSizeMM.Height);
  Result := True;
end;

function TPeardoxGorillaEyes.ModelDepth: Single;
var
  Box: TBoundingBox;
  Centre, Eye: TPoint3D;
  Depth: Single;
begin
  Result := FCamera.Distance;
  if FCamera.Subject = nil then
    Exit;
  Box := FCamera.Subject.GetAbsoluteBoundingBox;
  Centre := Point3D(Box.TopLeftNear.X + (Box.Width / 2), Box.TopLeftNear.Y + (Box.Height / 2),
    Box.TopLeftNear.Z + (Box.Depth / 2));
  Eye := FCamera.Camera.CameraPosition;
  // Along the line of sight, as the glass is square to it
  Depth := (Centre - Eye).DotProduct(FCamera.Camera.Orientation.Rotate(Point3D(0, 0, 1)));
  // A model behind the camera, or the camera inside it: the target's
  if Depth > FCamera.Distance * 0.05 then
    Result := Depth;
end;

function TPeardoxGorillaEyes.EyeView(const AEyeMM: TPoint3D; AScale: Single;
  out AView: TPeardoxEyeView): Boolean;
var
  Z, HalfW, HalfH: Single;
  E: TPoint3D;
begin
  // In the orbit camera's own frame (its parent's, the camera having no
  // turn of its own there): X right, Y down, Z the view direction, the glass
  // through the orbit centre (Z = 0), the orbit camera at Z = -D. FMX's Y is
  // down, the display's up
  Z := Max(AEyeMM.Z, PEARDOX_EYES_MIN_EYE_DISTANCE_MM);
  if FDisplay.Settings.PerEyeView then
    E := Point3D((AEyeMM.X - FDisplay.WindowCenterMM.X) * AScale,
      -(AEyeMM.Y - FDisplay.WindowCenterMM.Y) * AScale, -Z * AScale)
  else
  begin
    // Full speed: at the orbit camera's distance, in the direction the real
    // eye is, so the glass fills the picture (no zoom) and only its offset
    // remains
    E := Point3D((AEyeMM.X - FDisplay.WindowCenterMM.X) / Z, -(AEyeMM.Y -
      FDisplay.WindowCenterMM.Y) / Z, -1) * FScaleDepth;
  end;
  AView.Camera := E;
  // The glass's corners from there, the eye's camera looking the same way
  // as the orbit camera: X / Z and Y / Z through the projection, as
  // fractions of the picture from its top-left corner
  Z := -E.Z;
  HalfW := FDisplay.WindowSizeMM.Width / 2 * AScale;
  HalfH := FDisplay.WindowSizeMM.Height / 2 * AScale;
  AView.Part := RectF((1 + (-HalfW - E.X) / Z * FProjX) / 2,
    (1 + (-HalfH - E.Y) / Z * FProjY) / 2, (1 + (HalfW - E.X) / Z * FProjX) / 2,
    (1 + (HalfH - E.Y) / Z * FProjY) / 2);
  Result := (Z > 0) and (AView.Part.Right > AView.Part.Left) and
    (AView.Part.Bottom > AView.Part.Top);
end;

procedure TPeardoxGorillaEyes.LogSnapshot(const ANote: string);
const
  LensNames: array[TLenticularDisplayLensState] of string = ('not known', 'on', 'off');
  EyeNames: array[0..1] of string = ('L', 'R');
var
  Info: TLNBDisplayInfo;
  I: Integer;
  P: TRectF;
  Zoom: Single;

  //** @abstract(A point for the log.)
  //**
  //** @param(APoint The point.)
  //**
  //** @returns(Its coordinates to one place, in brackets.)
  function Pt(const APoint: TPoint3D): string;
  begin
    Result := Format('(%.1f, %.1f, %.1f)', [APoint.X, APoint.Y, APoint.Z]);
  end;

begin
  Log('=== SNAPSHOT ===');
  if ANote <> '' then
    Log('  ' + ANote);
  if (FDisplay = nil) or not FDisplay.Running or (FCamera = nil) then
  begin
    Log('  the display is not running');
    Log('=== END SNAPSHOT ===');
    Exit;
  end;
  if FDisplay.DisplayInfo(Info) then
    Log(Format('  display %d x %d px, %.1f x %.1f mm, recommended view %d x %d per eye',
      [Info.resolutionWidth, Info.resolutionHeight, Info.physicalWidthMM, Info.physicalHeightMM,
       Info.recommendedViewWidth, Info.recommendedViewHeight]));
  Log(Format('  viewport on the display: centre (%.1f, %.1f) mm, %.1f x %.1f mm, view %s',
    [FDisplay.WindowCenterMM.X, FDisplay.WindowCenterMM.Y, FDisplay.WindowSizeMM.Width,
     FDisplay.WindowSizeMM.Height, FLastViewInfo]));
  Log(Format('  eyes tracked L%s R%s mm (%s), drawn from L%s R%s mm (%s), look-around %s, ' +
    'lens %s', [Pt(FDisplay.LeftEyeMM), Pt(FDisplay.RightEyeMM),
    IfThen(FDisplay.EyesTracked, 'tracked', 'NOT tracked'), Pt(FLastEyes[0]), Pt(FLastEyes[1]),
    FLastEyesFrom, BoolToStr(FDisplay.Settings.LookAround, True),
    LensNames[FDisplay.LensState]]));
  Log(Format('  settings: EyeSeparationMM %.1f (0 = tracked), LatencyFrames %d, LensMode %d',
    [FDisplay.Settings.EyeSeparationMM, FDisplay.Settings.LatencyFrames,
     FDisplay.Settings.LensMode]));
  Log(Format('  camera: field of view %.2f deg, target depth (the glass) %.3f units; viewport ' +
    '%.0f x %.0f, rendered at %.2f times the view; per-eye view %s, weave %s', [FCamera.FOV, FCamera.Distance,
    FViewport.Width, FViewport.Height, RenderScale,
    BoolToStr(FDisplay.Settings.PerEyeView, True), BoolToStr(FDisplay.Settings.Weave, True)]));
  if FLastScale > 0 then
  begin
    Log(Format('  scale %.6f world units per mm (%.3f mm per unit), set at the model''s depth ' +
      '%.3f: the glass is %.0f mm from the orbit camera, the model %.0f mm', [FLastScale,
      1 / FLastScale, FScaleDepth, FCamera.Distance / FLastScale, FScaleDepth / FLastScale]));
    for I := 0 to 1 do
    begin
      P := FLastViews[I].Part;
      Zoom := 0;
      if P.Height > 0 then
        Zoom := 1 / P.Height;
      Log(Format('  %s eye camera %s units (%s mm); the glass is the picture''s part ' +
        '(%.3f, %.3f)-(%.3f, %.3f), zoom %.3f', [EyeNames[I], Pt(FLastViews[I].Camera),
        Pt(FLastViews[I].Camera * (1 / FLastScale)), P.Left, P.Top, P.Right, P.Bottom,
        Zoom]));
    end;
  end;
  if FLastRateText <> '' then
    Log('  ' + FLastRateText);
  Log('=== END SNAPSHOT ===');
end;

procedure TPeardoxGorillaEyes.CopyPart(const AData: TBitmapData; AWidth, AHeight: Integer;
  const APart: TRectF; AX0, APitch: Integer);
var
  X, Y, SY: Integer;
  Src: PCardinal;
  Dst: PCardinal;
begin
  // The source column of each of the view's columns, the nearest pixel
  if Length(FColumns) <> FViewWidth then
    SetLength(FColumns, FViewWidth);
  for X := 0 to FViewWidth - 1 do
  begin
    FColumns[X] := Floor((APart.Left + (X + 0.5) / FViewWidth * APart.Width) * AWidth);
    if (FColumns[X] < 0) or (FColumns[X] >= AWidth) then
      FColumns[X] := -1;
  end;
  for Y := 0 to FViewHeight - 1 do
  begin
    Dst := PCardinal(@FBuffer[Y * APitch + AX0]);
    SY := Floor((APart.Top + (Y + 0.5) / FViewHeight * APart.Height) * AHeight);
    if (SY < 0) or (SY >= AHeight) then
    begin
      // Outside the picture: opaque black, whichever order the bytes are in
      for X := 0 to FViewWidth - 1 do
      begin
        Dst^ := $FF000000;
        Inc(Dst);
      end;
      Continue;
    end;
    Src := PCardinal(AData.GetScanline(SY));
    for X := 0 to FViewWidth - 1 do
    begin
      if FColumns[X] >= 0 then
        Dst^ := PCardinal(PByte(Src) + FColumns[X] * 4)^
      else
        Dst^ := $FF000000;
      Inc(Dst);
    end;
  end;
end;

procedure TPeardoxGorillaEyes.Submit(ALeft, ARight: TBitmap);
var
  DL, DR: TBitmapData;
  Pitch: Integer;
  RGBA: Boolean;
  Watch: TStopwatch;
begin
  if (ALeft.Width <= 0) or (ALeft.Height <= 0) or (ARight.Width <= 0) or
    (ARight.Height <= 0) then
  begin
    FLastViewInfo := 'MakeScreenshot gave an empty picture';
    Exit;
  end;
  Watch := TStopwatch.StartNew;
  RGBA := False;
  Pitch := FViewWidth * 2 * 4;
  if Length(FBuffer) <> Pitch * FViewHeight then
    SetLength(FBuffer, Pitch * FViewHeight);
  if not ALeft.Map(TMapAccess.Read, DL) then
    Exit;
  try
    if not ARight.Map(TMapAccess.Read, DR) then
      Exit;
    try
      CopyPart(DL, ALeft.Width, ALeft.Height, FLastViews[0].Part, 0, Pitch);
      CopyPart(DR, ARight.Width, ARight.Height, FLastViews[1].Part, FViewWidth * 4, Pitch);
      RGBA := DL.PixelFormat = TPixelFormat.RGBA;
      FLastViewInfo := Format('%d x %d per eye from %d x %d screenshots, %s',
        [FViewWidth, FViewHeight, ALeft.Width, ALeft.Height, IfThen(RGBA, 'RGBA', 'BGRA')]);
    finally
      ARight.Unmap(DR);
    end;
  finally
    ALeft.Unmap(DL);
  end;
  FCopyMs := FCopyMs + Watch.Elapsed.TotalMilliseconds;
  Watch := TStopwatch.StartNew;
  if FDisplay.SubmitViews(@FBuffer[0], FViewWidth, FViewHeight, Pitch, RGBA) = LNB_OK then
    Inc(FWovenFrames);
  FSubmitMs := FSubmitMs + Watch.Elapsed.TotalMilliseconds;
end;

procedure TPeardoxGorillaEyes.Frame;
var
  L, R: TPoint3D;
  Scale: Single;
  Cam: TControl3D;
  SavedPos, SavedRot: TPoint3D;
  BL, BR: TBitmap;
  Watch, Watch2: TStopwatch;
  NowTick: UInt64;
  Secs, N: Double;
  Done: Boolean;
  W, H: Integer;
  PL, PR: TRectF;
  Flat: Boolean;
  RightTex: Pointer;
begin
  if FInFrame or not FActive then
    Exit;
  if (FDisplay = nil) or not FDisplay.Running or (FCamera = nil) or (FCamera.Camera = nil) or
    (FViewport = nil) then
  begin
    Stop;
    Exit;
  end;
  FInFrame := True;
  try
    Watch := TStopwatch.StartNew;
    FDisplay.UpdateEyes;
    EyePair(L, R);
    // Weave off: one view from between the eyes for both, the lens off
    // (owner, 22:37: for screen recordings, which cannot catch the woven
    // picture; the view still follows the head)
    Flat := not FDisplay.Settings.Weave;
    FDisplay.Flat := Flat;
    if Flat then
    begin
      L := (L + R) * 0.5;
      R := L;
    end;
    FLastEyes[0] := L;
    FLastEyes[1] := R;
    if ViewScale(Scale) and EyeView(L, Scale, FLastViews[0]) and
      EyeView(R, Scale, FLastViews[1]) then
    begin
      FLastScale := Scale;
      Cam := FCamera.Camera;
      SavedPos := Cam.Position.Point;
      SavedRot := Cam.RotationAngle.Point;
      if CanZeroCopy then
      begin
        try
          Done := RenderEyeGPU(0, FLastViews[0]) and (Flat or RenderEyeGPU(1, FLastViews[1]));
        finally
          // Exactly as it was: the orbit camera knows nothing of this
          Cam.Position.Point := SavedPos;
          Cam.RotationAngle.Point := SavedRot;
        end;
        if Done then
        begin
          FLastViewInfo := Format('%d x %d per eye from %d x %d, zero copy (OpenGL to ' +
            'Direct3D on the GPU)', [FInterop.Width, FInterop.Height, FInterop.SourceWidth,
            FInterop.SourceHeight]);
          Watch2 := TStopwatch.StartNew;
          RightTex := FInterop.RightTexture;
          if Flat then
          begin
            // The left eye's view for both: a flat picture
            RightTex := FInterop.LeftTexture;
            FLastViewInfo := FLastViewInfo + ', flat';
          end;
          if FDisplay.SubmitEyeTextures(FInterop.LeftTexture, RightTex, FInterop.Width,
            FInterop.Height) = LNB_OK then
            Inc(FWovenFrames);
          FSubmitMs := FSubmitMs + Watch2.Elapsed.TotalMilliseconds;
        end
        else
        begin
          // A picture of another size (a resize): made again from the next
          // frame. Anything else: screenshots on this device from now on
          if not TPeardoxGLInterop.SourceSize(W, H) or
            ((W = FInterop.SourceWidth) and (H = FInterop.SourceHeight)) then
          begin
            FZeroCopyFailed := True;
            FZeroCopyFailedOn := FInterop.Device;
            Log('Zero copy failed in a frame; screenshots instead');
          end;
          FreeAndNil(FInterop);
          FLastViewInfo := 'zero copy lost the picture';
        end;
      end
      else
      begin
        BL := nil;
        BR := nil;
        try
          try
            BL := RenderEye(FLastViews[0].Camera);
            if not Flat then
              BR := RenderEye(FLastViews[1].Camera);
          finally
            Cam.Position.Point := SavedPos;
            Cam.RotationAngle.Point := SavedRot;
          end;
          if (BL <> nil) and Flat then
            Submit(BL, BL)
          else if (BL <> nil) and (BR <> nil) then
            Submit(BL, BR)
          else
            FLastViewInfo := 'MakeScreenshot gave no picture';
        finally
          BL.Free;
          BR.Free;
        end;
      end;
      Inc(FFrames);
      FWorstMs := Max(FWorstMs, Watch.Elapsed.TotalMilliseconds);
    end;
  finally
    FInFrame := False;
    FLastFrameTick := TThread.GetTickCount64;
  end;
  NowTick := TThread.GetTickCount64;
  if NowTick - FLastLogTick >= 1000 then
  begin
    Secs := (NowTick - FLastLogTick) / 1000;
    N := Max(FFrames, 1);
    PL := FLastViews[0].Part;
    PR := FLastViews[1].Part;
    Log(Format('Eyes: %.1f fps (worst %.0f ms) | per frame: render %.1f ms, copy %.1f ms, ' +
      'submit %.1f ms | %s | eyes %s | scale %.5f units/mm at the model''s depth %.3f, target ' +
      '(glass) %.3f, glass part L (%.3f, %.3f)-(%.3f, ' +
      '%.3f) R (%.3f, %.3f)-(%.3f, %.3f) | %d by the watchdog', [FFrames / Secs, FWorstMs,
      FRenderMs / N, FCopyMs / N, FSubmitMs / N, FLastViewInfo, FLastEyesFrom, FLastScale,
      FScaleDepth, FCamera.Distance,
      PL.Left, PL.Top, PL.Right, PL.Bottom, PR.Left, PR.Top, PR.Right, PR.Bottom,
      FWatchdogFrames]));
    FLastRateText := Format('%.1f fps (worst %.0f ms), per frame render %.1f, copy %.1f, ' +
      'submit %.1f ms', [FFrames / Secs, FWorstMs, FRenderMs / N, FCopyMs / N, FSubmitMs / N]);
    FLastLogTick := NowTick;
    FWatchdogFrames := 0;
    FFrames := 0;
    FRenderMs := 0;
    FCopyMs := 0;
    FSubmitMs := 0;
    FWorstMs := 0;
  end;
end;

end.

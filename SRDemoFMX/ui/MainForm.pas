{ @abstract(Main window of SRDemoFMX: a test scene on the LeiaSR display, with a
  log.)

  The scene is built in code so the form file stays trivial. The toolbar and
  the log sit outside the viewport, because the woven image covers the
  viewport with a native window that hides FMX controls drawn over it. }
unit MainForm;

interface

uses
  System.SysUtils, System.Types, System.UITypes, System.Classes, System.Math.Vectors,
  System.Rtti, System.Diagnostics,
  FMX.Types, FMX.Controls, FMX.Forms, FMX.Graphics, FMX.StdCtrls, FMX.Layouts,
  FMX.Memo, FMX.Memo.Types, FMX.ScrollBox, FMX.Types3D, FMX.Controls3D, FMX.Objects3D,
  FMX.MaterialSources, FMX.Viewport3D, FMX.Ani, FMX.Platform, FMX.Controls.Presentation,
  FMX.ListBox, FMX.Objects, SRSettings, SRStartProblem,
  FMX.SRStereoViewport;

const
  { Spheres each side of the main sphere, across and in depth: the grid is
    (2 * RowHalf + 1) squared. }
  RowHalf = 5;
  { Distance between neighbouring spheres, across and in depth alike,
    world units (about 50 mm on the glass in a maximised window on a
    27-inch SR display). }
  RowStep = 3.0;
  { The spheres' diameter, world units. }
  SphereSize = 1.4;
  { Height of the grid: the middle of the screen, with the main sphere at
    the origin. }
  RowY = 0.0;
  { How far the nearest cubes are above and below the grid (FMX's Y axis
    points down, so the column going to -Y is above). }
  CubeY = 4.5;
  { How far the mouse wheel moves the scene per notch, world units; a
    quarter of it with Shift. }
  SceneStep = 1.0;
  { Furthest the scene can be pulled towards the viewer, world units (the
    nearest sphere then stands most of the way to a viewer 80 cm away). }
  SceneZMin = -20.0;
  { Furthest the scene can be pushed away, world units. }
  SceneZMax = 20.0;
  { Degrees the scene tilts or rolls per logical pixel of a left-button
    drag. }
  TiltPerPixel = 0.25;
  { Most the scene can tilt either way, degrees. }
  TiltMax = 85.0;
  { Most the scene can roll either way, degrees. }
  RollMax = 180.0;
  { Cubes in each column, above the grid and below it. }
  CubesPerColumn = 3;
  { Distance between neighbouring cubes in a column, world units; the
    outer ones start out of view and come in when the scene is tilted. }
  CubeGap = 4.5;

type
  { The demo's main window. }
  TfrmMain = class(TForm)
    { Builds the scene, toolbar, log and renderer. }
    procedure FormCreate(Sender: TObject);
    { Shuts SR down while the native window still exists.
      @param(Sender the form)
      @param(Action what to do with the form) }
    procedure FormClose(Sender: TObject; var Action: TCloseAction);
  private
    { Holds the viewport and, over it, @link(FFlatBack). }
    FViewArea: TLayout;
    { The 3D view. }
    FViewport: TViewport3D;
    { Black backing for @link(FFlatImage), over the viewport; shown only
      while LeiaSR is off and a stereo image is chosen. }
    FFlatBack: TRectangle;
    { The stereo image's left view, shown in 2D while LeiaSR is off. }
    FFlatImage: TImage;
    { The reference camera. }
    FCamera: TCamera;
    { Parent of every object in the scene (not the camera or the light), so
      the mouse wheel can move the whole scene towards or away from the
      viewer. }
    FSceneRoot: TDummy;
    { Holds the grid of spheres, inside @link(FSceneRoot), so the grid can
      spin on its own about the vertical axis through the main sphere. }
    FGridRoot: TDummy;
    { The grid's spin, paused until R is pressed. }
    FGridSpin: TFloatAnimation;
    { How far @link(FSceneRoot) is moved, world units; negative is towards
      the viewer (out of the screen). }
    FSceneZ: Single;
    { How far @link(FSceneRoot) is tilted about the horizontal axis through
      the main sphere, degrees. }
    FSceneTilt: Single;
    { How far @link(FSceneRoot) is rolled about the depth axis through the
      main sphere, degrees. }
    FSceneRoll: Single;
    { Whether a left-button drag is turning the scene. }
    FTilting: Boolean;
    { The pointer and the tilt and roll when the drag started. }
    FTiltStartX, FTiltStartY, FTiltStartAngle, FRollStartAngle: Single;
    { The grid's middle column, straight in depth through the main sphere,
      from RowHalf steps behind the glass (positive index) to RowHalf steps
      in front of it, towards the viewer (negative index); index 0 is the
      main sphere. Its distances are shown in the status bar. }
    FDepthRow: array[-RowHalf..RowHalf] of TSphere;
    { Shows @link(FViewport) on the SR display. }
    FStereo: TSRStereoRenderer;
    { The cubes' spins: the column above the grid, then the column below
      it. }
    FSpins: array[0..2 * CubesPerColumn - 1] of TFloatAnimation;
    { Status line. }
    FStatus: TLabel;
    { Turns 3D on and off. }
    FToggle: TCheckBox;
    { Pauses the cube. }
    FPause: TCheckBox;
    { Full screen on and off. }
    FFullScreen: TCheckBox;
    { The log. }
    FLog: TMemo;
    { Holds, in this fixed order from the top, the toolbar, the settings row
      and the log; hidden as a whole in full screen, so the order never
      changes. }
    FBottomArea: TLayout;
    { The toolbar above the settings row, inside @link(FBottomArea) above
      the log. }
    FBarsArea: TLayout;
    { The main toolbar. }
    FToolBar: TLayout;
    { The second row: glasses-free 3D settings and what to show. }
    FSettingsBar: TLayout;
    { Frames drawn, for the periodic FastMM5 scan. }
    FFrames: Integer;
    { The frame rate, on a flat panel on the glass (depth 0, so both eyes
      see the same pixels and it stays sharp), top left, not moved or
      turned with the scene. FMX's 3D text came out as streaks. }
    FFpsPanel: TPlane;
    { The panel's picture: the frame rate drawn as 2D text. }
    FFpsBitmap: TBitmap;
    { The panel's material, given @link(FFpsBitmap) after each redraw. }
    FFpsMaterial: TTextureMaterialSource;
    { Frames since the frame rate was last shown. }
    FFpsFrames: Integer;
    { Times the frame rate. }
    FFpsClock: TStopwatch;
    { Chooses the 3D scene or one of the stereo images in the media folder. }
    FShow: TComboBox;
    { Draws from where the head is (on) or from a fixed viewer (off). }
    FLookAround: TCheckBox;
    { Latency told to the weaver: SR's default, or 1 to 4 frames. }
    FLatency: TComboBox;
    { When the display's lens is on: off over the controls, always on, or
      always off (in @link(TSRLensMode) order). }
    FLens: TComboBox;
    { Saved settings. }
    FSettings: TSRSettings;
    { Set while settings are being applied, so the controls' handlers do not
      save them back half-applied. }
    FLoading: Boolean;
    { The repository's media folder, empty if not found. }
    FMediaFolder: string;
    { Controls that only mean anything with LeiaSR, hidden where it is not
      installed. }
    FSROnly: TArray<TControl>;
    { Whether this computer has the LeiaSR runtime. }
    FSRInstalled: Boolean;
    { Adds a control to @link(FSROnly).
      @param(C the control)
      @returns(C) }
    function SROnly(C: TControl): TControl;
    { Moves the whole scene towards or away from the viewer, or back.
      @param(Delta world units; negative is towards the viewer)
      @param(Reset @true puts it back where it was built, ignoring Delta) }
    procedure MoveScene(Delta: Single; Reset: Boolean);
    { The mouse wheel moves the scene: away from the viewer for a forward
      turn, towards for a backward one; Shift for small steps.
      @param(Sender the form)
      @param(Shift the modifier keys)
      @param(WheelDelta 120 per notch, positive forwards)
      @param(Handled set when the wheel was used) }
    procedure FormMouseWheel(Sender: TObject; Shift: TShiftState; WheelDelta: Integer;
      var Handled: Boolean);
    { Starts turning the scene on a left-button press over the viewport.
      @param(Sender the viewport)
      @param(Button which button)
      @param(Shift the modifier keys)
      @param(X pointer x, logical pixels)
      @param(Y pointer y, logical pixels) }
    procedure ViewportMouseDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState;
      X, Y: Single);
    { Turns the scene while the left button is held: moving up and down
      tilts it about the horizontal axis through the main sphere, left and
      right rolls it about the depth axis through it.
      @param(Sender the viewport)
      @param(Shift the modifier keys)
      @param(X pointer x, logical pixels)
      @param(Y pointer y, logical pixels) }
    procedure ViewportMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Single);
    { Ends the turn and logs where it was left.
      @param(Sender the viewport)
      @param(Button which button)
      @param(Shift the modifier keys)
      @param(X pointer x, logical pixels)
      @param(Y pointer y, logical pixels) }
    procedure ViewportMouseUp(Sender: TObject; Button: TMouseButton; Shift: TShiftState;
      X, Y: Single);
    { The depth line for the status bar: the middle column's distances in mm
      from the glass, the viewer's distance, and where the scene is.
      @returns(the text, empty before the first 3D frame) }
    function DepthText: string;
    { Draws the frame-rate panel's picture.
      @param(Text what to show) }
    procedure DrawFps(const Text: string);
    { Builds the 3D scene. }
    procedure BuildScene;
    { Builds the toolbar and the log. }
    procedure BuildControls;
    { Makes a lit material.
      @param(Color its diffuse colour)
      @returns(the material, owned by the form) }
    function MakeMaterial(Color: TAlphaColor): TLightMaterialSource;
    { Adds a line to the log, with the time.
      @param(Msg the line) }
    procedure AddLog(const Msg: string);
    { Turns 3D on or off from the checkbox.
      @param(Sender the checkbox) }
    procedure ToggleChange(Sender: TObject);
    { Pauses or resumes the cube.
      @param(Sender the checkbox) }
    procedure PauseChange(Sender: TObject);
    { Full screen on or off.
      @param(Sender the checkbox) }
    procedure FullScreenChange(Sender: TObject);
    { Finds the media folder and lists its images, and those in its
      @code(local) folder, in @link(FShow). }
    procedure ListMedia;
    { Shows the 3D scene or the chosen stereo image.
      @param(Sender the combo box) }
    procedure ShowChange(Sender: TObject);
    { Opens the settings dialog (the eye separation), with the lens held off
      so it can be read.
      @param(Sender the button) }
    procedure SettingsClick(Sender: TObject);
    { Turns look-around on or off.
      @param(Sender the checkbox) }
    procedure LookAroundChange(Sender: TObject);
    { Sets the weaver's latency.
      @param(Sender the combo box) }
    procedure LatencyChange(Sender: TObject);
    { Sets the renderer's lens mode.
      @param(Sender the combo box) }
    procedure LensChange(Sender: TObject);
    { Reads the settings file and applies it to the controls and renderer. }
    procedure LoadSettings;
    { Writes the settings file, unless settings are being applied. }
    procedure SaveSettings;
    { Logs an exception that reached the application, then shows it.
      @param(Sender the object that raised it)
      @param(E the exception) }
    procedure AppException(Sender: TObject; E: Exception);
    { Copies the log to the clipboard.
      @param(Sender the button) }
    procedure CopyLogClick(Sender: TObject);
    { Clears the log.
      @param(Sender the button) }
    procedure ClearLogClick(Sender: TObject);
    { Shows a renderer error and unticks 3D after the click is done.
      @param(Sender the renderer)
      @param(Msg the error) }
    procedure StereoError(Sender: TObject; const Msg: string);
    { LeiaSR could not start, or was turned off because it would run very
      badly: asks the user (continue without glasses-free 3D, try again, or
      use glasses-free 3D
      anyway), and offers the high-performance GPU when that would fix it.
      @param(Sender the renderer)
      @param(Problem what went wrong)
      @param(Msg the details)
      @param(CanDegrade whether glasses-free 3D anyway can be offered)
      @param(CanFixGpu whether the Windows GPU preference should fix it)
      @param(Choice receives the user's choice) }
    procedure StereoStartProblem(Sender: TObject; Problem: TSRStartProblem; const Msg: string;
      CanDegrade, CanFixGpu: Boolean; var Choice: TSRStartChoice);
    { LeiaSR is running: hides the 2D image and ticks 3D.
      @param(Sender the renderer) }
    procedure StereoStarted(Sender: TObject);
    { Shows the chosen stereo image's left view in 2D while LeiaSR is off,
      and hides it otherwise (the scene is then FMX's own drawing of the
      viewport, or the woven 3D). }
    procedure UpdateFlatImage;
    { Sets the 3D tick box without starting or stopping anything.
      @param(Value whether it is ticked) }
    procedure SetToggleQuietly(Value: Boolean);
    { Adds a renderer log line.
      @param(Sender the renderer)
      @param(Msg the line) }
    procedure StereoLog(Sender: TObject; const Msg: string);
    { Shows the eye positions in the status line.
      @param(Sender the renderer)
      @param(LeftMM left eye, millimetres)
      @param(RightMM right eye, millimetres) }
    procedure StereoEyes(Sender: TObject; const LeftMM, RightMM: TPoint3D);
    { Installs the keyboard hook that gives F11 and Esc to the form whichever
      window has the keyboard. }
    procedure InstallKeyHook;
    { Toggles full screen; queued by the keyboard hook, so it runs outside
      the key message.
      @param(Leave @true to leave full screen only (Esc), @false to toggle
        (F11)) }
    procedure FullScreenKey(Leave: Boolean);
  public
    { Removes the keyboard hook and frees the settings. }
    destructor Destroy; override;
    { Called by the keyboard hook for every key going down in this program's
      thread.
      @param(Key the virtual key code)
      @param(IsRepeat @true for auto-repeat)
      @returns(@true if the key was one the demo uses (F11, Esc in full
        screen, Page Up, Page Down, Home, R, P) and must not reach any
        control) }
    function HookKey(Key: Word; IsRepeat: Boolean): Boolean;
    { Starts or stops the grid's spin about the vertical axis (R), keeping
      the angle it has reached. }
    procedure ToggleGridSpin;
    { Logs a snapshot (P): the scene's state (move, tilt, roll, the grid's
      spin, the depth row in mm) and the renderer's
      @link(TSRStereoRenderer.LogSnapshot). }
    procedure Snapshot;
  end;

var
  { The main window. }
  frmMain: TfrmMain;

implementation

{$R *.fmx}

uses
  System.Math, FMX.Platform.Win, FastMM5, SRDiagLog, SRSettingsDialog;

{ The few Windows calls the keyboard hook needs, declared here rather than
  using Winapi.Windows, whose names (Rectangle, TBitmap and others) would
  hide FMX's in this unit. }
const
  { SetWindowsHookEx: hook keyboard messages. }
  WH_KEYBOARD = 2;
  { Hook code: a key message is being taken from the queue. }
  HC_ACTION = 0;

function SetWindowsHookExW(idHook: Integer; lpfn: Pointer; hmod: NativeUInt;
  dwThreadId: Cardinal): NativeUInt; stdcall; external 'user32.dll';
function UnhookWindowsHookEx(hhk: NativeUInt): LongBool; stdcall; external 'user32.dll';
function CallNextHookEx(hhk: NativeUInt; nCode: Integer; wParam: NativeUInt;
  lParam: NativeInt): NativeInt; stdcall; external 'user32.dll';
function GetFocus: NativeUInt; stdcall; external 'user32.dll';
function GetClassNameW(hWnd: NativeUInt; lpClassName: PWideChar;
  nMaxCount: Integer): Integer; stdcall; external 'user32.dll';
function GetLastError: Cardinal; stdcall; external 'kernel32.dll';
function GetCurrentThreadId: Cardinal; stdcall; external 'kernel32.dll';
{ user32's MessageBoxW, for the GPU preference's result (FMX's dialog came
  up behind the window). }
function MessageBoxW(hWnd: NativeUInt; lpText, lpCaption: PWideChar; uType: Cardinal): Integer;
  stdcall; external 'user32.dll';

const
  { MessageBoxW: OK button. }
  MB_OK = $00000000;
  { MessageBoxW: warning icon. }
  MB_ICONWARNING = $00000030;
  { MessageBoxW: information icon. }
  MB_ICONINFORMATION = $00000040;
  { MessageBoxW: bring the box to the foreground. }
  MB_SETFOREGROUND = $00010000;

var
  { The keyboard hook, 0 if none. }
  KeyHook: NativeUInt = 0;
  { The form the hook reports to, nil once it is gone. }
  KeyHookForm: TfrmMain = nil;

{ Thread keyboard hook: sees every key message this thread takes from its
  queue, before FMX or any native child window (the bridge's) does, so F11
  works whichever window has the keyboard.
  @param(Code hook code)
  @param(WParam the virtual key)
  @param(LParam repeat count and flags; bit 31 set on key up, bit 30 on
    repeat)
  @returns(1 to swallow the key, otherwise the next hook's result) }
function KeyHookProc(Code: Integer; WParam: NativeUInt; LParam: NativeInt): NativeInt; stdcall;
begin
  if (Code = HC_ACTION) and (KeyHookForm <> nil) and ((LParam and $80000000) = 0) then
    if KeyHookForm.HookKey(Word(WParam), (LParam and $40000000) <> 0) then
      Exit(1);
  Result := CallNextHookEx(KeyHook, Code, WParam, LParam);
end;

{ Names the window that has the keyboard, for the log.
  @returns(its class name and handle, or "none") }
function FocusWindowName: string;
var
  H: NativeUInt;
  Buf: array[0..127] of WideChar;
begin
  H := GetFocus;
  if H = 0 then
    Exit('none');
  if GetClassNameW(H, Buf, Length(Buf)) > 0 then
    Result := Format('%s ($%x)', [string(PWideChar(@Buf[0])), H])
  else
    Result := Format('$%x', [H]);
end;

const
  { Most lines kept in the log. }
  MaxLogLines = 3000;
  { Frames between FastMM5 scans of its debug blocks for corruption. }
  FastMMScanEvery = 30;

{ Picks one of two strings.
  @param(Condition which to pick)
  @param(WhenTrue the string for @true)
  @param(WhenFalse the string for @false)
  @returns(the chosen string) }
function IfThenStr(Condition: Boolean; const WhenTrue, WhenFalse: string): string;
begin
  if Condition then
    Result := WhenTrue
  else
    Result := WhenFalse;
end;

function TfrmMain.MakeMaterial(Color: TAlphaColor): TLightMaterialSource;
begin
  Result := TLightMaterialSource.Create(Self);
  Result.Diffuse := Color;
  Result.Ambient := $FF202020;
  Result.Specular := TAlphaColors.White;
  Result.Shininess := 40;
end;

procedure TfrmMain.DrawFps(const Text: string);
begin
  if FFpsBitmap.Canvas.BeginScene then
  try
    FFpsBitmap.Canvas.Clear($80202838);   // half see-through background
    FFpsBitmap.Canvas.Fill.Color := TAlphaColors.White;
    FFpsBitmap.Canvas.Font.Size := 60;
    FFpsBitmap.Canvas.FillText(RectF(0, 0, FFpsBitmap.Width, FFpsBitmap.Height), Text, False, 1, [],
      TTextAlign.Center, TTextAlign.Center);
  finally
    FFpsBitmap.Canvas.EndScene;
  end;
  FFpsMaterial.Texture := FFpsBitmap;   // copies it
end;

procedure TfrmMain.BuildScene;
const
  { One colour for each depth of the grid, nearest the viewer first: warm
    in front of the glass, white on it, cool behind it. }
  DepthColors: array[-RowHalf..RowHalf] of TAlphaColor = (TAlphaColors.Red,
    TAlphaColors.Orangered, TAlphaColors.Darkorange, TAlphaColors.Orange, TAlphaColors.Yellow,
    TAlphaColors.White, TAlphaColors.Lightskyblue, TAlphaColors.Deepskyblue,
    TAlphaColors.Dodgerblue, TAlphaColors.Royalblue, TAlphaColors.Mediumblue);
  { The main sphere's colour, in the middle of the grid on the glass. }
  MainColor = TAlphaColors.Limegreen;
var
  Light: TLight;
  Cube: TCube;
  CubeMat: TLightMaterialSource;
  K: Integer;
  Sphere: TSphere;
  Plane: TPlane;
  I, J: Integer;
  Mats: array[-RowHalf..RowHalf] of TLightMaterialSource;
  MainMat: TLightMaterialSource;
begin
  FViewArea := TLayout.Create(Self);
  FViewArea.Parent := Self;
  FViewArea.Align := TAlignLayout.Client;

  // TSRViewport3D: leaves out FMX's own drawing while glasses-free 3D covers it
  FViewport := TSRViewport3D.Create(Self);
  FViewport.Parent := FViewArea;
  FViewport.Align := TAlignLayout.Client;
  FViewport.Color := $FF101828;
  FViewport.UsingDesignCamera := False;
  FViewport.OnMouseDown := ViewportMouseDown;
  FViewport.OnMouseMove := ViewportMouseMove;
  FViewport.OnMouseUp := ViewportMouseUp;

  // FMX-style camera 20 units in front of the origin; with FocusDistance 20
  // the origin's plane falls on the display glass.
  FCamera := TCamera.Create(Self);
  FCamera.Parent := FViewport;
  FCamera.Position.Point := Point3D(0, 0, -20);
  FViewport.Camera := FCamera;

  Light := TLight.Create(Self);
  Light.Parent := FViewport;
  Light.LightType := TLightType.Directional;
  Light.RotationAngle.X := -35;
  Light.RotationAngle.Y := 25;

  // Everything below moves together with the mouse wheel; the glass is the
  // plane Z = 0 while it is not moved (FocusDistance 20 from the camera)
  FSceneRoot := TDummy.Create(Self);
  FSceneRoot.Parent := FViewport;

  // Back wall, behind the furthest sphere of the depth row
  Plane := TPlane.Create(Self);
  Plane.Parent := FSceneRoot;
  Plane.Position.Point := Point3D(0, 0, (RowHalf + 1) * RowStep);
  Plane.Width := 60;
  Plane.Height := 40;
  Plane.MaterialSource := MakeMaterial($FF35507A);
  Plane.HitTest := False;   // the viewport takes the mouse, not the objects

  // Columns of cubes on the screen plane, spinning: one going up from the
  // grid, one going down; the outer ones come into view when tilted
  CubeMat := MakeMaterial($FFE8A33D);
  for K := 0 to 2 * CubesPerColumn - 1 do
  begin
    Cube := TCube.Create(Self);
    Cube.Parent := FSceneRoot;
    Cube.Position.Point := Point3D(0, (2 * (K div CubesPerColumn) - 1) *
      (CubeY + (K mod CubesPerColumn) * CubeGap), 0);
    Cube.Width := 3;
    Cube.Height := 3;
    Cube.Depth := 3;
    Cube.MaterialSource := CubeMat;
    Cube.HitTest := False;
    FSpins[K] := TFloatAnimation.Create(Self);
    FSpins[K].Parent := Cube;
    FSpins[K].PropertyName := 'RotationAngle.Y';
    FSpins[K].StartValue := 0;
    FSpins[K].StopValue := 360;
    FSpins[K].Duration := 8;
    FSpins[K].Loop := True;
    FSpins[K].Enabled := True;
  end;

  // The grid's own holder, so it can spin about the vertical axis through
  // the main sphere (R) while the rest of the scene stays put
  FGridRoot := TDummy.Create(Self);
  FGridRoot.Parent := FSceneRoot;
  FGridSpin := TFloatAnimation.Create(Self);
  FGridSpin.Parent := FGridRoot;
  FGridSpin.PropertyName := 'RotationAngle.Y';
  FGridSpin.StartValue := 360;   // the opposite way to the cubes
  FGridSpin.StopValue := 0;
  FGridSpin.Duration := 20;
  FGridSpin.Loop := True;
  FGridSpin.Enabled := True;
  FGridSpin.Pause := True;   // R starts it

  // A grid of spheres across the middle of the screen, the same gap across and
  // in depth, centred on the main sphere (green) on the glass. One colour
  // per depth: white on the glass, behind it (+Z) blue, darker further
  // away; in front of it, out towards the viewer (-Z), yellow to red. The
  // status bar gives the middle column's distances in mm.
  for J := -RowHalf to RowHalf do
    Mats[J] := MakeMaterial(DepthColors[J]);
  MainMat := MakeMaterial(MainColor);
  for J := -RowHalf to RowHalf do      // depth
    for I := -RowHalf to RowHalf do    // across
    begin
      Sphere := TSphere.Create(Self);
      Sphere.Parent := FGridRoot;
      Sphere.Width := SphereSize;
      Sphere.Height := SphereSize;
      Sphere.Depth := SphereSize;
      Sphere.Position.Point := Point3D(I * RowStep, RowY, J * RowStep);
      Sphere.HitTest := False;
      if (I = 0) and (J = 0) then
        Sphere.MaterialSource := MainMat
      else
        Sphere.MaterialSource := Mats[J];
      if I = 0 then
        FDepthRow[J] := Sphere;
    end;

  // The frame rate, on the glass (Z = 0) at the top left: in the viewport,
  // not in the scene, so the wheel and the drag do not move it. A flat
  // panel showing a picture of the text (unlit texture), redrawn once a
  // second; its background is half see-through.
  FFpsBitmap := TBitmap.Create(300, 100);
  FFpsMaterial := TTextureMaterialSource.Create(Self);
  FFpsPanel := TPlane.Create(Self);
  FFpsPanel.Parent := FViewport;
  FFpsPanel.Position.Point := Point3D(-12, -7, 0);
  FFpsPanel.Width := 3;
  FFpsPanel.Height := 1;
  FFpsPanel.MaterialSource := FFpsMaterial;
  FFpsPanel.HitTest := False;
  DrawFps('-- fps');

  // The stereo image's left view, for 2D while LeiaSR is off (the woven
  // image only exists while it runs). Over the viewport, so made last.
  FFlatBack := TRectangle.Create(Self);
  FFlatBack.Parent := FViewArea;
  FFlatBack.Align := TAlignLayout.Contents;
  FFlatBack.Fill.Color := TAlphaColors.Black;
  FFlatBack.Stroke.Kind := TBrushKind.None;
  FFlatBack.HitTest := False;
  FFlatBack.Visible := False;
  FFlatImage := TImage.Create(Self);
  FFlatImage.Parent := FFlatBack;
  FFlatImage.Align := TAlignLayout.Client;
  FFlatImage.WrapMode := TImageWrapMode.Fit;
  FFlatImage.HitTest := False;
end;

procedure TfrmMain.BuildControls;
var
  Bar: TLayout;
  Lbl: TLabel;
  Btn: TButton;
begin
  // One area at the bottom of the form: the toolbar, then the settings row,
  // then the log. Hiding the three one by one (full screen) let FMX restack
  // them in another order when they came back, so only the area is hidden,
  // and each container inside holds at most one control per alignment, so
  // the order cannot vary.
  FBottomArea := TLayout.Create(Self);
  FBottomArea.Parent := Self;
  FBottomArea.Align := TAlignLayout.Bottom;
  FBottomArea.Height := 36 + 30 + 170;

  FLog := TMemo.Create(Self);
  FLog.Parent := FBottomArea;
  FLog.Align := TAlignLayout.Bottom;
  FLog.Height := 170;

  FBarsArea := TLayout.Create(Self);
  FBarsArea.Parent := FBottomArea;
  FBarsArea.Align := TAlignLayout.Client;
  FLog.ReadOnly := True;
  FLog.TextSettings.Font.Family := 'Consolas';
  FLog.TextSettings.Font.Size := 11;

  // Settings row, under the toolbar
  Bar := TLayout.Create(Self);
  FSettingsBar := Bar;
  Bar.Parent := FBarsArea;
  Bar.Align := TAlignLayout.Client;
  Bar.Padding.Rect := RectF(8, 2, 8, 2);

  FLookAround := TCheckBox.Create(Self);
  FLookAround.Parent := Bar;
  SROnly(FLookAround);
  FLookAround.Align := TAlignLayout.Left;
  FLookAround.Width := 100;
  FLookAround.Margins.Left := 12;
  FLookAround.Text := 'Look-around';
  FLookAround.IsChecked := True;
  FLookAround.OnChange := LookAroundChange;

  Lbl := TLabel.Create(Self);
  Lbl.Parent := Bar;
  Lbl.Align := TAlignLayout.Left;
  Lbl.Width := 55;
  Lbl.Text := 'Latency';
  SROnly(Lbl);

  FLatency := TComboBox.Create(Self);
  FLatency.Parent := Bar;
  SROnly(FLatency);
  FLatency.Align := TAlignLayout.Left;
  FLatency.Width := 110;
  FLatency.Items.Add('SR default');
  FLatency.Items.Add('1 frame');
  FLatency.Items.Add('2 frames');
  FLatency.Items.Add('3 frames');
  FLatency.Items.Add('4 frames');
  FLatency.ItemIndex := 0;
  FLatency.OnChange := LatencyChange;

  Lbl := TLabel.Create(Self);
  Lbl.Parent := Bar;
  Lbl.Align := TAlignLayout.Left;
  Lbl.Width := 40;
  Lbl.Margins.Left := 12;
  Lbl.Text := 'Lens';
  SROnly(Lbl);

  FLens := TComboBox.Create(Self);
  FLens.Parent := Bar;
  SROnly(FLens);
  FLens.Align := TAlignLayout.Left;
  FLens.Width := 160;
  FLens.Items.Add('Off over controls');
  FLens.Items.Add('Always on');
  FLens.Items.Add('Always off (2D)');
  FLens.ItemIndex := 0;
  FLens.OnChange := LensChange;

  Lbl := TLabel.Create(Self);
  Lbl.Parent := Bar;
  Lbl.Align := TAlignLayout.Left;
  Lbl.Width := 45;
  Lbl.Margins.Left := 12;
  Lbl.Text := 'Show:';

  FShow := TComboBox.Create(Self);
  FShow.Parent := Bar;
  FShow.Align := TAlignLayout.Left;
  FShow.Width := 220;
  FShow.Items.Add('3D scene');
  FShow.ItemIndex := 0;
  FShow.OnChange := ShowChange;

  Bar := TLayout.Create(Self);
  FToolBar := Bar;
  Bar.Parent := FBarsArea;
  Bar.Align := TAlignLayout.Top;
  Bar.Height := 36;
  Bar.Padding.Rect := RectF(8, 4, 8, 4);

  FToggle := TCheckBox.Create(Self);
  FToggle.Parent := Bar;
  SROnly(FToggle);
  FToggle.Align := TAlignLayout.Left;
  FToggle.Width := 130;
  FToggle.Text := 'Glasses-free 3D';
  FToggle.IsChecked := True;
  FToggle.OnChange := ToggleChange;

  FPause := TCheckBox.Create(Self);
  FPause.Parent := Bar;
  FPause.Align := TAlignLayout.Left;
  FPause.Width := 110;
  FPause.Text := 'Pause rotation';
  FPause.OnChange := PauseChange;

  FFullScreen := TCheckBox.Create(Self);
  FFullScreen.Parent := Bar;
  FFullScreen.Align := TAlignLayout.Left;
  FFullScreen.Width := 110;
  FFullScreen.Text := 'Full screen (F11)';
  FFullScreen.OnChange := FullScreenChange;

  Btn := TButton.Create(Self);
  Btn.Parent := Bar;
  SROnly(Btn);
  Btn.Align := TAlignLayout.Left;
  Btn.Width := 90;
  Btn.Margins.Left := 8;
  Btn.Text := 'Settings...';
  Btn.OnClick := SettingsClick;

  Btn := TButton.Create(Self);
  Btn.Parent := Bar;
  Btn.Align := TAlignLayout.Right;
  Btn.Width := 80;
  Btn.Text := 'Copy log';
  Btn.OnClick := CopyLogClick;

  Btn := TButton.Create(Self);
  Btn.Parent := Bar;
  Btn.Align := TAlignLayout.Right;
  Btn.Width := 80;
  Btn.Margins.Right := 6;
  Btn.Text := 'Clear log';
  Btn.OnClick := ClearLogClick;

  FStatus := TLabel.Create(Self);
  FStatus.Parent := Bar;
  FStatus.Align := TAlignLayout.Client;
  FStatus.Margins.Left := 12;
  FStatus.Text := 'Starting...';
end;

procedure TfrmMain.FormCreate(Sender: TObject);
var
  C: TControl;
begin
  Caption := 'SRDemoFMX: LeiaSR + FireMonkey TViewport3D';
  Application.OnException := AppException;
  WindowState := TWindowState.wsMaximized;
  OnMouseWheel := FormMouseWheel;
  FFpsClock := TStopwatch.StartNew;
  BuildControls;
  BuildScene;

  FStereo := TSRStereoRenderer.Create(Self);
  FStereo.Viewport := FViewport;
  FStereo.FocusDistance := 20;
  FStereo.OnError := StereoError;
  // Stops SR again by itself if FMX would draw in software or on the wrong
  // GPU (StopWhenDegraded), and asks here what to do
  FStereo.OnStartProblem := StereoStartProblem;
  FStereo.OnStarted := StereoStarted;
  FStereo.OnLog := StereoLog;
  FStereo.OnEyesUpdated := StereoEyes;
  AddLog('Log file: ' + DiagLogFileName);
  if FastMM_DebugModeActive then
    AddLog(Format('FastMM5 full debug mode ON: debug blocks scanned every %d frames', [FastMMScanEvery]))
  else
    AddLog('FastMM5 full debug mode off');
  DiagLogAttachBridge;
  ListMedia;
  LoadSettings;
  InstallKeyHook;
  FSRInstalled := TSRStereoRenderer.SRInstalled;
  if not FSRInstalled then
  begin
    // As if the program had no SR support: no controls, no messages
    AddLog('LeiaSR runtime not installed: glasses-free 3D controls hidden, LeiaSR not started');
    for C in FSROnly do
      C.Visible := False;
    FStatus.Text := '';
  end
  else if FSettings.UseGlassesFree3D then
  begin
    SetToggleQuietly(True);
    FStereo.Active := True;   // completes once the form is shown
  end
  else
  begin
    SetToggleQuietly(False);
    AddLog('Glasses-free 3D is off in the settings (useGlassesFree3D false): LeiaSR not started');
    FStatus.Text := 'Glasses-free 3D off (tick Glasses-free 3D to use it)';
  end;
  UpdateFlatImage;
end;

function TfrmMain.SROnly(C: TControl): TControl;
begin
  FSROnly := FSROnly + [C];
  Result := C;
end;

procedure TfrmMain.FormClose(Sender: TObject; var Action: TCloseAction);
begin
  AddLog('Closing');
  FStereo.Active := False;
end;

procedure TfrmMain.InstallKeyHook;
begin
  KeyHookForm := Self;
  KeyHook := SetWindowsHookExW(WH_KEYBOARD, @KeyHookProc, 0, GetCurrentThreadId);
  if KeyHook = 0 then
    AddLog(Format('Keyboard hook NOT installed (error %d): F11 and Esc will not work',
      [GetLastError]))
  else
    AddLog('Keyboard hook installed: F11 toggles full screen, Esc leaves it');
end;

function TfrmMain.HookKey(Key: Word; IsRepeat: Boolean): Boolean;
var
  Leave: Boolean;
  Delta: Single;
begin
  // P logs a snapshot of everything that sets the view, for comparing
  // with StereoModel (owner, 7 November 2026)
  if Key = vkP then
  begin
    Result := True;
    if not IsRepeat then
      TThread.ForceQueue(nil,
        procedure
        begin
          if KeyHookForm <> nil then
            KeyHookForm.Snapshot;
        end);
    Exit;
  end;
  // R starts or stops the grid's spin
  if Key = vkR then
  begin
    Result := True;
    if not IsRepeat then
      TThread.ForceQueue(nil,
        procedure
        begin
          if KeyHookForm <> nil then
            KeyHookForm.ToggleGridSpin;
        end);
    Exit;
  end;
  // Page Up / Page Down move the scene as the wheel does (repeats too), Home
  // puts it back: for when the wheel does not reach the form
  if (Key = vkPrior) or (Key = vkNext) or (Key = vkHome) then
  begin
    Result := True;
    if Key = vkPrior then
      Delta := SceneStep
    else
      Delta := -SceneStep;
    TThread.ForceQueue(nil,
      procedure
      begin
        if KeyHookForm <> nil then
          KeyHookForm.MoveScene(Delta, Key = vkHome);
      end);
    Exit;
  end;
  Result := (Key = vkF11) or ((Key = vkEscape) and FFullScreen.IsChecked);
  if (not Result) or IsRepeat then
    Exit;
  Leave := Key = vkEscape;
  AddLog(Format('Key %s, full screen was %s, keyboard focus %s',
    [IfThenStr(Leave, 'Esc', 'F11'), BoolToStr(FFullScreen.IsChecked, True),
     FocusWindowName]));
  TThread.ForceQueue(nil,
    procedure
    begin
      if KeyHookForm <> nil then
        KeyHookForm.FullScreenKey(Leave);
    end);
end;

procedure TfrmMain.Snapshot;
begin
  FStereo.LogSnapshot(Format('SRDemoFMX scene: Z %.2f, tilt %.1f, roll %.1f deg, grid spin ' +
    '%.1f deg (%s); %s', [FSceneZ, FSceneTilt, FSceneRoll, FGridRoot.RotationAngle.Y,
    IfThenStr(FGridSpin.Pause, 'stopped', 'spinning'), DepthText]));
end;

procedure TfrmMain.ToggleGridSpin;
begin
  FGridSpin.Pause := not FGridSpin.Pause;
  AddLog(Format('Grid spin about the vertical axis %s (R), at %.0f degrees',
    [IfThenStr(FGridSpin.Pause, 'stopped', 'started'), FGridRoot.RotationAngle.Y]));
end;

procedure TfrmMain.MoveScene(Delta: Single; Reset: Boolean);
var
  Was: Single;
begin
  Was := FSceneZ;
  if Reset then
  begin
    FSceneZ := 0;
    if (FSceneTilt <> 0) or (FSceneRoll <> 0) then
    begin
      FSceneTilt := 0;
      FSceneRoll := 0;
      FSceneRoot.RotationAngle.X := 0;
      FSceneRoot.RotationAngle.Z := 0;
      AddLog('Scene tilt and roll back to level');
    end;
  end
  else
    FSceneZ := EnsureRange(FSceneZ + Delta, SceneZMin, SceneZMax);
  if SameValue(Was, FSceneZ) then
    Exit;
  FSceneRoot.Position.Z := FSceneZ;
  AddLog(Format('Scene moved to Z %.2f world units (%s)', [FSceneZ,
    IfThenStr(FSceneZ < 0, 'towards the viewer', IfThenStr(FSceneZ > 0, 'away', 'as built'))]) +
    IfThenStr(DepthText = '', '', ': ' + DepthText));
  if not FStereo.Running then
    FStatus.Text := Format('Scene Z %.2f (wheel or Page Up / Page Down; left-drag turns; Home ' +
      'resets both)', [FSceneZ]);
end;

procedure TfrmMain.FormMouseWheel(Sender: TObject; Shift: TShiftState; WheelDelta: Integer;
  var Handled: Boolean);
var
  Step: Single;
begin
  // A list or track bar under the pointer keeps its own wheel
  if Handled then
    Exit;
  Step := SceneStep;
  if ssShift in Shift then
    Step := Step * 0.25;
  MoveScene(Step * WheelDelta / 120, False);
  Handled := True;
end;

procedure TfrmMain.ViewportMouseDown(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: Single);
begin
  if Button <> TMouseButton.mbLeft then
    Exit;
  FTilting := True;
  FTiltStartX := X;
  FTiltStartY := Y;
  FTiltStartAngle := FSceneTilt;
  FRollStartAngle := FSceneRoll;
end;

procedure TfrmMain.ViewportMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Single);
begin
  if not FTilting then
    Exit;
  // Up tilts the far side down, as when the viewer stands up; right rolls
  // the scene clockwise
  FSceneTilt := EnsureRange(FTiltStartAngle + (FTiltStartY - Y) * TiltPerPixel, -TiltMax, TiltMax);
  FSceneRoll := EnsureRange(FRollStartAngle + (X - FTiltStartX) * TiltPerPixel, -RollMax, RollMax);
  FSceneRoot.RotationAngle.X := FSceneTilt;
  FSceneRoot.RotationAngle.Z := FSceneRoll;
end;

procedure TfrmMain.ViewportMouseUp(Sender: TObject; Button: TMouseButton; Shift: TShiftState;
  X, Y: Single);
begin
  if (Button <> TMouseButton.mbLeft) or not FTilting then
    Exit;
  FTilting := False;
  AddLog(Format('Scene tilted %.1f and rolled %.1f degrees about the main sphere (left-drag; ' +
    'Home levels it)', [FSceneTilt, FSceneRoll]) + IfThenStr(DepthText = '', '', ': ' + DepthText));
end;

function TfrmMain.DepthText: string;
var
  Scale, Front: Single;
  I: Integer;
  Parts: string;
begin
  Result := '';
  Scale := FStereo.WorldUnitsPerMM;
  if Scale <= 0 then
    Exit;
  // The glass is the plane Z = 0 (FocusDistance in front of the camera at
  // Z = -20). Each sphere's centre in the world, so with the scene's move
  // and tilt, from the main sphere to the nearest: negative is behind it.
  Parts := '';
  for I := 0 downto -RowHalf do
  begin
    Front := -FDepthRow[I].AbsolutePosition.Z;
    if Parts <> '' then
      Parts := Parts + ' ';
    Parts := Parts + Format('%.0f', [Front / Scale]);
  end;
  Result := Format('depths %s mm in front of the glass (green to red), furthest blue %.0f mm ' +
    'behind, viewer %.0f mm, scene Z %.2f, tilt %.0f, roll %.0f deg', [Parts,
    FDepthRow[RowHalf].AbsolutePosition.Z / Scale, FStereo.LeftEyeMM.Z, FSceneZ, FSceneTilt,
    FSceneRoll]);
end;

procedure TfrmMain.FullScreenKey(Leave: Boolean);
begin
  if Leave then
    FFullScreen.IsChecked := False
  else
    FFullScreen.IsChecked := not FFullScreen.IsChecked;
end;

procedure TfrmMain.AddLog(const Msg: string);
begin
  FLog.Lines.BeginUpdate;
  try
    while FLog.Lines.Count >= MaxLogLines do
      FLog.Lines.Delete(0);
    FLog.Lines.Add(FormatDateTime('hh:nn:ss.zzz', Now) + '  ' + Msg);
  finally
    FLog.Lines.EndUpdate;
  end;
  FLog.GoToTextEnd;
  DiagLog(Msg);
end;

procedure TfrmMain.ToggleChange(Sender: TObject);
begin
  // The user's choice, kept for the next start; a failed start does not
  // change it (SetToggleQuietly)
  if (FSettings <> nil) and (FSettings.UseGlassesFree3D <> FToggle.IsChecked) then
  begin
    FSettings.UseGlassesFree3D := FToggle.IsChecked;
    SaveSettings;
  end;
  if FToggle.IsChecked then
  begin
    FStatus.Text := 'Starting LeiaSR...';
    FStereo.Active := True;
  end
  else
  begin
    FStereo.Active := False;
    FStatus.Text := 'Glasses-free 3D off (LeiaSR stopped)';
  end;
  UpdateFlatImage;
end;

procedure TfrmMain.PauseChange(Sender: TObject);
const
  State: array[Boolean] of string = ('running', 'paused');
var
  I: Integer;
begin
  for I := Low(FSpins) to High(FSpins) do
    FSpins[I].Pause := FPause.IsChecked;
  AddLog('Rotation ' + State[FPause.IsChecked]);
end;

procedure TfrmMain.FullScreenChange(Sender: TObject);
begin
  // Full screen shows only the 3D view; F11 or Esc brings the rest back
  FBottomArea.Visible := not FFullScreen.IsChecked;
  // The renderer's full screen, not the form's: FMX's re-creates the window
  // and sizes it in steps at display scaling, and SR restarted part way
  // through wove for the wrong size
  FStereo.FullScreen := FFullScreen.IsChecked;
  AddLog(Format('Full screen %s: form now %d x %d logical (F11 or Esc to leave)',
    [BoolToStr(FStereo.FullScreen, True), Width, Height]));
  if FSettings <> nil then
  begin
    FSettings.FullScreen := FFullScreen.IsChecked;
    SaveSettings;
  end;
end;

procedure TfrmMain.ListMedia;
const
  SubFolders: array[0..1] of string = ('', 'local\');
var
  Dir, Candidate, Sub: string;
  I: Integer;
  F: TSearchRec;
begin
  // The exe is in SRDemoFMX\Win64\Debug; look upwards for the repository's media
  Dir := ExtractFilePath(ParamStr(0));
  for I := 1 to 5 do
  begin
    Candidate := IncludeTrailingPathDelimiter(Dir) + 'media';
    if DirectoryExists(Candidate) then
    begin
      FMediaFolder := IncludeTrailingPathDelimiter(Candidate);
      Break;
    end;
    Dir := ExtractFileDir(ExcludeTrailingPathDelimiter(Dir));
  end;
  if FMediaFolder = '' then
  begin
    AddLog('No media folder found above ' + ExtractFilePath(ParamStr(0)));
    Exit;
  end;
  // media\ holds images that may be published; media\local\ (ignored by
  // git) holds images that may not, such as film stills
  for Sub in SubFolders do
    if FindFirst(FMediaFolder + Sub + '*.*', faAnyFile, F) = 0 then
    try
      repeat
        if SameText(ExtractFileExt(F.Name), '.png') or SameText(ExtractFileExt(F.Name), '.jpg') or
          SameText(ExtractFileExt(F.Name), '.jpeg') then
          FShow.Items.Add(Sub + F.Name);
      until FindNext(F) <> 0;
    finally
      FindClose(F);
    end;
  AddLog(Format('%d stereo images in %s', [FShow.Items.Count - 1, FMediaFolder]));
end;

procedure TfrmMain.ShowChange(Sender: TObject);
begin
  try
    if FShow.ItemIndex <= 0 then
      FStereo.ShowStereoImage('')
    else
      FStereo.ShowStereoImage(FMediaFolder + FShow.Items[FShow.ItemIndex]);
  except
    on E: Exception do
      AddLog('Cannot show ' + FShow.Items[FShow.ItemIndex] + ': ' + E.Message);
  end;
  UpdateFlatImage;
  if FSettings <> nil then
  begin
    if FShow.ItemIndex <= 0 then
      FSettings.StereoImage := ''
    else
      FSettings.StereoImage := FShow.Items[FShow.ItemIndex];
    SaveSettings;
  end;
end;

destructor TfrmMain.Destroy;
begin
  KeyHookForm := nil;
  if KeyHook <> 0 then
    UnhookWindowsHookEx(KeyHook);
  KeyHook := 0;
  FSettings.Free;
  FFpsBitmap.Free;
  inherited;
end;

procedure TfrmMain.LoadSettings;
var
  I: Integer;
begin
  FSettings := TSRSettings.Create;
  try
    if FSettings.Load then
      AddLog('Settings read from ' + TSRSettings.SettingsFileName)
    else
      AddLog('No settings file yet; defaults used (' + TSRSettings.SettingsFileName + ')');
  except
    on E: Exception do
      AddLog(E.Message + '; defaults used');
  end;
  FLoading := True;
  try
    FLookAround.IsChecked := FSettings.LookAround;
    FLatency.ItemIndex := EnsureRange(FSettings.LatencyFrames, 0, FLatency.Items.Count - 1);
    FStereo.EyeSeparationMM := FSettings.EyeSeparationMM;
    // Depth is always the real eye separation now (the Depth slider is
    // gone); a value saved by it is put back to 1
    FStereo.EyeSeparationScale := 1;
    FStereo.FocusDistance := FSettings.FocusDistance;
    FStereo.LookAround := FSettings.LookAround;
    FStereo.LatencyFrames := FSettings.LatencyFrames;
    FLens.ItemIndex := EnsureRange(FSettings.LensMode, 0, FLens.Items.Count - 1);
    FStereo.LensMode := TSRLensMode(FLens.ItemIndex);
    for I := 1 to FShow.Items.Count - 1 do
      if SameText(FShow.Items[I], FSettings.StereoImage) then
        FShow.ItemIndex := I;
    FFullScreen.IsChecked := FSettings.FullScreen;
  finally
    FLoading := False;
  end;
  AddLog(Format('Settings: glasses-free 3D %s, eye separation %.0f mm, depth %.2f, focus %.1f, ' +
    'look-around %s, latency %d, lens %s, image "%s", full screen %s',
    [BoolToStr(FSettings.UseGlassesFree3D, True), FSettings.EyeSeparationMM,
    FSettings.EyeSeparationScale, FSettings.FocusDistance, BoolToStr(FSettings.LookAround, True),
    FSettings.LatencyFrames, FLens.Items[FLens.ItemIndex], FSettings.StereoImage,
    BoolToStr(FSettings.FullScreen, True)]));
  if not SameValue(FSettings.EyeSeparationScale, 1) then
  begin
    AddLog(Format('Depth %.2f from the old Depth slider put back to 1 (the real eye separation)',
      [FSettings.EyeSeparationScale]));
    FSettings.EyeSeparationScale := 1;
    SaveSettings;
  end;
end;

procedure TfrmMain.SaveSettings;
begin
  if FLoading or (FSettings = nil) then
    Exit;
  try
    FSettings.Save;
  except
    on E: Exception do
      AddLog(E.Message);
  end;
end;

procedure TfrmMain.SettingsClick(Sender: TObject);
var
  MM: Integer;
begin
  MM := Round(FSettings.EyeSeparationMM);
  // A Windows dialog owned by the form, in front of it, with the lens off
  FStereo.SuspendLens(True);
  try
    if not AskEyeSeparation(FormToHWND(Self), 'SRDemoFMX', MM) then
      Exit;
  finally
    FStereo.SuspendLens(False);
  end;
  FStereo.EyeSeparationMM := MM;
  FSettings.EyeSeparationMM := MM;
  if MM = 0 then
    AddLog('Eye separation: as tracked')
  else
    AddLog(Format('Eye separation: %d mm', [MM]));
  SaveSettings;
end;

procedure TfrmMain.LookAroundChange(Sender: TObject);
const
  State: array[Boolean] of string = ('off (fixed viewer)', 'on');
begin
  FStereo.LookAround := FLookAround.IsChecked;
  if FSettings <> nil then
    FSettings.LookAround := FLookAround.IsChecked;
  AddLog('Look-around ' + State[FLookAround.IsChecked]);
  SaveSettings;
end;

procedure TfrmMain.LensChange(Sender: TObject);
begin
  FStereo.LensMode := TSRLensMode(FLens.ItemIndex);
  if FSettings <> nil then
    FSettings.LensMode := FLens.ItemIndex;
  AddLog('Lens: ' + FLens.Items[FLens.ItemIndex]);
  SaveSettings;
end;

procedure TfrmMain.LatencyChange(Sender: TObject);
begin
  FStereo.LatencyFrames := FLatency.ItemIndex;
  if FSettings <> nil then
    FSettings.LatencyFrames := FLatency.ItemIndex;
  AddLog('Weaver latency: ' + FLatency.Items[FLatency.ItemIndex]);
  SaveSettings;
end;

procedure TfrmMain.AppException(Sender: TObject; E: Exception);
begin
  DiagLog('EXCEPTION reached the application: ' + E.ClassName + ': ' + E.Message);
  Application.ShowException(E);
end;

procedure TfrmMain.CopyLogClick(Sender: TObject);
var
  Clip: IFMXClipboardService;
begin
  if TPlatformServices.Current.SupportsPlatformService(IFMXClipboardService, Clip) then
  begin
    Clip.SetClipboard(FLog.Lines.Text);
    FStatus.Text := Format('Copied %d log lines', [FLog.Lines.Count]);
  end;
end;

procedure TfrmMain.ClearLogClick(Sender: TObject);
begin
  FLog.Lines.Clear;
end;

procedure TfrmMain.StereoError(Sender: TObject; const Msg: string);
begin
  FStatus.Text := 'LeiaSR error: ' + Msg;
  TThread.ForceQueue(nil,
    procedure
    begin
      SetToggleQuietly(FStereo.Active);
      UpdateFlatImage;
    end);
end;

procedure TfrmMain.SetToggleQuietly(Value: Boolean);
begin
  FToggle.OnChange := nil;
  try
    FToggle.IsChecked := Value;
  finally
    FToggle.OnChange := ToggleChange;
  end;
end;

procedure TfrmMain.UpdateFlatImage;
var
  Show: Boolean;
begin
  Show := not FStereo.Running and (FStereo.StereoImageFile <> '');
  if Show then
    Show := FStereo.CopyLeftView(FFlatImage.Bitmap);
  if Show <> FFlatBack.Visible then
    AddLog(IfThenStr(Show, 'Showing the stereo image''s left view in 2D (LeiaSR off)',
      'No 2D image over the viewport'));
  FFlatBack.Visible := Show;
end;

procedure TfrmMain.StereoStarted(Sender: TObject);
begin
  SetToggleQuietly(True);
  UpdateFlatImage;
end;

procedure TfrmMain.StereoStartProblem(Sender: TObject; Problem: TSRStartProblem;
  const Msg: string; CanDegrade, CanFixGpu: Boolean; var Choice: TSRStartChoice);
const
  ChoiceNames: array[TSRStartChoice] of string = ('continue without glasses-free 3D',
    'try again', 'use glasses-free 3D anyway', 'exit');
var
  Owner: NativeUInt;
  FixWanted: Boolean;
  FixText: string;
begin
  // Called from the message queue with LeiaSR off, so the dialog is readable
  FStatus.Text := 'Glasses-free 3D off: ' + StartProblemName(Problem);
  SetToggleQuietly(False);
  UpdateFlatImage;
  FixText := '';
  if CanFixGpu then
    FixText := 'Also set SRDemoFMX to use the high-performance GPU (from its next start)';
  Owner := FormToHWND(Self);
  Choice := AskStartProblem(Owner, 'SRDemoFMX', Problem, Msg, CanDegrade, FixText, FixWanted);
  AddLog(Format('Start problem (%s): the user chose to %s%s', [StartProblemName(Problem),
    ChoiceNames[Choice], IfThenStr(FixWanted, ', and the high-performance GPU', '')]));
  if FixWanted then
  begin
    if FStereo.SetHighPerformanceGpu then
      MessageBoxW(Owner, 'Done. Close SRDemoFMX and start it again for glasses-free 3D at full speed.',
        'SRDemoFMX: GPU', MB_OK or MB_ICONINFORMATION or MB_SETFOREGROUND)
    else
      MessageBoxW(Owner, 'Windows did not accept the setting. Set it by hand in Settings > ' +
        'System > Display > Graphics.', 'SRDemoFMX: GPU',
        MB_OK or MB_ICONWARNING or MB_SETFOREGROUND);
  end;
  if Choice = scExit then
    FStatus.Text := 'Closing'
  else if Choice = scContinueWithoutSR then
    FStatus.Text := 'Glasses-free 3D off (' + StartProblemName(Problem) +
      '); tick Glasses-free 3D to try again'
  else
    FStatus.Text := 'Starting LeiaSR...';
end;

procedure TfrmMain.StereoLog(Sender: TObject; const Msg: string);
begin
  AddLog(Msg);
end;

procedure TfrmMain.StereoEyes(Sender: TObject; const LeftMM, RightMM: TPoint3D);
const
  Mode: array[Boolean] of string = ('2D fallback', 'Weaving');
begin
  // In full debug mode, look for heap corruption close to when it happens.
  // A corrupt block is logged to SRDemoFMX_FastMM.log with stack traces, and
  // an exception is raised, which the renderer reports and stops on.
  Inc(FFrames);
  if FastMM_DebugModeActive and (FFrames mod FastMMScanEvery = 0) then
    FastMM_ScanDebugBlocksForCorruption;
  // Once a second: the panel's picture is redrawn and copied to the GPU
  Inc(FFpsFrames);
  if FFpsClock.ElapsedMilliseconds >= 1000 then
  begin
    DrawFps(Format('%d fps', [Round(FFpsFrames * 1000 / FFpsClock.ElapsedMilliseconds)]));
    FFpsFrames := 0;
    FFpsClock := TStopwatch.StartNew;
  end;
  FStatus.Text := Format('%s   L(%.0f, %.0f, %.0f)  R(%.0f, %.0f, %.0f) mm   %s',
    [Mode[FStereo.Weaving], LeftMM.X, LeftMM.Y, LeftMM.Z, RightMM.X, RightMM.Y, RightMM.Z,
     DepthText]);
end;

end.

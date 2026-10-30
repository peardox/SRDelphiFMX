{ @abstract(Main window of SRDemo: a test scene on the LeiaSR display, with a
  log.)

  The scene is built in code so the form file stays trivial. The toolbar and
  the log sit outside the viewport, because the woven image covers the
  viewport with a native window that hides FMX controls drawn over it. }
unit MainForm;

interface

uses
  System.SysUtils, System.Types, System.UITypes, System.Classes, System.Math.Vectors,
  System.Rtti,
  FMX.Types, FMX.Controls, FMX.Forms, FMX.Graphics, FMX.StdCtrls, FMX.Layouts,
  FMX.Memo, FMX.Memo.Types, FMX.ScrollBox, FMX.Types3D, FMX.Controls3D, FMX.Objects3D,
  FMX.MaterialSources, FMX.Viewport3D, FMX.Ani, FMX.Platform, FMX.Controls.Presentation,
  FMX.ListBox, FMX.EditBox, FMX.NumberBox, SRSettings,
  FMX.SRStereoViewport;

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
    { The 3D view. }
    FViewport: TViewport3D;
    { The reference camera. }
    FCamera: TCamera;
    { Shows @link(FViewport) on the SR display. }
    FStereo: TSRStereoRenderer;
    { The cube's spin. }
    FSpin: TFloatAnimation;
    { Status line. }
    FStatus: TLabel;
    { Turns 3D on and off. }
    FToggle: TCheckBox;
    { Pauses the cube. }
    FPause: TCheckBox;
    { Full screen on and off. }
    FFullScreen: TCheckBox;
    { Eye separation scale. }
    FDepth: TTrackBar;
    { Diagnostic log. }
    FLog: TMemo;
    { The main toolbar, hidden in full screen. }
    FToolBar: TLayout;
    { The diagnostics row, hidden in full screen. }
    FDiagBar: TLayout;
    { Skip the eye tracker (use nominal eyes). }
    FSkipTracking: TCheckBox;
    { Skip rendering the scene. }
    FSkipRender: TCheckBox;
    { Skip handing the views to the bridge. }
    FSkipSubmit: TCheckBox;
    { Test: full screen without telling Windows and one row short. }
    FPlainFull: TCheckBox;
    { Frames drawn, for the periodic FastMM5 scan. }
    FFrames: Integer;
    { Chooses the 3D scene or one of the stereo images in the media folder. }
    FShow: TComboBox;
    { Eye separation in millimetres; 0 uses the tracker's measurement. }
    FEyeSep: TNumberBox;
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
    { Sets the eye separation scale.
      @param(Sender the track bar) }
    procedure DepthChange(Sender: TObject);
    { Finds the media folder and lists its images, and those in its
      @code(local) folder, in @link(FShow). }
    procedure ListMedia;
    { Shows the 3D scene or the chosen stereo image.
      @param(Sender the combo box) }
    procedure ShowChange(Sender: TObject);
    { Sets the eye separation from the number box.
      @param(Sender the number box) }
    procedure EyeSepChange(Sender: TObject);
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
    { Applies the diagnostic skip checkboxes to the renderer.
      @param(Sender a checkbox) }
    procedure SkipChange(Sender: TObject);
    { Sets the renderer's plain full-screen test mode.
      @param(Sender the checkbox) }
    procedure PlainFullChange(Sender: TObject);
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
      @returns(@true if the key was F11 or Esc in full screen and must not
        reach any control) }
    function HookKey(Key: Word; IsRepeat: Boolean): Boolean;
  end;

var
  { The main window. }
  frmMain: TfrmMain;

implementation

{$R *.fmx}

uses
  System.Math, FastMM5, SRDiagLog;

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

procedure TfrmMain.BuildScene;
const
  SphereColors: array[0..4] of TAlphaColor = (TAlphaColors.Tomato, TAlphaColors.Gold,
    TAlphaColors.Limegreen, TAlphaColors.Deepskyblue, TAlphaColors.Orchid);
var
  Light: TLight;
  Cube: TCube;
  Sphere: TSphere;
  Plane: TPlane;
  I: Integer;
begin
  FViewport := TViewport3D.Create(Self);
  FViewport.Parent := Self;
  FViewport.Align := TAlignLayout.Client;
  FViewport.Color := $FF101828;
  FViewport.UsingDesignCamera := False;

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

  // Back wall, well behind the screen
  Plane := TPlane.Create(Self);
  Plane.Parent := FViewport;
  Plane.Position.Point := Point3D(0, 0, 8);
  Plane.Width := 30;
  Plane.Height := 20;
  Plane.MaterialSource := MakeMaterial($FF35507A);

  // Cube on the screen plane, spinning
  Cube := TCube.Create(Self);
  Cube.Parent := FViewport;
  Cube.Width := 3;
  Cube.Height := 3;
  Cube.Depth := 3;
  Cube.MaterialSource := MakeMaterial($FFE8A33D);
  FSpin := TFloatAnimation.Create(Self);
  FSpin.Parent := Cube;
  FSpin.PropertyName := 'RotationAngle.Y';
  FSpin.StartValue := 0;
  FSpin.StopValue := 360;
  FSpin.Duration := 8;
  FSpin.Loop := True;
  FSpin.Enabled := True;

  // Spheres stepping from behind the screen (+Z) to in front of it (-Z)
  for I := 0 to 4 do
  begin
    Sphere := TSphere.Create(Self);
    Sphere.Parent := FViewport;
    Sphere.Width := 1.4;
    Sphere.Height := 1.4;
    Sphere.Depth := 1.4;
    Sphere.Position.Point := Point3D(-6 + I * 3, 3.5, 6 - I * 3);
    Sphere.MaterialSource := MakeMaterial(SphereColors[I]);
  end;
end;

procedure TfrmMain.BuildControls;
var
  Bar: TLayout;
  Lbl: TLabel;
  Btn: TButton;
begin
  // Bottom-aligned controls are stacked by Position.Y, so set it before
  // aligning: the log at the very bottom, the toolbar above it.
  FLog := TMemo.Create(Self);
  FLog.Parent := Self;
  FLog.Position.Y := 10000;
  FLog.Align := TAlignLayout.Bottom;
  FLog.Height := 170;
  FLog.ReadOnly := True;
  FLog.TextSettings.Font.Family := 'Consolas';
  FLog.TextSettings.Font.Size := 11;

  // Diagnostics row, between the toolbar and the log
  Bar := TLayout.Create(Self);
  FDiagBar := Bar;
  Bar.Parent := Self;
  Bar.Position.Y := 5000;
  Bar.Align := TAlignLayout.Bottom;
  Bar.Height := 30;
  Bar.Padding.Rect := RectF(8, 2, 8, 2);

  Lbl := TLabel.Create(Self);
  Lbl.Parent := Bar;
  Lbl.Align := TAlignLayout.Left;
  Lbl.Width := 80;
  Lbl.Text := 'Diagnostics:';

  FSkipTracking := TCheckBox.Create(Self);
  FSkipTracking.Parent := Bar;
  FSkipTracking.Align := TAlignLayout.Left;
  FSkipTracking.Width := 150;
  FSkipTracking.Text := 'Skip eye tracking';
  FSkipTracking.OnChange := SkipChange;

  FSkipRender := TCheckBox.Create(Self);
  FSkipRender.Parent := Bar;
  FSkipRender.Align := TAlignLayout.Left;
  FSkipRender.Width := 150;
  FSkipRender.Text := 'Skip rendering';
  FSkipRender.OnChange := SkipChange;

  FSkipSubmit := TCheckBox.Create(Self);
  FSkipSubmit.Parent := Bar;
  FSkipSubmit.Align := TAlignLayout.Left;
  FSkipSubmit.Width := 180;
  FSkipSubmit.Text := 'Skip weaving (bridge)';
  FSkipSubmit.OnChange := SkipChange;

  FPlainFull := TCheckBox.Create(Self);
  FPlainFull.Parent := Bar;
  FPlainFull.Align := TAlignLayout.Left;
  FPlainFull.Width := 150;
  FPlainFull.Text := 'Plain full screen (test)';
  FPlainFull.OnChange := PlainFullChange;

  Lbl := TLabel.Create(Self);
  Lbl.Parent := Bar;
  Lbl.Align := TAlignLayout.Left;
  Lbl.Width := 175;
  Lbl.Margins.Left := 12;
  Lbl.Text := 'Eye separation mm (0 = tracked)';

  FEyeSep := TNumberBox.Create(Self);
  FEyeSep.Parent := Bar;
  FEyeSep.Align := TAlignLayout.Left;
  FEyeSep.Width := 60;
  FEyeSep.Min := 0;
  FEyeSep.Max := 90;
  FEyeSep.DecimalDigits := 0;
  FEyeSep.Value := DEFAULT_EYE_SEPARATION_MM;
  FEyeSep.OnChange := EyeSepChange;

  FLookAround := TCheckBox.Create(Self);
  FLookAround.Parent := Bar;
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

  FLatency := TComboBox.Create(Self);
  FLatency.Parent := Bar;
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

  FLens := TComboBox.Create(Self);
  FLens.Parent := Bar;
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
  Bar.Parent := Self;
  Bar.Position.Y := 0;
  Bar.Align := TAlignLayout.Bottom;
  Bar.Height := 36;
  Bar.Padding.Rect := RectF(8, 4, 8, 4);

  FToggle := TCheckBox.Create(Self);
  FToggle.Parent := Bar;
  FToggle.Align := TAlignLayout.Left;
  FToggle.Width := 100;
  FToggle.Text := '3D (LeiaSR)';
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

  Lbl := TLabel.Create(Self);
  Lbl.Parent := Bar;
  Lbl.Align := TAlignLayout.Left;
  Lbl.Width := 50;
  Lbl.Text := 'Depth';

  FDepth := TTrackBar.Create(Self);
  FDepth.Parent := Bar;
  FDepth.Align := TAlignLayout.Left;
  FDepth.Width := 120;
  FDepth.Min := 0;
  FDepth.Max := 2;
  FDepth.Value := 1;
  FDepth.OnChange := DepthChange;

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
begin
  Caption := 'SRDemo: LeiaSR + FireMonkey TViewport3D';
  Application.OnException := AppException;
  WindowState := TWindowState.wsMaximized;
  BuildControls;
  BuildScene;

  FStereo := TSRStereoRenderer.Create(Self);
  FStereo.Viewport := FViewport;
  FStereo.FocusDistance := 20;
  FStereo.OnError := StereoError;
  FStereo.OnLog := StereoLog;
  FStereo.OnEyesUpdated := StereoEyes;
  FStereo.TraceFrames := 5;   // stage-by-stage log of the first frames
  AddLog('Log file: ' + DiagLogFileName);
  if FastMM_DebugModeActive then
    AddLog(Format('FastMM5 full debug mode ON: debug blocks scanned every %d frames', [FastMMScanEvery]))
  else
    AddLog('FastMM5 full debug mode off');
  DiagLogAttachBridge;
  ListMedia;
  LoadSettings;
  InstallKeyHook;
  FStereo.Active := True;   // completes once the form is shown
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
begin
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
  if FToggle.IsChecked then
  begin
    FStatus.Text := 'Starting LeiaSR...';
    FStereo.Active := True;
  end
  else
  begin
    FStereo.Active := False;
    FStatus.Text := '2D (LeiaSR off)';
  end;
end;

procedure TfrmMain.PauseChange(Sender: TObject);
const
  State: array[Boolean] of string = ('running', 'paused');
begin
  FSpin.Pause := FPause.IsChecked;
  AddLog('Rotation ' + State[FPause.IsChecked]);
end;

procedure TfrmMain.FullScreenChange(Sender: TObject);
begin
  // Full screen shows only the 3D view; F11 or Esc brings the rest back
  FToolBar.Visible := not FFullScreen.IsChecked;
  FDiagBar.Visible := not FFullScreen.IsChecked;
  FLog.Visible := not FFullScreen.IsChecked;
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

procedure TfrmMain.DepthChange(Sender: TObject);
begin
  FStereo.EyeSeparationScale := FDepth.Value;
  if FSettings <> nil then
  begin
    FSettings.EyeSeparationScale := FDepth.Value;
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
  // The exe is in SRDemo\Win64\Debug; look upwards for the repository's media
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
    FEyeSep.Value := FSettings.EyeSeparationMM;
    FDepth.Value := FSettings.EyeSeparationScale;
    FLookAround.IsChecked := FSettings.LookAround;
    FLatency.ItemIndex := EnsureRange(FSettings.LatencyFrames, 0, FLatency.Items.Count - 1);
    FStereo.EyeSeparationMM := FSettings.EyeSeparationMM;
    FStereo.EyeSeparationScale := FSettings.EyeSeparationScale;
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
  AddLog(Format('Settings: eye separation %.0f mm, depth %.2f, focus %.1f, look-around %s, ' +
    'latency %d, lens %s, image "%s", full screen %s', [FSettings.EyeSeparationMM,
    FSettings.EyeSeparationScale, FSettings.FocusDistance, BoolToStr(FSettings.LookAround, True),
    FSettings.LatencyFrames, FLens.Items[FLens.ItemIndex], FSettings.StereoImage,
    BoolToStr(FSettings.FullScreen, True)]));
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

procedure TfrmMain.EyeSepChange(Sender: TObject);
begin
  FStereo.EyeSeparationMM := FEyeSep.Value;
  if FSettings <> nil then
    FSettings.EyeSeparationMM := FEyeSep.Value;
  if FEyeSep.Value = 0 then
    AddLog('Eye separation: as tracked')
  else
    AddLog(Format('Eye separation: %.0f mm', [FEyeSep.Value]));
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

procedure TfrmMain.PlainFullChange(Sender: TObject);
begin
  FStereo.FullScreenPlain := FPlainFull.IsChecked;
  AddLog('Plain full screen (test) ' + BoolToStr(FPlainFull.IsChecked, True) +
    ': applies the next time full screen is entered');
end;

procedure TfrmMain.SkipChange(Sender: TObject);
var
  Skip: TSRDiagnosticSkips;
begin
  Skip := [];
  if FSkipTracking.IsChecked then
    Include(Skip, dsTracking);
  if FSkipRender.IsChecked then
    Include(Skip, dsRender);
  if FSkipSubmit.IsChecked then
    Include(Skip, dsSubmit);
  FStereo.DiagnosticSkip := Skip;
  AddLog(Format('Diagnostics: skip tracking %s, rendering %s, weaving %s',
    [BoolToStr(dsTracking in Skip, True), BoolToStr(dsRender in Skip, True),
     BoolToStr(dsSubmit in Skip, True)]));
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
      FToggle.OnChange := nil;
      FToggle.IsChecked := FStereo.Active;
      FToggle.OnChange := ToggleChange;
    end);
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
  // A corrupt block is logged to SRDemo_FastMM.log with stack traces, and
  // an exception is raised, which the renderer reports and stops on.
  Inc(FFrames);
  if FastMM_DebugModeActive and (FFrames mod FastMMScanEvery = 0) then
    FastMM_ScanDebugBlocksForCorruption;
  FStatus.Text := Format('%s   L(%.0f, %.0f, %.0f)  R(%.0f, %.0f, %.0f) mm',
    [Mode[FStereo.Weaving], LeftMM.X, LeftMM.Y, LeftMM.Z, RightMM.X, RightMM.Y, RightMM.Z]);
end;

end.

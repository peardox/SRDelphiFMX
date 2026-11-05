{ @abstract(SRDemoVCL's main window: VCL controls, and a 3D scene drawn by
  the bridge itself on the GPU and woven onto the LeiaSR display.)

  VCL has no 3D, so the scene (a back wall, a floor, a turning cube on the
  glass and four spheres in front of and behind it) is drawn by
  @code(srb_RenderScene) in the bridge, straight into the view texture, one
  off-axis projection per eye. Nothing is read back to the CPU, unlike
  SRDemoFMX, where FMX renders each eye and the pixels are copied back and
  uploaded again. The viewport is a plain @code(TPanel); the bridge's child
  window covers it.

  The toolbar chooses what is shown (the scene, the test pattern or a
  side-by-side image from @code(media)), rotation, look-around, depth, eye
  separation, view size and when the lens is on. F11 toggles full screen
  on the SR display, Esc leaves it. Choices are kept with SRDemoFMX's in
  @code(%APPDATA%\SRDelphiFMX\settings.json). Everything is logged to
  @code(SRDemoVCL.log) beside the executable and to the log panel. }
unit MainFormVCL;

interface

uses
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Classes, System.Types,
  System.Diagnostics, Vcl.Controls, Vcl.Forms, Vcl.StdCtrls, Vcl.ExtCtrls,
  Vcl.ComCtrls, SRSettings, SRStereoImage, SRBridge.Api, SRStartProblem;

type
  { What the lens does: as SRDemoFMX's @code(LensMode). }
  TLensChoice = (
    { On while the pointer is over the viewport or in full screen, off over
      the controls (the controls look soft through the lens). }
    lcOffOverControls,
    { Always on. }
    lcAlwaysOn,
    { Always off: a 2D picture. }
    lcAlwaysOff);

  { The main window. }
  TfrmMainVCL = class(TForm)
    { Creates the controls, loads the settings and the image list. }
    procedure FormCreate(Sender: TObject);
    { Stops the bridge and saves the settings. }
    procedure FormDestroy(Sender: TObject);
    { Starts the bridge once the window is on screen. }
    procedure FormShow(Sender: TObject);
    { F11 toggles full screen, Esc leaves it; Page Up and Page Down move the
      scene, Home puts it back; R starts and stops the grid's spin. }
    procedure FormKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
  private
    { The toolbar. }
    FTop: TPanel;
    { The viewport: the bridge's child window covers it. }
    FViewport: TPanel;
    { The log panel. }
    FLog: TMemo;
    { The status line. }
    FStatus: TStatusBar;
    { Weaving on or off (starts and stops the bridge). }
    FWeave: TCheckBox;
    { Whether the background check of LeiaSR is running. }
    FProbing: Boolean;
    { Whether it found SR ready; used up by the next @link(StartBridge). }
    FProbeOK: Boolean;
    { When it started, ms on @code(FClock). }
    FProbeStartMs: Int64;
    { What to show: the 3D scene, the test pattern or an image. }
    FShow: TComboBox;
    { Turn the cube. }
    FRotate: TCheckBox;
    { Look-around on, or a fixed viewer. }
    FLookAround: TCheckBox;
    { How far the scene is moved away from the viewer, world units
      (negative: towards). }
    FSceneZ: Single;
    { The scene's tilt about the horizontal axis through the main sphere,
      degrees. }
    FSceneTilt: Single;
    { The scene's roll about the depth axis through the main sphere,
      degrees. }
    FSceneRoll: Single;
    { The sphere grid's turn about the vertical axis, degrees. }
    FGridSpin: Single;
    { Whether the grid is spinning (R). }
    FGridSpinning: Boolean;
    { Whether a left-button drag is turning the scene. }
    FTilting: Boolean;
    { The pointer and the tilt and roll when the drag started. }
    FTiltStartX, FTiltStartY: Integer;
    { The tilt and roll when the drag started, degrees. }
    FTiltStartAngle, FRollStartAngle: Single;
    { The last second's frame rate, drawn on the glass; -1 before the
      first. }
    FLastFps: Integer;
    { A hidden window for posted messages: it stays the same when the form's
      window is made again (full screen), and a message to it after it has gone
      is dropped. }
    FMsgWnd: HWND;
    { The start problem to ask about. }
    FProblem: TSRStartProblem;
    { Its message. }
    FProblemMsg: string;
    { View size: the viewport's, or half of it. }
    FViewSize: TComboBox;
    { When the lens is on. }
    FLens: TComboBox;
    { One-shot timer that starts the bridge after the window is shown. }
    FStartTimer: TTimer;

    { The saved settings. }
    FSettings: TSRSettings;
    { @true while settings are being put into the controls, so their change
      events do not save. }
    FLoading: Boolean;
    { Image files found in @code(media). }
    FImageFiles: TStringList;
    { The image being shown, when one is. }
    FImage: TSRStereoImage;
    { The side-by-side pixels of @link(FImage) at the current view size. }
    FImagePixels: TBytes;
    { The view size @link(FImagePixels) was made for. }
    FImageViewSize: TSize;
    { @true when @link(FImagePixels) must be rebuilt. }
    FImageDirty: Boolean;

    { @true while the bridge is initialised. }
    FRunning: Boolean;
    { @true while full screen. }
    FFullScreen: Boolean;
    { The window's placement before full screen. }
    FPlacement: TWindowPlacement;
    { The SR display's rectangle on the desktop, physical pixels. }
    FSRRect: TRect;
    { @true when @link(FSRRect) is known. }
    FSRRectKnown: Boolean;
    { Viewport size last given to @code(srb_SetBounds). }
    FBounds: TSize;
    { The lens state last asked for. }
    FLensOn: Boolean;
    { @link(FClock) milliseconds since the lens has wanted to change, -1 when
      it does not. }
    FLensWantSinceMs: Int64;
    { The cube's turn in radians. }
    FRotation: Double;

    { Time since the start. }
    FClock: TStopwatch;
    { @link(FClock) milliseconds of the previous frame. }
    FPrevFrameMs: Int64;
    { @link(FClock) milliseconds of the last status update. }
    FLastStatusMs: Int64;
    { @link(FClock) milliseconds of the last log summary. }
    FLastSummaryMs: Int64;
    { Frames since the last status update. }
    FFrames: Integer;
    { Longest frame since the last summary, milliseconds. }
    FWorstFrameMs: Int64;
    { The last scene info from the bridge. }
    FLastInfo: TSRBSceneInfo;

    { Builds the toolbar, viewport, log and status line. }
    procedure BuildControls;
    { Opens the settings dialog (the eye separation), with the lens off.
      @param(Sender the button) }
    procedure SettingsClick(Sender: TObject);
    { The mouse wheel moves the scene, as in SRDemoFMX: away for a forward
      turn, towards for a backward one; Shift for small steps.
      @param(Sender the form) @param(Shift the modifier keys)
      @param(WheelDelta 120 per notch, positive forwards)
      @param(MousePos the pointer, screen pixels)
      @param(Handled set when used) }
    procedure FormMouseWheel(Sender: TObject; Shift: TShiftState; WheelDelta: Integer;
      MousePos: TPoint; var Handled: Boolean);
    { Starts turning the scene on a left-button press over the viewport.
      @param(Sender the viewport) @param(Button which button)
      @param(Shift the modifier keys) @param(X pointer x) @param(Y pointer y) }
    procedure ViewportMouseDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState;
      X, Y: Integer);
    { Turns the scene while the left button is held: up and down tilts it,
      left and right rolls it, about the main sphere.
      @param(Sender the viewport) @param(Shift the modifier keys)
      @param(X pointer x) @param(Y pointer y) }
    procedure ViewportMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Integer);
    { Ends the turn and logs it.
      @param(Sender the viewport) @param(Button which button)
      @param(Shift the modifier keys) @param(X pointer x) @param(Y pointer y) }
    procedure ViewportMouseUp(Sender: TObject; Button: TMouseButton; Shift: TShiftState;
      X, Y: Integer);
    { Moves the scene in depth, or puts it (and its tilt and roll) back.
      @param(Delta world units; negative is towards the viewer)
      @param(Reset @true puts it back as built, ignoring Delta) }
    procedure MoveScene(Delta: Single; Reset: Boolean);
    { The status bar's depth line: the middle column of spheres' distances
      in mm in front of the glass, and where the scene is.
      @returns(the text, empty before the first frame) }
    function DepthText: string;
    { Adds a label to the toolbar. @param(Text its text) @returns(the label) }
    function AddLabel(const Text: string): TLabel;
    { Puts the saved settings into the controls. }
    procedure SettingsToControls;
    { Saves the controls' values, unless loading. }
    procedure SaveSettings;
    { A toolbar control changed. @param(Sender the control) }
    procedure ControlChanged(Sender: TObject);
    { Weaving was ticked or unticked. @param(Sender the check box) }
    procedure WeaveClicked(Sender: TObject);
    { Starts the bridge from the one-shot timer. @param(Sender the timer) }
    procedure StartTimerFired(Sender: TObject);
    { Finds the side-by-side images in @code(media). }
    procedure FindImages;
    { Loads the image or pattern the Show box names. }
    procedure LoadShownImage;
    { Initialises the bridge on the viewport. }
    procedure StartBridge;
    { Finalises the bridge. }
    procedure StopBridge;
    { Runs @code(srb_Probe) on a background thread (up to 5 s); its answer
      goes to @link(ProbeDone) through the main thread's queue. }
    procedure StartProbe;
    { The background check's answer: starts the bridge if SR is ready, or
      asks the user what to do.
      @param(RC what @code(srb_Probe) returned) }
    procedure ProbeDone(RC: Integer);
    { Ticks or unticks Weave without its OnClick, so neither the bridge nor
      the saved choice changes: for failed starts and loading settings.
      @param(Value whether it is ticked) }
    procedure SetWeaveQuietly(Value: Boolean);
    { After a failed start, once the current event is done: asks the user
      (a dialog centred on the window) whether to carry on without
      glasses-free 3D, try again or exit. The scene is drawn by the bridge, so
      there is no "anyway" choice.
      @param(Problem what went wrong)
      @param(Msg the details) }
    procedure AskAfterStartFailure(Problem: TSRStartProblem; const Msg: string);
    { Asks the user about the start problem in @link(FProblem) and
      @link(FProblemMsg): on @code(WM_SR_STARTPROBLEM), so not from inside the
      click or timer that started it. }
    procedure HandleStartProblem;
    { Handles the hidden window's messages: @code(WM_SR_STARTPROBLEM) and
      @code(WM_SR_PROBEDONE) (its @code(WPARAM) the check's result).
      @param(Msg the message) }
    procedure MsgWndProc(var Msg: TMessage);
    { Moves the window onto the SR display if it is elsewhere. }
    procedure PlaceOnSRDisplay;
    { Turns full screen on or off. @param(Value @true for full screen) }
    procedure SetFullScreen(Value: Boolean);
    { The application's idle handler: one frame per call while running.
      @param(Sender the application) @param(Done set to @false to be called
      again at once) }
    procedure AppIdle(Sender: TObject; var Done: Boolean);
    { Draws, weaves and presents one frame. }
    procedure Frame;
    { Decides whether the lens should be on, with a delay against flicker. }
    procedure UpdateLens;
    { Writes queued SR events to the log. }
    procedure PollEvents;
    { Writes a line to the log file and the log panel. @param(Msg the line) }
    procedure AddLog(const Msg: string);
    { The view size for a viewport, as the View box says.
      @param(W the viewport's width) @param(H its height)
      @returns(the size of each eye's view) }
    function ViewSizeFor(W, H: Integer): TSize;
  end;

var
  { The main window. }
  frmMainVCL: TfrmMainVCL;

implementation

{$R *.dfm}

uses
  Winapi.MultiMon, System.Math, System.StrUtils, System.IOUtils,
  SRDiagLog, SRSettingsDialog;

const
  { Most lines kept in the log panel. }
  MaxLogLines = 2000;
  { How long the lens must have wanted a change before it is made, ms. }
  LensSwitchDelayMs = 250;
  { The cubes' turning speed, radians a second: a turn in 8 s, as
    SRDemoFMX's. }
  TurnSpeed = 2 * Pi / 8;
  { The grid's turning speed, degrees a second: a turn in 20 s, the other
    way, as SRDemoFMX's. }
  GridSpinSpeed = -360 / 20;
  { How far the wheel moves the scene per notch, world units. }
  SceneStep = 1.0;
  { Furthest the scene can be pulled towards the viewer, world units. }
  SceneZMin = -20.0;
  { Furthest the scene can be pushed away, world units. }
  SceneZMax = 20.0;
  { Degrees the scene tilts or rolls per pixel of a left-button drag. }
  TiltPerPixel = 0.25;
  { Most the scene can tilt either way, degrees. }
  TiltMax = 85.0;
  { Most the scene can roll either way, degrees. }
  RollMax = 180.0;
  { The viewport's height on the glass in world units (FMX's camera 20
    units back at 45 degrees), for converting to mm. }
  WorldViewHeight = 16.5685;
  { Spheres each side of the main one, and their spacing, world units. }
  RowHalf = 5;
  { See @link(RowHalf). }
  RowStep = 3.0;
  { The bridge export SRDemoVCL needs: only in bridges that draw
    SRDemoFMX's scene (5 November 2026, 08:40 or later). }
  SceneExport = 'srb_SceneParamsSize';

procedure TfrmMainVCL.AddLog(const Msg: string);
begin
  DiagLog(Msg);
  if FLog = nil then
    Exit;
  FLog.Lines.BeginUpdate;
  try
    while FLog.Lines.Count >= MaxLogLines do
      FLog.Lines.Delete(0);
    FLog.Lines.Add(FormatDateTime('hh:nn:ss.zzz', Now) + '  ' + Msg);
  finally
    FLog.Lines.EndUpdate;
  end;
  SendMessage(FLog.Handle, EM_SCROLLCARET, 0, 0);
end;

function TfrmMainVCL.AddLabel(const Text: string): TLabel;
begin
  Result := TLabel.Create(Self);
  Result.Parent := FTop;
  Result.Caption := Text;
  Result.Align := alLeft;
  Result.Layout := tlCenter;
  Result.AlignWithMargins := True;
  Result.Margins.SetBounds(8, 0, 2, 0);
  Result.Left := 10000;   // after what is already there
end;

procedure TfrmMainVCL.BuildControls;
var
  Btn: TButton;

  { Places a control at the right-hand end of the toolbar.
    @param(C the control) @param(Width its width) }
  procedure Dock(C: TControl; Width: Integer);
  begin
    C.Parent := FTop;
    C.Align := alLeft;
    C.AlignWithMargins := True;
    C.Margins.SetBounds(4, 6, 4, 6);
    C.Width := Width;
    C.Left := 10000;
  end;

begin
  FTop := TPanel.Create(Self);
  FTop.Parent := Self;
  FTop.Align := alTop;
  FTop.Height := 40;
  FTop.BevelOuter := bvNone;
  FTop.Caption := '';

  FLog := TMemo.Create(Self);
  FLog.Parent := Self;
  FLog.Align := alBottom;
  FLog.Height := 150;
  FLog.ReadOnly := True;
  FLog.ScrollBars := ssVertical;
  FLog.WordWrap := False;
  FLog.Font.Name := 'Consolas';

  FStatus := TStatusBar.Create(Self);
  FStatus.Parent := Self;
  FStatus.SimplePanel := True;
  FStatus.Top := ClientHeight + 1000;   // below the log

  FViewport := TPanel.Create(Self);
  FViewport.Parent := Self;
  FViewport.Align := alClient;
  FViewport.BevelOuter := bvNone;
  FViewport.Caption := 'Starting LeiaSR...';
  FViewport.ParentBackground := False;
  FViewport.Color := $00100808;
  FViewport.Font.Color := $00C0C0C0;
  FViewport.OnMouseDown := ViewportMouseDown;
  FViewport.OnMouseMove := ViewportMouseMove;
  FViewport.OnMouseUp := ViewportMouseUp;
  OnMouseWheel := FormMouseWheel;

  FWeave := TCheckBox.Create(Self);
  Dock(FWeave, 70);
  FWeave.Caption := 'Weave';
  FWeave.Checked := True;
  FWeave.OnClick := WeaveClicked;

  AddLabel('Show');
  FShow := TComboBox.Create(Self);
  Dock(FShow, 170);
  FShow.Style := csDropDownList;
  FShow.OnChange := ControlChanged;

  FRotate := TCheckBox.Create(Self);
  Dock(FRotate, 70);
  FRotate.Caption := 'Rotate';
  FRotate.Checked := True;
  FRotate.OnClick := ControlChanged;

  FLookAround := TCheckBox.Create(Self);
  Dock(FLookAround, 100);
  FLookAround.Caption := 'Look-around';
  FLookAround.OnClick := ControlChanged;

  Btn := TButton.Create(Self);
  Dock(Btn, 90);
  Btn.Caption := 'Settings...';
  Btn.OnClick := SettingsClick;

  AddLabel('Views');
  FViewSize := TComboBox.Create(Self);
  Dock(FViewSize, 120);
  FViewSize.Style := csDropDownList;
  FViewSize.Items.Add('Viewport size');
  FViewSize.Items.Add('Half size');
  FViewSize.ItemIndex := 0;
  FViewSize.OnChange := ControlChanged;

  AddLabel('Lens');
  FLens := TComboBox.Create(Self);
  Dock(FLens, 150);
  FLens.Style := csDropDownList;
  FLens.Items.Add('Off over controls');
  FLens.Items.Add('Always on');
  FLens.Items.Add('Always off');
  FLens.ItemIndex := 0;
  FLens.OnChange := ControlChanged;

  AddLabel('F11 full screen');
end;

procedure TfrmMainVCL.FindImages;
var
  Dir, Media, F: string;
  Level: Integer;
begin
  Dir := ExtractFileDir(ParamStr(0));
  Media := '';
  for Level := 0 to 4 do
  begin
    if TDirectory.Exists(TPath.Combine(Dir, 'media')) then
    begin
      Media := TPath.Combine(Dir, 'media');
      Break;
    end;
    Dir := ExtractFileDir(Dir);
  end;
  FShow.Items.Clear;
  FShow.Items.Add('3D scene');
  FShow.Items.Add('Test pattern');
  if Media <> '' then
  begin
    for F in TDirectory.GetFiles(Media) do
      if MatchText(ExtractFileExt(F), ['.png', '.jpg', '.jpeg', '.bmp']) then
        FImageFiles.Add(F);
    FImageFiles.Sort;
    for F in FImageFiles do
      FShow.Items.Add(ExtractFileName(F));
    AddLog(Format('%d stereo image(s) in %s', [FImageFiles.Count, Media]));
  end
  else
    AddLog('No media folder found above the executable');
  FShow.ItemIndex := 0;
end;

procedure TfrmMainVCL.LoadShownImage;
begin
  FImageDirty := True;
  try
    if FShow.ItemIndex = 1 then
      FImage.MakeTestPattern(1920, 1080)
    else if FShow.ItemIndex >= 2 then
      FImage.LoadFromFile(FImageFiles[FShow.ItemIndex - 2]);
    if FShow.ItemIndex >= 1 then
      AddLog(Format('Showing %s, %d x %d', [FImage.Name, FImage.SourceWidth, FImage.SourceHeight]))
    else
      AddLog('Showing the 3D scene');
  except
    on E: Exception do
    begin
      AddLog('Could not load the image: ' + E.Message + '; showing the 3D scene');
      FShow.ItemIndex := 0;
    end;
  end;
end;

procedure TfrmMainVCL.SettingsToControls;
var
  I: Integer;
begin
  FLoading := True;
  try
    FLookAround.Checked := FSettings.LookAround;
    FLens.ItemIndex := EnsureRange(FSettings.LensMode, 0, FLens.Items.Count - 1);
    SetWeaveQuietly(FSettings.UseGlassesFree3D);   // the click would start the bridge now
    if FSettings.StereoImage <> '' then
    begin
      I := FShow.Items.IndexOf(FSettings.StereoImage);
      if I >= 0 then
        FShow.ItemIndex := I;
    end;
  finally
    FLoading := False;
  end;
  ControlChanged(nil);
end;

procedure TfrmMainVCL.SaveSettings;
begin
  if FLoading or (FSettings = nil) then
    Exit;
  FSettings.LookAround := FLookAround.Checked;
  FSettings.EyeSeparationScale := 1;   // the real eye separation; the Depth slider is gone
  FSettings.LensMode := FLens.ItemIndex;
  if FShow.ItemIndex >= 2 then
    FSettings.StereoImage := FShow.Text
  else
    FSettings.StereoImage := '';
  FSettings.FullScreen := FFullScreen;
  try
    FSettings.Save;
  except
    on E: Exception do
      AddLog('Settings not saved: ' + E.Message);
  end;
end;

procedure TfrmMainVCL.ControlChanged(Sender: TObject);
begin
  if Sender = FShow then
    LoadShownImage;
  if Sender = FViewSize then
    FImageDirty := True;
  if (Sender <> nil) and not FLoading then
  begin
    AddLog(Format('Settings: show %s, rotate %s, look-around %s, eyes %s, views %s, lens %s',
      [FShow.Text, BoolToStr(FRotate.Checked, True), BoolToStr(FLookAround.Checked, True),
       IfThen(FSettings.EyeSeparationMM = 0, 'tracked', Format('%.0f mm', [FSettings.EyeSeparationMM])),
       FViewSize.Text, FLens.Text]));
    SaveSettings;
  end;
end;

procedure TfrmMainVCL.FormCreate(Sender: TObject);
begin
  FMsgWnd := System.Classes.AllocateHWnd(MsgWndProc);
  FClock := TStopwatch.StartNew;
  FImageFiles := TStringList.Create;
  FImage := TSRStereoImage.Create;
  FLensWantSinceMs := -1;
  FLastFps := -1;
  BuildControls;
  AddLog('SRDemoVCL: the 3D scene is drawn by the bridge on the GPU; nothing is read back');
  FindImages;
  FSettings := TSRSettings.Create;
  try
    if FSettings.Load then
      AddLog('Settings loaded from ' + TSRSettings.SettingsFileName);
  except
    on E: Exception do
      AddLog('Settings not loaded: ' + E.Message);
  end;
  SettingsToControls;
  LoadShownImage;
  if not SRRuntimeInstalled then
  begin
    // As if the program had no SR support: nothing to start, nothing said
    AddLog('LeiaSR runtime not installed: Weave hidden, LeiaSR not started');
    SetWeaveQuietly(False);
    FWeave.Visible := False;
  end
  else if not FWeave.Checked then
  begin
    AddLog('Glasses-free 3D is off in the settings (useGlassesFree3D false): LeiaSR not started');
    FViewport.Caption := 'Glasses-free 3D off: tick Weave to use it';
  end;
  FStartTimer := TTimer.Create(Self);
  FStartTimer.Enabled := False;
  FStartTimer.Interval := 100;
  FStartTimer.OnTimer := StartTimerFired;
end;

procedure TfrmMainVCL.FormDestroy(Sender: TObject);
begin
  if FMsgWnd <> 0 then
    System.Classes.DeallocateHWnd(FMsgWnd);
  FMsgWnd := 0;
  Application.OnIdle := nil;
  StopBridge;
  FreeAndNil(FSettings);
  FreeAndNil(FImage);
  FreeAndNil(FImageFiles);
end;

procedure TfrmMainVCL.FormShow(Sender: TObject);
begin
  FStartTimer.Enabled := True;
end;

procedure TfrmMainVCL.StartTimerFired(Sender: TObject);
begin
  FStartTimer.Enabled := False;
  if FWeave.Checked and not FRunning then
    StartBridge;
end;

procedure TfrmMainVCL.WeaveClicked(Sender: TObject);
begin
  if (FSettings <> nil) and (FSettings.UseGlassesFree3D <> FWeave.Checked) then
  begin
    // The user's choice, kept for the next start
    FSettings.UseGlassesFree3D := FWeave.Checked;
    try
      FSettings.Save;
    except
      on E: Exception do
        AddLog('Settings not saved: ' + E.Message);
    end;
  end;
  if FWeave.Checked then
    StartBridge
  else
  begin
    StopBridge;
    FViewport.Caption := 'Weaving off';
  end;
end;

procedure TfrmMainVCL.StartBridge;
var
  RC: Integer;
  R: TSRBRect;
  Info: TSRBDisplayInfo;
  Gpus: TSRBGpuCheck;
begin
  if FRunning then
    Exit;
  if not SRBridgeAvailable then
  begin
    AddLog('Bridge not available: ' + SRBridgeLastError);
    SetWeaveQuietly(False);
    FViewport.Caption := SRBridgeLastError;
    AskAfterStartFailure(spBridgeMissing, SRBridgeLastError);
    Exit;
  end;
  DiagLogAttachBridge;
  if not SRBridgeHasExport(SceneExport) or (srb_SceneParamsSize <> SizeOf(TSRBSceneParams)) then
  begin
    AddLog('This SRBridge.dll is too old: it draws the old scene, not SRDemoFMX''s. Rebuild the ' +
      'bridge (5 November 2026, 08:40 or later)');
    SetWeaveQuietly(False);
    FViewport.Caption := 'SRBridge.dll is too old: rebuild the bridge';
    AskAfterStartFailure(spBridgeMissing, 'This SRBridge.dll is too old (it has no ' + SceneExport +
      '): rebuild the bridge.');
    Exit;
  end;
  // The wait for SR (a service starting, a display) happens on a background
  // thread, so the window keeps working; the scene comes on when it answers
  if SRBridgeHasExport('srb_Probe') and not FProbeOK then
  begin
    if not FProbing then
      StartProbe;
    Exit;
  end;
  FProbeOK := False;   // used up: the next start checks again
  srb_SetVSync(1);
  AddLog('Starting LeiaSR (timeout 5 s)');
  RC := srb_Initialize(Pointer(FViewport.Handle), 5.0);
  if RC <> SRB_OK then
  begin
    AddLog(Format('LeiaSR initialisation failed (%d): %s', [RC, SRBridgeLastError]));
    SetWeaveQuietly(False);
    FViewport.Caption := 'LeiaSR initialisation failed: ' + SRBridgeLastError;
    AskAfterStartFailure(spStartFailed, SRBridgeLastError);
    Exit;
  end;
  FRunning := True;
  FViewport.Caption := '';
  if FSettings.LatencyFrames > 0 then
    srb_SetLatencyInFrames(FSettings.LatencyFrames);
  AddLog('SR platform ' + UTF8ToString(srb_GetPlatformVersion));
  if srb_GetDisplayInfo(@Info) = SRB_OK then
    AddLog(Format('SR display %d x %d px, %.1f x %.1f mm, recommended views %d x %d',
      [Info.resolutionWidth, Info.resolutionHeight, Info.physicalWidthMM, Info.physicalHeightMM,
       Info.recommendedViewWidth, Info.recommendedViewHeight]));
  FSRRectKnown := srb_GetDisplayRect(R) = SRB_OK;
  if FSRRectKnown then
    FSRRect := Rect(R[0], R[1], R[2], R[3]);
  if SRBridgeHasExport('srb_GetGpuCheck') then
  begin
    FillChar(Gpus, SizeOf(Gpus), 0);
    srb_GetGpuCheck(@Gpus);
    AddLog(Format('GPUs: the bridge draws on %s; the SR display is driven by %s (%d Hz)%s',
      [UTF8ToString(PAnsiChar(@Gpus.bridgeAdapter[0])), UTF8ToString(PAnsiChar(@Gpus.srDisplayAdapter[0])),
       Gpus.srRefreshHz, IfThen(Gpus.bridgeOnSRAdapter = 0, ' - NOT the same GPU: stereo will be slow', '')]));
  end;
  FLensOn := True;
  srb_SetLens(1);
  FBounds := TSize.Create(0, 0);
  FImageDirty := True;
  FPrevFrameMs := FClock.ElapsedMilliseconds;
  FLastStatusMs := FPrevFrameMs;
  FLastSummaryMs := FPrevFrameMs;
  PlaceOnSRDisplay;
  if FSettings.FullScreen and not FFullScreen then
    SetFullScreen(True);
  Application.OnIdle := AppIdle;
end;

const
  { Posted to the hidden window: ask about the start problem. }
  WM_SR_STARTPROBLEM = WM_APP + 1;
  { Posted to the hidden window by the background check, its result in
    @code(WPARAM). }
  WM_SR_PROBEDONE = WM_APP + 2;

procedure TfrmMainVCL.AskAfterStartFailure(Problem: TSRStartProblem; const Msg: string);
begin
  AddLog('Start problem (' + StartProblemName(Problem) + '): asking the user');
  FProblem := Problem;
  FProblemMsg := Msg;
  // Not from inside the click or timer that started it
  if (FMsgWnd = 0) or not PostMessage(FMsgWnd, WM_SR_STARTPROBLEM, 0, 0) then
    HandleStartProblem;
end;

procedure TfrmMainVCL.HandleStartProblem;
var
  Fix: Boolean;
begin
  if FRunning then
    Exit;
  case AskStartProblem(Handle, 'SRDemoVCL', FProblem, FProblemMsg, False, '', Fix) of
    scRetry:
      begin
        AddLog('Start problem: the user chose to try again');
        if FWeave.Checked then
          StartBridge
        else
          FWeave.Checked := True;   // its OnClick starts the bridge
      end;
    scExit:
      begin
        AddLog('Start problem: the user chose to exit, to fix the SR set-up');
        Close;
      end;
  else
    AddLog('Start problem: the user chose to carry on without glasses-free 3D');
  end;
end;

procedure TfrmMainVCL.MsgWndProc(var Msg: TMessage);
begin
  case Msg.Msg of
    WM_SR_STARTPROBLEM:
      HandleStartProblem;
    WM_SR_PROBEDONE:
      ProbeDone(Integer(Msg.WParam));
  else
    Msg.Result := DefWindowProc(FMsgWnd, Msg.Msg, Msg.WParam, Msg.LParam);
  end;
end;

procedure TfrmMainVCL.StartProbe;
var
  Wnd: HWND;
begin
  Wnd := FMsgWnd;
  FProbing := True;
  FProbeStartMs := FClock.ElapsedMilliseconds;
  FViewport.Caption := 'Checking for LeiaSR...';
  AddLog('Checking for LeiaSR on a background thread (up to 5 s)');
  TThread.CreateAnonymousThread(
    procedure
    begin
      // Dropped if the window has gone by then
      PostMessage(Wnd, WM_SR_PROBEDONE, WPARAM(srb_Probe(5000)), 0);
    end).Start;
end;

procedure TfrmMainVCL.ProbeDone(RC: Integer);
begin
  FProbing := False;
  AddLog(Format('LeiaSR background check: %d after %d ms%s', [RC, FClock.ElapsedMilliseconds - FProbeStartMs,
    IfThen(RC = SRB_OK, ' (service running, display found)', ': ' + SRBridgeLastError)]));
  if FRunning or not FWeave.Checked then
  begin
    AddLog('LeiaSR background check: no longer wanted (Weave unticked meanwhile)');
    FViewport.Caption := 'Weaving off';
    Exit;
  end;
  if RC = SRB_OK then
  begin
    FProbeOK := True;
    StartBridge;   // now quick: SR is there and its DLLs are loaded
    Exit;
  end;
  SetWeaveQuietly(False);
  FViewport.Caption := 'Glasses-free 3D could not be started: ' + SRBridgeLastError;
  case RC of
    SRB_E_NO_SERVICE: AskAfterStartFailure(spNoService, 'The LeiaSR (Simulated Reality) service ' +
      'is not running. It normally starts with Windows: restarting the SR software, or the ' +
      'computer, starts it again.');
    SRB_E_NO_DISPLAY: AskAfterStartFailure(spNoDisplay, 'No SR display was found. Check that it ' +
      'is switched on and connected (video cable and USB), and set to its native resolution.');
  else
    AskAfterStartFailure(spStartFailed, SRBridgeLastError);
  end;
end;

procedure TfrmMainVCL.SetWeaveQuietly(Value: Boolean);
begin
  FWeave.OnClick := nil;
  try
    FWeave.Checked := Value;
  finally
    FWeave.OnClick := WeaveClicked;
  end;
end;

procedure TfrmMainVCL.StopBridge;
begin
  if not FRunning then
    Exit;
  Application.OnIdle := nil;
  AddLog('Stopping LeiaSR');
  srb_Finalize;
  FRunning := False;
end;

procedure TfrmMainVCL.PlaceOnSRDisplay;
var
  WR: TRect;
  W, H: Integer;
begin
  if not FSRRectKnown then
    Exit;
  GetWindowRect(Handle, WR);
  if FSRRect.Contains(WR.CenterPoint) then
  begin
    AddLog('The window is on the SR display');
    Exit;
  end;
  W := (FSRRect.Width * 3) div 4;
  H := (FSRRect.Height * 3) div 4;
  SetWindowPos(Handle, 0, FSRRect.Left + (FSRRect.Width - W) div 2,
    FSRRect.Top + (FSRRect.Height - H) div 2, W, H, SWP_NOZORDER or SWP_NOACTIVATE);
  GetWindowRect(Handle, WR);
  AddLog(Format('Moved the window onto the SR display: (%d, %d) %d x %d',
    [WR.Left, WR.Top, WR.Width, WR.Height]));
end;

procedure TfrmMainVCL.SetFullScreen(Value: Boolean);
var
  Style: NativeInt;
  MI: TMonitorInfo;
  Target, WR: TRect;
begin
  if Value = FFullScreen then
    Exit;
  Style := GetWindowLongPtr(Handle, GWL_STYLE);
  if Value then
  begin
    // As Leia's samples (Raymond Chen's method), on the SR display
    FPlacement.length := SizeOf(FPlacement);
    GetWindowPlacement(Handle, @FPlacement);
    if FSRRectKnown then
      Target := FSRRect
    else
    begin
      MI.cbSize := SizeOf(MI);
      GetMonitorInfo(MonitorFromWindow(Handle, MONITOR_DEFAULTTONEAREST), @MI);
      Target := MI.rcMonitor;
    end;
    FTop.Visible := False;
    FLog.Visible := False;
    FStatus.Visible := False;
    SetWindowLongPtr(Handle, GWL_STYLE, Style and not NativeInt(WS_OVERLAPPEDWINDOW or WS_MAXIMIZE));
    SetWindowPos(Handle, HWND_TOP, Target.Left, Target.Top, Target.Width, Target.Height,
      SWP_NOOWNERZORDER or SWP_FRAMECHANGED);
    FFullScreen := True;
    GetWindowRect(Handle, WR);
    AddLog(Format('Full screen on: wanted (%d, %d) %d x %d, window (%d, %d) %d x %d',
      [Target.Left, Target.Top, Target.Width, Target.Height, WR.Left, WR.Top, WR.Width, WR.Height]));
  end
  else
  begin
    SetWindowLongPtr(Handle, GWL_STYLE, Style or NativeInt(WS_OVERLAPPEDWINDOW));
    SetWindowPlacement(Handle, @FPlacement);
    SetWindowPos(Handle, 0, 0, 0, 0, 0, SWP_NOMOVE or SWP_NOSIZE or SWP_NOZORDER or
      SWP_NOOWNERZORDER or SWP_FRAMECHANGED);
    FTop.Visible := True;
    FLog.Visible := True;
    FStatus.Visible := True;
    FStatus.Top := ClientHeight + 1000;   // below the log
    FFullScreen := False;
    GetWindowRect(Handle, WR);
    AddLog(Format('Full screen off: window (%d, %d) %d x %d', [WR.Left, WR.Top, WR.Width, WR.Height]));
  end;
  SaveSettings;
end;

procedure TfrmMainVCL.FormKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  case Key of
    VK_F11:
      SetFullScreen(not FFullScreen);
    VK_ESCAPE:
      if FFullScreen then
        SetFullScreen(False)
      else
        Exit;
    VK_PRIOR:
      MoveScene(SceneStep, False);
    VK_NEXT:
      MoveScene(-SceneStep, False);
    VK_HOME:
      MoveScene(0, True);
    Ord('R'):
      begin
        FGridSpinning := not FGridSpinning;
        AddLog(Format('Grid spin about the vertical axis %s (R), at %.0f degrees',
          [IfThen(FGridSpinning, 'started', 'stopped'), FGridSpin]));
      end;
  else
    Exit;
  end;
  Key := 0;
end;

procedure TfrmMainVCL.SettingsClick(Sender: TObject);
var
  MM: Integer;
begin
  MM := Round(FSettings.EyeSeparationMM);
  // The lens off while the dialog is up, so it can be read
  if FRunning then
    srb_SetLens(0);
  try
    if not AskEyeSeparation(Handle, 'SRDemoVCL', MM) then
      Exit;
  finally
    if FRunning then
      srb_SetLens(Ord(FLensOn));
  end;
  FSettings.EyeSeparationMM := MM;
  AddLog(IfThen(MM = 0, 'Eye separation: as tracked', Format('Eye separation: %d mm', [MM])));
  SaveSettings;
end;

procedure TfrmMainVCL.FormMouseWheel(Sender: TObject; Shift: TShiftState; WheelDelta: Integer;
  MousePos: TPoint; var Handled: Boolean);
var
  Step: Single;
begin
  // A list under the pointer keeps its own wheel
  if (ActiveControl is TComboBox) and TComboBox(ActiveControl).DroppedDown then
    Exit;
  Step := SceneStep;
  if ssShift in Shift then
    Step := Step * 0.25;
  MoveScene(Step * WheelDelta / 120, False);
  Handled := True;
end;

procedure TfrmMainVCL.ViewportMouseDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState;
  X, Y: Integer);
begin
  if Button <> mbLeft then
    Exit;
  FTilting := True;
  FTiltStartX := X;
  FTiltStartY := Y;
  FTiltStartAngle := FSceneTilt;
  FRollStartAngle := FSceneRoll;
end;

procedure TfrmMainVCL.ViewportMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Integer);
begin
  if not FTilting then
    Exit;
  // Up tilts the far side down, as when the viewer stands up; right rolls
  // the scene clockwise (as SRDemoFMX)
  FSceneTilt := EnsureRange(FTiltStartAngle + (FTiltStartY - Y) * TiltPerPixel, -TiltMax, TiltMax);
  FSceneRoll := EnsureRange(FRollStartAngle + (X - FTiltStartX) * TiltPerPixel, -RollMax, RollMax);
end;

procedure TfrmMainVCL.ViewportMouseUp(Sender: TObject; Button: TMouseButton; Shift: TShiftState;
  X, Y: Integer);
begin
  if (Button <> mbLeft) or not FTilting then
    Exit;
  FTilting := False;
  AddLog(Format('Scene tilted %.1f and rolled %.1f degrees about the main sphere (left-drag; Home ' +
    'levels it)', [FSceneTilt, FSceneRoll]) + IfThen(DepthText = '', '', ': ' + DepthText));
end;

procedure TfrmMainVCL.MoveScene(Delta: Single; Reset: Boolean);
begin
  if Reset then
  begin
    FSceneZ := 0;
    FSceneTilt := 0;
    FSceneRoll := 0;
    AddLog('Scene back as built: depth, tilt and roll 0');
    Exit;
  end;
  FSceneZ := EnsureRange(FSceneZ + Delta, SceneZMin, SceneZMax);
  AddLog(Format('Scene moved to Z %.2f world units', [FSceneZ]) +
    IfThen(DepthText = '', '', ': ' + DepthText));
end;

function TfrmMainVCL.DepthText: string;
var
  U, Z, ZRot, A, T: Double;
  J: Integer;
  Parts: string;
begin
  Result := '';
  if FLastInfo.windowHeight <= 0 then
    Exit;
  // mm per world unit, as the bridge draws it
  U := FLastInfo.windowHeight / WorldViewHeight;
  A := DegToRad(FGridSpin);
  T := DegToRad(FSceneTilt);
  Parts := '';
  // The middle column (x 0) from the main sphere to the nearest: turned
  // with the grid, then tilted (the roll leaves depth alone), then moved
  for J := 0 downto -RowHalf do
  begin
    Z := J * RowStep;
    ZRot := Z * Cos(A) * Cos(T) + FSceneZ;
    if Parts <> '' then
      Parts := Parts + ' ';
    Parts := Parts + Format('%.0f', [-ZRot * U]);
  end;
  Z := RowHalf * RowStep;
  Result := Format('depths %s mm in front of the glass (green to red), furthest blue %.0f mm behind, ' +
    'scene Z %.2f, tilt %.0f, roll %.0f deg', [Parts, (Z * Cos(A) * Cos(T) + FSceneZ) * U, FSceneZ,
    FSceneTilt, FSceneRoll]);
end;

function TfrmMainVCL.ViewSizeFor(W, H: Integer): TSize;
begin
  if FViewSize.ItemIndex = 1 then
    Result := TSize.Create(Max(1, W div 2), Max(1, H div 2))
  else
    Result := TSize.Create(W, H);
end;

procedure TfrmMainVCL.UpdateLens;
var
  Want: Boolean;
  P: TPoint;
  VR: TRect;
  NowMs: Int64;
begin
  case TLensChoice(FLens.ItemIndex) of
    lcAlwaysOn: Want := True;
    lcAlwaysOff: Want := False;
  else
    if FFullScreen then
      Want := True
    else
    begin
      GetCursorPos(P);
      VR := FViewport.ClientRect;
      VR.TopLeft := FViewport.ClientToScreen(VR.TopLeft);
      VR.BottomRight := FViewport.ClientToScreen(VR.BottomRight);
      // Off the SR display the lens does not matter: leave it on
      Want := VR.Contains(P) or (FSRRectKnown and not FSRRect.Contains(P));
      if (GetKeyState(VK_LBUTTON) < 0) or (GetKeyState(VK_RBUTTON) < 0) then
        Want := FLensOn;   // no change while a button is held
    end;
  end;
  NowMs := FClock.ElapsedMilliseconds;
  if Want = FLensOn then
  begin
    FLensWantSinceMs := -1;
    Exit;
  end;
  if FLensWantSinceMs < 0 then
    FLensWantSinceMs := NowMs;
  if (NowMs - FLensWantSinceMs >= LensSwitchDelayMs) or (FLens.ItemIndex <> Ord(lcOffOverControls)) then
  begin
    FLensOn := Want;
    FLensWantSinceMs := -1;
    srb_SetLens(Ord(Want));
    AddLog(IfThen(Want, 'Lens ON', 'Lens OFF: drawn flat'));
  end;
end;

procedure TfrmMainVCL.PollEvents;
var
  Ev: TSRBSystemEvent;
begin
  while srb_PollSystemEvent(@Ev) = 1 do
    if (Ev.eventType <> 16) and (Ev.eventType <> 17) then   // not user found / lost
      AddLog(Format('SR event %d: %s', [Int64(Ev.eventType), UTF8ToString(PAnsiChar(@Ev.message[0]))]));
end;

procedure TfrmMainVCL.Frame;
var
  W, H, RC: Integer;
  V: TSize;
  P: TSRBSceneParams;
  Info: TSRBSceneInfo;
  NowMs, Dt: Int64;
  Stats: TSRBStats;
  Secs: Double;
begin
  NowMs := FClock.ElapsedMilliseconds;
  Dt := NowMs - FPrevFrameMs;
  FPrevFrameMs := NowMs;
  FWorstFrameMs := Max(FWorstFrameMs, Dt);

  W := FViewport.ClientWidth;
  H := FViewport.ClientHeight;
  if IsIconic(Handle) or (W < 1) or (H < 1) then
  begin
    Sleep(20);
    Exit;
  end;
  if (W <> FBounds.cx) or (H <> FBounds.cy) then
  begin
    srb_SetBounds(0, 0, W, H);
    AddLog(Format('Viewport %d x %d physical pixels', [W, H]));
    FBounds := TSize.Create(W, H);
    FImageDirty := True;
  end;
  UpdateLens;
  V := ViewSizeFor(W, H);

  if FShow.ItemIndex >= 1 then
  begin
    if FImageDirty or (V <> FImageViewSize) then
    begin
      FImage.RenderViews(V.cx, V.cy, FImagePixels);
      FImageViewSize := V;
      FImageDirty := False;
    end;
    RC := srb_SubmitViews(@FImagePixels[0], V.cx, V.cy, V.cx * 8, SRB_FMT_BGRA8);
  end
  else
  begin
    if FRotate.Checked then
      FRotation := FRotation + TurnSpeed * Dt / 1000;
    if FGridSpinning then
      FGridSpin := FMod(FGridSpin + GridSpinSpeed * Dt / 1000, 360);
    FillChar(P, SizeOf(P), 0);
    P.viewWidth := V.cx;
    P.viewHeight := V.cy;
    P.rotation := FRotation;
    P.eyeSeparationMM := FSettings.EyeSeparationMM;
    P.depthScale := 1;
    P.lookAround := Ord(FLookAround.Checked);
    P.flat := Ord(not FLensOn);
    P.fps := FLastFps;
    P.sceneZ := FSceneZ;
    P.tiltDeg := FSceneTilt;
    P.rollDeg := FSceneRoll;
    P.gridSpinDeg := FGridSpin;
    RC := srb_RenderScene(@P, @Info);
    if RC >= 0 then
      FLastInfo := Info;
  end;
  if RC < 0 then
    AddLog(Format('Frame failed (%d): %s', [RC, SRBridgeLastError]))
  else if RC = SRB_S_OCCLUDED then
    Sleep(10);
  Inc(FFrames);
  PollEvents;

  if NowMs - FLastStatusMs >= 1000 then
  begin
    Secs := (NowMs - FLastStatusMs) / 1000;
    FLastFps := Round(FFrames / Secs);
    FStatus.SimpleText := Format('%.0f fps   views %d x %d   eyes L(%.0f, %.0f, %.0f) R(%.0f, %.0f, %.0f) mm%s%s   %s   %s',
      [FFrames / Secs, V.cx, V.cy,
       FLastInfo.leftEye[0], FLastInfo.leftEye[1], FLastInfo.leftEye[2],
       FLastInfo.rightEye[0], FLastInfo.rightEye[1], FLastInfo.rightEye[2],
       IfThen(FLastInfo.nominalEyes <> 0, '  (no eyes yet)', ''),
       IfThen(FLastInfo.separationRebuilt <> 0, '  (63 mm used)', ''),
       IfThen(FLensOn, 'lens on', 'lens off'), DepthText]);
    FLastStatusMs := NowMs;
    if NowMs - FLastSummaryMs >= 5000 then
    begin
      FillChar(Stats, SizeOf(Stats), 0);
      srb_GetStats(@Stats);
      DiagLog(Format('%.0f fps, worst frame %d ms, views %d x %d, %s; woven %d, 2D %d; window %.0f x %.0f mm at (%.0f, %.0f); ' +
        'eyes L(%.0f, %.0f, %.0f) R(%.0f, %.0f, %.0f)%s',
        [FFrames / Secs, FWorstFrameMs, V.cx, V.cy, IfThen(FFullScreen, 'FULL SCREEN', 'windowed'),
         Int64(Stats.framesWoven), Int64(Stats.frames2D),
         FLastInfo.windowWidth, FLastInfo.windowHeight, FLastInfo.windowCenterX, FLastInfo.windowCenterY,
         FLastInfo.leftEye[0], FLastInfo.leftEye[1], FLastInfo.leftEye[2],
         FLastInfo.rightEye[0], FLastInfo.rightEye[1], FLastInfo.rightEye[2],
         IfThen(FLensOn, '', ' LENS-OFF')]));
      FLastSummaryMs := NowMs;
      FWorstFrameMs := 0;
    end;
    FFrames := 0;
  end;
end;

procedure TfrmMainVCL.AppIdle(Sender: TObject; var Done: Boolean);
begin
  if not FRunning then
    Exit;
  Frame;
  Done := False;
end;

end.

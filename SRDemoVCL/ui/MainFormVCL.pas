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
  Vcl.ComCtrls, SRSettings, SRStereoImage, SRBridge.Api;

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
    { F11 toggles full screen; Esc leaves it. }
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
    { What to show: the 3D scene, the test pattern or an image. }
    FShow: TComboBox;
    { Turn the cube. }
    FRotate: TCheckBox;
    { Look-around on, or a fixed viewer. }
    FLookAround: TCheckBox;
    { Depth: the eye separation scale, 10 to 150 percent. }
    FDepth: TTrackBar;
    { Shows the depth value. }
    FDepthLabel: TLabel;
    { Eye separation, 0 (tracked) to 80 mm. }
    FSeparation: TTrackBar;
    { Shows the separation value. }
    FSeparationLabel: TLabel;
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
  SRDiagLog;

const
  { Most lines kept in the log panel. }
  MaxLogLines = 2000;
  { How long the lens must have wanted a change before it is made, ms. }
  LensSwitchDelayMs = 250;
  { The cube's turning speed, radians a second. }
  TurnSpeed = 0.6;
  { The bridge export SRDemoVCL needs. }
  SceneExport = 'srb_RenderScene';

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

  FDepthLabel := AddLabel('Depth 100%');
  FDepth := TTrackBar.Create(Self);
  Dock(FDepth, 140);
  FDepth.Min := 10;
  FDepth.Max := 150;
  FDepth.Frequency := 10;
  FDepth.Position := 100;
  FDepth.OnChange := ControlChanged;

  FSeparationLabel := AddLabel('Eyes 63 mm');
  FSeparation := TTrackBar.Create(Self);
  Dock(FSeparation, 140);
  FSeparation.Min := 0;
  FSeparation.Max := 80;
  FSeparation.Frequency := 10;
  FSeparation.Position := 63;
  FSeparation.OnChange := ControlChanged;

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
    FDepth.Position := EnsureRange(Round(FSettings.EyeSeparationScale * 100), FDepth.Min, FDepth.Max);
    FSeparation.Position := EnsureRange(Round(FSettings.EyeSeparationMM), 0, FSeparation.Max);
    FLens.ItemIndex := EnsureRange(FSettings.LensMode, 0, FLens.Items.Count - 1);
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
  FSettings.EyeSeparationScale := FDepth.Position / 100;
  FSettings.EyeSeparationMM := FSeparation.Position;
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
  FDepthLabel.Caption := Format('Depth %d%%', [FDepth.Position]);
  if FSeparation.Position = 0 then
    FSeparationLabel.Caption := 'Eyes tracked'
  else
    FSeparationLabel.Caption := Format('Eyes %d mm', [FSeparation.Position]);
  if Sender = FShow then
    LoadShownImage;
  if Sender = FViewSize then
    FImageDirty := True;
  if (Sender <> nil) and not FLoading then
  begin
    AddLog(Format('Settings: show %s, rotate %s, look-around %s, depth %d%%, eyes %s, views %s, lens %s',
      [FShow.Text, BoolToStr(FRotate.Checked, True), BoolToStr(FLookAround.Checked, True),
       FDepth.Position, IfThen(FSeparation.Position = 0, 'tracked', IntToStr(FSeparation.Position) + ' mm'),
       FViewSize.Text, FLens.Text]));
    SaveSettings;
  end;
end;

procedure TfrmMainVCL.FormCreate(Sender: TObject);
begin
  FClock := TStopwatch.StartNew;
  FImageFiles := TStringList.Create;
  FImage := TSRStereoImage.Create;
  FLensWantSinceMs := -1;
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
  FStartTimer := TTimer.Create(Self);
  FStartTimer.Enabled := False;
  FStartTimer.Interval := 100;
  FStartTimer.OnTimer := StartTimerFired;
end;

procedure TfrmMainVCL.FormDestroy(Sender: TObject);
begin
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
begin
  if FRunning then
    Exit;
  if not SRBridgeAvailable then
  begin
    AddLog('Bridge not available: ' + SRBridgeLastError);
    FViewport.Caption := SRBridgeLastError;
    FWeave.Checked := False;
    Exit;
  end;
  DiagLogAttachBridge;
  if not SRBridgeHasExport(SceneExport) then
  begin
    AddLog('This SRBridge.dll has no srb_RenderScene: rebuild the bridge (5 November 2026, ' +
      '03:30 or later)');
    FViewport.Caption := 'SRBridge.dll is too old: rebuild the bridge';
    FWeave.Checked := False;
    Exit;
  end;
  srb_SetVSync(1);
  AddLog('Starting LeiaSR (timeout 5 s)');
  RC := srb_Initialize(Pointer(FViewport.Handle), 5.0);
  if RC <> SRB_OK then
  begin
    AddLog(Format('LeiaSR initialisation failed (%d): %s', [RC, SRBridgeLastError]));
    FViewport.Caption := 'LeiaSR initialisation failed: ' + SRBridgeLastError;
    FWeave.Checked := False;
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
  if Key = VK_F11 then
  begin
    SetFullScreen(not FFullScreen);
    Key := 0;
  end
  else if (Key = VK_ESCAPE) and FFullScreen then
  begin
    SetFullScreen(False);
    Key := 0;
  end;
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
    FillChar(P, SizeOf(P), 0);
    P.viewWidth := V.cx;
    P.viewHeight := V.cy;
    P.rotation := FRotation;
    P.eyeSeparationMM := FSeparation.Position;
    P.depthScale := FDepth.Position / 100;
    P.lookAround := Ord(FLookAround.Checked);
    P.flat := Ord(not FLensOn);
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
    FStatus.SimpleText := Format('%.0f fps   views %d x %d   eyes L(%.0f, %.0f, %.0f) R(%.0f, %.0f, %.0f) mm%s%s   %s',
      [FFrames / Secs, V.cx, V.cy,
       FLastInfo.leftEye[0], FLastInfo.leftEye[1], FLastInfo.leftEye[2],
       FLastInfo.rightEye[0], FLastInfo.rightEye[1], FLastInfo.rightEye[2],
       IfThen(FLastInfo.nominalEyes <> 0, '  (no eyes yet)', ''),
       IfThen(FLastInfo.separationRebuilt <> 0, '  (63 mm used)', ''),
       IfThen(FLensOn, 'lens on', 'lens off')]);
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

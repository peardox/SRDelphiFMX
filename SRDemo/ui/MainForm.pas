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
  FMX.ListBox,
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
    { F11 toggles full screen; Esc leaves it.
      @param(Sender the form)
      @param(Key the key)
      @param(KeyChar the character)
      @param(Shift modifier keys) }
    procedure FormKeyDown(Sender: TObject; var Key: Word; var KeyChar: WideChar;
      Shift: TShiftState);
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
    { Skip the eye tracker (use nominal eyes). }
    FSkipTracking: TCheckBox;
    { Skip rendering the scene. }
    FSkipRender: TCheckBox;
    { Skip handing the views to the bridge. }
    FSkipSubmit: TCheckBox;
    { Frames drawn, for the periodic FastMM5 scan. }
    FFrames: Integer;
    { Chooses the 3D scene or one of the stereo images in the media folder. }
    FShow: TComboBox;
    { Uses a fixed 63 mm eye separation instead of the tracker's. }
    FFixedIpd: TCheckBox;
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
    { Finds the media folder and lists its images in @link(FShow). }
    procedure ListMedia;
    { Shows the 3D scene or the chosen stereo image.
      @param(Sender the combo box) }
    procedure ShowChange(Sender: TObject);
    { Turns the fixed eye separation on or off.
      @param(Sender the checkbox) }
    procedure FixedIpdChange(Sender: TObject);
    { Applies the diagnostic skip checkboxes to the renderer.
      @param(Sender a checkbox) }
    procedure SkipChange(Sender: TObject);
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
  end;

var
  { The main window. }
  frmMain: TfrmMain;

implementation

{$R *.fmx}

uses
  FastMM5, SRDiagLog;

const
  { Most lines kept in the log. }
  MaxLogLines = 3000;
  { Frames between FastMM5 scans of its debug blocks for corruption. }
  FastMMScanEvery = 30;

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

  FFixedIpd := TCheckBox.Create(Self);
  FFixedIpd.Parent := Bar;
  FFixedIpd.Align := TAlignLayout.Left;
  FFixedIpd.Width := 200;
  FFixedIpd.Text := 'Fixed 63 mm eye separation';
  FFixedIpd.OnChange := FixedIpdChange;

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
  // 63 mm is what the owner's SR software is set to, and it looks better than
  // the tracker's measured separation (which wanders between 61 and 75 mm)
  FFixedIpd.IsChecked := True;
  FStereo.Active := True;   // completes once the form is shown
end;

procedure TfrmMain.FormClose(Sender: TObject; var Action: TCloseAction);
begin
  AddLog('Closing');
  FStereo.Active := False;
end;

procedure TfrmMain.FormKeyDown(Sender: TObject; var Key: Word; var KeyChar: WideChar;
  Shift: TShiftState);
begin
  if Key = vkF11 then
    FFullScreen.IsChecked := not FFullScreen.IsChecked
  else if (Key = vkEscape) and FFullScreen.IsChecked then
    FFullScreen.IsChecked := False;
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
  FullScreen := FFullScreen.IsChecked;
  AddLog('Full screen ' + BoolToStr(FullScreen, True));
end;

procedure TfrmMain.DepthChange(Sender: TObject);
begin
  FStereo.EyeSeparationScale := FDepth.Value;
end;

procedure TfrmMain.ListMedia;
var
  Dir, Candidate: string;
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
  if FindFirst(FMediaFolder + '*.*', faAnyFile, F) = 0 then
  try
    repeat
      if SameText(ExtractFileExt(F.Name), '.png') or SameText(ExtractFileExt(F.Name), '.jpg') or
        SameText(ExtractFileExt(F.Name), '.jpeg') then
        FShow.Items.Add(F.Name);
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
end;

procedure TfrmMain.FixedIpdChange(Sender: TObject);
const
  State: array[Boolean] of string = ('as tracked', 'fixed 63 mm');
begin
  if FFixedIpd.IsChecked then
    FStereo.EyeSeparationMM := 63
  else
    FStereo.EyeSeparationMM := 0;
  AddLog('Eye separation: ' + State[FFixedIpd.IsChecked]);
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

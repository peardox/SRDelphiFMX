{ @abstract(Main window of MoviePlayerFMX: a side-by-side film or frame
  shown on the LeiaSR display, with a log.)

  Open... (or Ctrl+O) loads a side-by-side film (FFmpeg, pictures only so
  far; Space pauses) or a single frame, half side-by-side as films are
  encoded, or full, and @link(TSRMovieRenderer) weaves it at its proper shape
  as a stereo pair. The viewport has no scene of its own: it is black until
  something is opened. The
  controls and the log sit outside the viewport, because the woven image
  covers it with a native window that hides FMX controls drawn over it. }
unit PlayerForm;

interface

uses
  System.SysUtils, System.Types, System.UITypes, System.Classes, System.Math.Vectors,
  FMX.Types, FMX.Controls, FMX.Forms, FMX.Graphics, FMX.StdCtrls, FMX.Layouts,
  FMX.Memo, FMX.Memo.Types, FMX.ScrollBox, FMX.Types3D, FMX.Controls3D,
  FMX.Viewport3D, FMX.Platform, FMX.Controls.Presentation, FMX.ListBox, FMX.Objects,
  SRSettings, SRStartProblem, SRStereoFrame, FMX.SRStereoViewport, FMX.SRMovieRenderer;

type
  { The player's main window. }
  TfrmPlayer = class(TForm)
    { Builds the viewport, controls and renderer, and opens the frame file
      named on the command line, if any. }
    procedure FormCreate(Sender: TObject);
    { Shuts SR down while the native window still exists.
      @param(Sender the form)
      @param(Action what to do with the form) }
    procedure FormClose(Sender: TObject; var Action: TCloseAction);
  private
    { Holds the viewport and, over it, @link(FFlatBack). }
    FViewArea: TLayout;
    { The viewport the renderer weaves; no scene of its own. }
    FViewport: TViewport3D;
    { The viewport's camera, which the renderer needs to draw from. }
    FCamera: TCamera;
    { Black backing for @link(FFlatImage), over the viewport; shown only
      while LeiaSR is off and a frame is open. }
    FFlatBack: TRectangle;
    { The frame's left view, shown in 2D while LeiaSR is off. }
    FFlatImage: TImage;
    { Shows the frame on the SR display. }
    FStereo: TSRMovieRenderer;
    { The frame file open now, empty for none. }
    FFileName: string;
    { The repository's media folder (found above the executable), empty if
      not found; where Open... starts. }
    FMediaFolder: string;
    { Status line. }
    FStatus: TLabel;
    { Turns glasses-free 3D on and off. }
    FToggle: TCheckBox;
    { How the frame is packed: auto, half side-by-side or full side-by-side
      (in @link(TSRStereoLayout) order). }
    FLayout: TComboBox;
    { When the display's lens is on: off over the controls, always on, or
      always off (in @link(TSRLensMode) order). }
    FLens: TComboBox;
    { Full screen on and off. }
    FFullScreen: TCheckBox;
    { The log. }
    FLog: TMemo;
    { Holds the toolbar and the log; hidden as a whole in full screen. }
    FBottomArea: TLayout;
    { Frames drawn, for the periodic FastMM5 scan. }
    FFrames: Integer;
    { Saved settings, shared with the demos. }
    FSettings: TSRSettings;
    { Set while settings are being applied, so the controls' handlers do not
      save them back half-applied. }
    FLoading: Boolean;
    { Controls that only mean anything with LeiaSR, hidden where it is not
      installed. }
    FSROnly: TArray<TControl>;
    { Whether this computer has the LeiaSR runtime. }
    FSRInstalled: Boolean;
    { Adds a control to @link(FSROnly).
      @param(C the control)
      @returns(C) }
    function SROnly(C: TControl): TControl;
    { Builds the viewport and the 2D image over it. }
    procedure BuildView;
    { Builds the toolbar and the log. }
    procedure BuildControls;
    { Finds the repository's media folder above the executable. }
    procedure FindMedia;
    { Adds a line to the log, with the time.
      @param(Msg the line) }
    procedure AddLog(const Msg: string);
    { Opens a frame file chosen in a dialog, with the lens held off so the
      dialog can be read.
      @param(Sender the button) }
    procedure OpenClick(Sender: TObject);
    { Shows a frame file with the layout chosen in @link(FLayout).
      @param(FileName the file; empty shows nothing) }
    procedure ShowFile(const FileName: string);
    { Shows the open frame again with the newly chosen layout.
      @param(Sender the combo box) }
    procedure LayoutChange(Sender: TObject);
    { Turns glasses-free 3D on or off from the checkbox.
      @param(Sender the checkbox) }
    procedure ToggleChange(Sender: TObject);
    { Sets the renderer's lens mode.
      @param(Sender the combo box) }
    procedure LensChange(Sender: TObject);
    { Full screen on or off.
      @param(Sender the checkbox) }
    procedure FullScreenChange(Sender: TObject);
    { Opens the settings dialog (the eye separation), with the lens held off
      so it can be read.
      @param(Sender the button) }
    procedure SettingsClick(Sender: TObject);
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
    { Shows a renderer error and unticks glasses-free 3D after the click is
      done.
      @param(Sender the renderer)
      @param(Msg the error) }
    procedure StereoError(Sender: TObject; const Msg: string);
    { LeiaSR could not start, or was turned off because it would run very
      badly: asks the user (continue without glasses-free 3D, try again, use
      glasses-free 3D anyway, or exit), and offers the high-performance GPU
      when that would fix it.
      @param(Sender the renderer)
      @param(Problem what went wrong)
      @param(Msg the details)
      @param(CanDegrade whether glasses-free 3D anyway can be offered)
      @param(CanFixGpu whether the Windows GPU preference should fix it)
      @param(Choice receives the user's choice) }
    procedure StereoStartProblem(Sender: TObject; Problem: TSRStartProblem; const Msg: string;
      CanDegrade, CanFixGpu: Boolean; var Choice: TSRStartChoice);
    { LeiaSR is running: hides the 2D image and ticks glasses-free 3D.
      @param(Sender the renderer) }
    procedure StereoStarted(Sender: TObject);
    { Adds a renderer log line.
      @param(Sender the renderer)
      @param(Msg the line) }
    procedure StereoLog(Sender: TObject; const Msg: string);
    { Shows the eye positions and the frame in the status line.
      @param(Sender the renderer)
      @param(LeftMM left eye, millimetres)
      @param(RightMM right eye, millimetres) }
    procedure StereoEyes(Sender: TObject; const LeftMM, RightMM: TPoint3D);
    { Shows the frame's left view in 2D while LeiaSR is off, and hides it
      otherwise. }
    procedure UpdateFlatImage;
    { Sets the glasses-free 3D tick box without starting or stopping
      anything.
      @param(Value whether it is ticked) }
    procedure SetToggleQuietly(Value: Boolean);
    { The open frame for the status line.
      @returns(its name and layout, or a hint to open one) }
    function FrameText: string;
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
      @returns(@true if the key was one the player uses (F11, Esc in full
        screen, Ctrl+O, Space while a film is open) and must not reach any
        control) }
    function HookKey(Key: Word; IsRepeat: Boolean): Boolean;
  end;

var
  { The main window. }
  frmPlayer: TfrmPlayer;

implementation

{$R *.fmx}

uses
  System.Math, FMX.Dialogs, FMX.Platform.Win, FastMM5, SRDiagLog, SRSettingsDialog;

{ The few Windows calls the keyboard hook needs, declared here rather than
  using Winapi.Windows, whose names (Rectangle, TBitmap and others) would
  hide FMX's in this unit. }
const
  { SetWindowsHookEx: hook keyboard messages. }
  WH_KEYBOARD = 2;
  { Hook code: a key message is being taken from the queue. }
  HC_ACTION = 0;
  { GetKeyState: the Ctrl key. }
  VK_CONTROL = $11;

function SetWindowsHookExW(idHook: Integer; lpfn: Pointer; hmod: NativeUInt;
  dwThreadId: Cardinal): NativeUInt; stdcall; external 'user32.dll';
function UnhookWindowsHookEx(hhk: NativeUInt): LongBool; stdcall; external 'user32.dll';
function CallNextHookEx(hhk: NativeUInt; nCode: Integer; wParam: NativeUInt;
  lParam: NativeInt): NativeInt; stdcall; external 'user32.dll';
function GetLastError: Cardinal; stdcall; external 'kernel32.dll';
function GetCurrentThreadId: Cardinal; stdcall; external 'kernel32.dll';
function GetKeyState(nVirtKey: Integer): SmallInt; stdcall; external 'user32.dll';
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
  { The program's name, for dialogs. }
  AppName = 'MoviePlayerFMX';
  { Most lines kept in the log. }
  MaxLogLines = 3000;
  { Frames between FastMM5 scans of its debug blocks for corruption. }
  FastMMScanEvery = 30;

var
  { The keyboard hook, 0 if none. }
  KeyHook: NativeUInt = 0;
  { The form the hook reports to, nil once it is gone. }
  KeyHookForm: TfrmPlayer = nil;

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

const
  { Open...'s masks for stills, read with WIC. }
  FrameMasks = '*.png;*.jpg;*.jpeg';
  { Open...'s masks for films, read with FFmpeg. }
  FilmMasks = '*.mkv;*.mp4;*.m4v;*.mov;*.ts;*.m2ts;*.webm;*.avi';

{ Whether a file is a still (WIC) rather than a film (FFmpeg), by its
  extension.
  @param(FileName the file)
  @returns(@true for PNG and JPEG) }
function IsFrameFile(const FileName: string): Boolean;
var
  Ext: string;
begin
  Ext := LowerCase(ExtractFileExt(FileName));
  Result := (Ext = '.png') or (Ext = '.jpg') or (Ext = '.jpeg');
end;

{ A time as text for the status line.
  @param(Seconds the time; below 0 shows as unknown)
  @returns(such as 1:02:03 or 2:03) }
function FormatSeconds(Seconds: Double): string;
var
  T: Integer;
begin
  if Seconds < 0 then
    Exit('-:--');
  T := Trunc(Seconds);
  if T >= 3600 then
    Result := Format('%d:%.2d:%.2d', [T div 3600, (T div 60) mod 60, T mod 60])
  else
    Result := Format('%d:%.2d', [T div 60, T mod 60]);
end;

procedure TfrmPlayer.BuildView;
begin
  FViewArea := TLayout.Create(Self);
  FViewArea.Parent := Self;
  FViewArea.Align := TAlignLayout.Client;

  // TSRViewport3D: leaves out FMX's own drawing while glasses-free 3D covers it
  FViewport := TSRViewport3D.Create(Self);
  FViewport.Parent := FViewArea;
  FViewport.Align := TAlignLayout.Client;
  FViewport.Color := TAlphaColors.Black;
  FViewport.UsingDesignCamera := False;

  // The renderer draws from the viewport's camera; there is nothing else in
  // the viewport, so the frame is all that is ever seen
  FCamera := TCamera.Create(Self);
  FCamera.Parent := FViewport;
  FCamera.Position.Point := Point3D(0, 0, -20);
  FViewport.Camera := FCamera;

  // The frame's left view, for 2D while LeiaSR is off (the woven image only
  // exists while it runs). Over the viewport, so made last.
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

procedure TfrmPlayer.BuildControls;
var
  Bar: TLayout;
  Lbl: TLabel;
  Btn: TButton;
begin
  // One area at the bottom: the toolbar, then the log; only the area is
  // hidden in full screen, so the order never changes (as in SRDemoFMX)
  FBottomArea := TLayout.Create(Self);
  FBottomArea.Parent := Self;
  FBottomArea.Align := TAlignLayout.Bottom;
  FBottomArea.Height := 36 + 150;

  FLog := TMemo.Create(Self);
  FLog.Parent := FBottomArea;
  FLog.Align := TAlignLayout.Bottom;
  FLog.Height := 150;
  FLog.ReadOnly := True;
  FLog.TextSettings.Font.Family := 'Consolas';
  FLog.TextSettings.Font.Size := 11;

  Bar := TLayout.Create(Self);
  Bar.Parent := FBottomArea;
  Bar.Align := TAlignLayout.Client;
  Bar.Padding.Rect := RectF(8, 4, 8, 4);

  FToggle := TCheckBox.Create(Self);
  FToggle.Parent := Bar;
  SROnly(FToggle);
  FToggle.Align := TAlignLayout.Left;
  FToggle.Width := 130;
  FToggle.Text := 'Glasses-free 3D';
  FToggle.IsChecked := True;
  FToggle.OnChange := ToggleChange;

  Btn := TButton.Create(Self);
  Btn.Parent := Bar;
  Btn.Align := TAlignLayout.Left;
  Btn.Width := 80;
  Btn.Margins.Left := 4;
  Btn.Text := 'Open...';
  Btn.OnClick := OpenClick;

  Lbl := TLabel.Create(Self);
  Lbl.Parent := Bar;
  Lbl.Align := TAlignLayout.Left;
  Lbl.Width := 50;
  Lbl.Margins.Left := 12;
  Lbl.Text := 'Layout';

  FLayout := TComboBox.Create(Self);
  FLayout.Parent := Bar;
  FLayout.Align := TAlignLayout.Left;
  FLayout.Width := 170;
  FLayout.Items.Add('Auto');
  FLayout.Items.Add('Full side-by-side');
  FLayout.Items.Add('Half side-by-side');
  FLayout.ItemIndex := Ord(layoutAuto);
  FLayout.OnChange := LayoutChange;

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

  FFullScreen := TCheckBox.Create(Self);
  FFullScreen.Parent := Bar;
  FFullScreen.Align := TAlignLayout.Left;
  FFullScreen.Width := 120;
  FFullScreen.Margins.Left := 12;
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

procedure TfrmPlayer.FormCreate(Sender: TObject);
var
  C: TControl;
begin
  Caption := AppName;
  Application.OnException := AppException;
  WindowState := TWindowState.wsMaximized;
  BuildControls;
  BuildView;

  FStereo := TSRMovieRenderer.Create(Self);
  FStereo.Viewport := FViewport;
  FStereo.FocusDistance := 20;
  FStereo.OnError := StereoError;
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
  FindMedia;
  LoadSettings;
  InstallKeyHook;
  FSRInstalled := TSRStereoRenderer.SRInstalled;
  if not FSRInstalled then
  begin
    // As if the program had no SR support: no controls, no messages
    AddLog('LeiaSR runtime not installed: glasses-free 3D controls hidden, LeiaSR not started');
    for C in FSROnly do
      C.Visible := False;
    FStatus.Text := FrameText;
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
  // A frame file on the command line is opened at once
  if (ParamCount >= 1) and (ParamStr(1) <> '') and (ParamStr(1)[1] <> '/') then
  begin
    if FileExists(ParamStr(1)) then
    begin
      AddLog('Opening the frame given on the command line: ' + ParamStr(1));
      ShowFile(ExpandFileName(ParamStr(1)));
    end
    else
      AddLog('Command line names ' + ParamStr(1) + ', which does not exist: nothing opened');
  end;
  UpdateFlatImage;
end;

function TfrmPlayer.SROnly(C: TControl): TControl;
begin
  FSROnly := FSROnly + [C];
  Result := C;
end;

procedure TfrmPlayer.FormClose(Sender: TObject; var Action: TCloseAction);
begin
  AddLog('Closing');
  FStereo.Active := False;
end;

destructor TfrmPlayer.Destroy;
begin
  KeyHookForm := nil;
  if KeyHook <> 0 then
    UnhookWindowsHookEx(KeyHook);
  KeyHook := 0;
  FSettings.Free;
  inherited;
end;

procedure TfrmPlayer.FindMedia;
var
  Dir, Candidate: string;
  I: Integer;
begin
  // The exe is in MoviePlayerFMX\Win64\Release (or beside media\ when
  // released); look upwards for the media folder
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
    AddLog('No media folder found above ' + ExtractFilePath(ParamStr(0)) +
      ': Open... starts in the Windows default folder')
  else
    AddLog('Media folder: ' + FMediaFolder);
end;

procedure TfrmPlayer.InstallKeyHook;
begin
  KeyHookForm := Self;
  KeyHook := SetWindowsHookExW(WH_KEYBOARD, @KeyHookProc, 0, GetCurrentThreadId);
  if KeyHook = 0 then
    AddLog(Format('Keyboard hook NOT installed (error %d): F11 and Esc will not work',
      [GetLastError]))
  else
    AddLog('Keyboard hook installed: F11 toggles full screen, Esc leaves it');
end;

function TfrmPlayer.HookKey(Key: Word; IsRepeat: Boolean): Boolean;
var
  Leave: Boolean;
begin
  // Space pauses or resumes a film
  if (Key = vkSpace) and (FStereo.Video <> nil) then
  begin
    Result := True;
    if not IsRepeat then
      TThread.ForceQueue(nil,
        procedure
        begin
          if KeyHookForm <> nil then
            KeyHookForm.FStereo.TogglePause;
        end);
    Exit;
  end;
  // Ctrl+O opens a frame, also in full screen, where the toolbar is hidden
  if (Key = vkO) and (GetKeyState(VK_CONTROL) < 0) then
  begin
    Result := True;
    if not IsRepeat then
      TThread.ForceQueue(nil,
        procedure
        begin
          if KeyHookForm <> nil then
            KeyHookForm.OpenClick(nil);
        end);
    Exit;
  end;
  Result := (Key = vkF11) or ((Key = vkEscape) and FFullScreen.IsChecked);
  if (not Result) or IsRepeat then
    Exit;
  Leave := Key = vkEscape;
  AddLog(Format('Key %s, full screen was %s', [IfThenStr(Leave, 'Esc', 'F11'),
    BoolToStr(FFullScreen.IsChecked, True)]));
  TThread.ForceQueue(nil,
    procedure
    begin
      if KeyHookForm <> nil then
        KeyHookForm.FullScreenKey(Leave);
    end);
end;

procedure TfrmPlayer.FullScreenKey(Leave: Boolean);
begin
  if Leave then
    FFullScreen.IsChecked := False
  else
    FFullScreen.IsChecked := not FFullScreen.IsChecked;
end;

procedure TfrmPlayer.AddLog(const Msg: string);
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

procedure TfrmPlayer.OpenClick(Sender: TObject);
var
  Dlg: TOpenDialog;
  Picked: Boolean;
begin
  Dlg := TOpenDialog.Create(nil);
  try
    Dlg.Title := 'Open a side-by-side film or frame';
    Dlg.Filter := 'Films and frames|' + FilmMasks + ';' + FrameMasks + '|Films|' + FilmMasks +
      '|Frames|' + FrameMasks + '|All files (*.*)|*.*';
    // The folder last opened from (also in earlier runs), else media\hsbs
    if FFileName <> '' then
      Dlg.InitialDir := ExtractFileDir(FFileName)
    else if (FSettings <> nil) and (FSettings.PlayerFolder <> '') and
      DirectoryExists(FSettings.PlayerFolder) then
      Dlg.InitialDir := FSettings.PlayerFolder
    else if DirectoryExists(FMediaFolder + 'hsbs') then
      Dlg.InitialDir := FMediaFolder + 'hsbs'
    else
      Dlg.InitialDir := ExcludeTrailingPathDelimiter(FMediaFolder);
    // The lens off while the dialog is up, or it cannot be read
    FStereo.SuspendLens(True);
    try
      Picked := Dlg.Execute;
    finally
      FStereo.SuspendLens(False);
    end;
    if Picked then
      ShowFile(Dlg.FileName)
    else
      AddLog('Open...: cancelled');
  finally
    Dlg.Free;
  end;
end;

procedure TfrmPlayer.ShowFile(const FileName: string);
begin
  if FileName = '' then
    Exit;
  try
    // A still through WIC; anything else is taken for a film (FFmpeg)
    if IsFrameFile(FileName) then
      FStereo.ShowFrameFile(FileName, TSRStereoLayout(FLayout.ItemIndex))
    else
      FStereo.PlayFile(FileName, TSRStereoLayout(FLayout.ItemIndex));
    FFileName := FileName;
    Caption := AppName + ' - ' + ExtractFileName(FileName);
    // Open... starts here next time, also after a restart
    if (FSettings <> nil) and not SameText(FSettings.PlayerFolder, ExtractFileDir(FileName)) then
    begin
      FSettings.PlayerFolder := ExtractFileDir(FileName);
      SaveSettings;
    end;
  except
    on E: Exception do
    begin
      AddLog('Cannot show ' + FileName + ': ' + E.Message);
      FStatus.Text := 'Cannot show ' + ExtractFileName(FileName) + ' (see the log)';
    end;
  end;
  UpdateFlatImage;
  if not FStereo.Running then
    FStatus.Text := FrameText;
end;

procedure TfrmPlayer.LayoutChange(Sender: TObject);
begin
  AddLog('Layout: ' + FLayout.Items[FLayout.ItemIndex]);
  // A film takes it from its next picture; a still's layout is decided when
  // it is loaded, so it is loaded again
  if FStereo.Video <> nil then
    FStereo.VideoLayout := TSRStereoLayout(FLayout.ItemIndex)
  else if FFileName <> '' then
    ShowFile(FFileName);
end;

function TfrmPlayer.FrameText: string;
var
  Len: Double;
begin
  Len := -1;   // unknown
  if (FStereo.Video <> nil) and (FStereo.Video.Duration > 0) then
    Len := FStereo.Video.Duration;
  if FStereo.Video <> nil then
    Result := Format('%s  %s / %s%s, %s', [ExtractFileName(FFileName),
      FormatSeconds(FStereo.Video.Position), FormatSeconds(Len),
      IfThenStr(FStereo.Video.Paused, ' (paused: Space)', ''),
      TSRStereoFrame.LayoutName(FStereo.Frame.Layout)])
  else if not FStereo.Frame.Loaded then
    Result := 'Nothing open (Open... or Ctrl+O)'
  else
    Result := FStereo.Frame.Name + ', ' + TSRStereoFrame.LayoutName(FStereo.Frame.Layout);
end;

procedure TfrmPlayer.ToggleChange(Sender: TObject);
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

procedure TfrmPlayer.LensChange(Sender: TObject);
begin
  FStereo.LensMode := TSRLensMode(FLens.ItemIndex);
  if FSettings <> nil then
    FSettings.LensMode := FLens.ItemIndex;
  AddLog('Lens: ' + FLens.Items[FLens.ItemIndex]);
  SaveSettings;
end;

procedure TfrmPlayer.FullScreenChange(Sender: TObject);
begin
  // Full screen shows only the view; F11 or Esc brings the rest back. The
  // renderer's full screen, not the form's (see SRDemoFMX)
  FBottomArea.Visible := not FFullScreen.IsChecked;
  FStereo.FullScreen := FFullScreen.IsChecked;
  // Not saved: the settings file is shared with the demos, and starting in
  // full screen would hide Open... before a frame is open
  AddLog(Format('Full screen %s: form now %d x %d logical (F11 or Esc to leave)',
    [BoolToStr(FStereo.FullScreen, True), Width, Height]));
end;

procedure TfrmPlayer.SettingsClick(Sender: TObject);
var
  MM: Integer;
begin
  MM := Round(FSettings.EyeSeparationMM);
  // A Windows dialog owned by the form, in front of it, with the lens off
  FStereo.SuspendLens(True);
  try
    if not AskEyeSeparation(FormToHWND(Self), AppName, MM) then
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

procedure TfrmPlayer.LoadSettings;
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
  // The same file as the demos: only the settings the player uses are
  // applied, and the rest are written back as they were read
  FLoading := True;
  try
    FStereo.EyeSeparationMM := FSettings.EyeSeparationMM;
    FStereo.EyeSeparationScale := 1;
    FStereo.FocusDistance := FSettings.FocusDistance;
    FStereo.LookAround := FSettings.LookAround;
    FStereo.LatencyFrames := FSettings.LatencyFrames;
    FLens.ItemIndex := EnsureRange(FSettings.LensMode, 0, FLens.Items.Count - 1);
    FStereo.LensMode := TSRLensMode(FLens.ItemIndex);
    // fullScreen is SRDemoFMX's: the player always starts in a window, so
    // Open... is on screen (F11 for full screen)
  finally
    FLoading := False;
  end;
  AddLog(Format('Settings: glasses-free 3D %s, eye separation %.0f mm, latency %d, lens %s; ' +
    'starting in a window (the saved fullScreen %s is SRDemoFMX''s, not used here)',
    [BoolToStr(FSettings.UseGlassesFree3D, True), FSettings.EyeSeparationMM,
    FSettings.LatencyFrames, FLens.Items[FLens.ItemIndex], BoolToStr(FSettings.FullScreen, True)]));
end;

procedure TfrmPlayer.SaveSettings;
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

procedure TfrmPlayer.AppException(Sender: TObject; E: Exception);
begin
  DiagLog('EXCEPTION reached the application: ' + E.ClassName + ': ' + E.Message);
  Application.ShowException(E);
end;

procedure TfrmPlayer.CopyLogClick(Sender: TObject);
var
  Clip: IFMXClipboardService;
begin
  if TPlatformServices.Current.SupportsPlatformService(IFMXClipboardService, Clip) then
  begin
    Clip.SetClipboard(FLog.Lines.Text);
    FStatus.Text := Format('Copied %d log lines', [FLog.Lines.Count]);
  end;
end;

procedure TfrmPlayer.ClearLogClick(Sender: TObject);
begin
  FLog.Lines.Clear;
end;

procedure TfrmPlayer.StereoError(Sender: TObject; const Msg: string);
begin
  FStatus.Text := 'LeiaSR error: ' + Msg;
  TThread.ForceQueue(nil,
    procedure
    begin
      SetToggleQuietly(FStereo.Active);
      UpdateFlatImage;
    end);
end;

procedure TfrmPlayer.SetToggleQuietly(Value: Boolean);
begin
  FToggle.OnChange := nil;
  try
    FToggle.IsChecked := Value;
  finally
    FToggle.OnChange := ToggleChange;
  end;
end;

procedure TfrmPlayer.UpdateFlatImage;
var
  Show: Boolean;
begin
  Show := not FStereo.Running and FStereo.Frame.Loaded;
  if Show then
    Show := FStereo.CopyFrameLeftView(FFlatImage.Bitmap);
  if Show <> FFlatBack.Visible then
    AddLog(IfThenStr(Show, Format('Showing the frame''s left view in 2D (LeiaSR off), %d x %d',
      [FFlatImage.Bitmap.Width, FFlatImage.Bitmap.Height]), 'No 2D image over the viewport'));
  FFlatBack.Visible := Show;
end;

procedure TfrmPlayer.StereoStarted(Sender: TObject);
begin
  SetToggleQuietly(True);
  UpdateFlatImage;
end;

procedure TfrmPlayer.StereoStartProblem(Sender: TObject; Problem: TSRStartProblem;
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
    FixText := 'Also set ' + AppName + ' to use the high-performance GPU (from its next start)';
  Owner := FormToHWND(Self);
  Choice := AskStartProblem(Owner, AppName, Problem, Msg, CanDegrade, FixText, FixWanted);
  AddLog(Format('Start problem (%s): the user chose to %s%s', [StartProblemName(Problem),
    ChoiceNames[Choice], IfThenStr(FixWanted, ', and the high-performance GPU', '')]));
  if FixWanted then
  begin
    if FStereo.SetHighPerformanceGpu then
      MessageBoxW(Owner, 'Done. Close MoviePlayerFMX and start it again for glasses-free 3D ' +
        'at full speed.', AppName + ': GPU', MB_OK or MB_ICONINFORMATION or MB_SETFOREGROUND)
    else
      MessageBoxW(Owner, 'Windows did not accept the setting. Set it by hand in Settings > ' +
        'System > Display > Graphics.', AppName + ': GPU',
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

procedure TfrmPlayer.StereoLog(Sender: TObject; const Msg: string);
begin
  AddLog(Msg);
end;

procedure TfrmPlayer.StereoEyes(Sender: TObject; const LeftMM, RightMM: TPoint3D);
const
  Mode: array[Boolean] of string = ('2D fallback', 'Weaving');
begin
  // In full debug mode, look for heap corruption close to when it happens
  Inc(FFrames);
  if FastMM_DebugModeActive and (FFrames mod FastMMScanEvery = 0) then
    FastMM_ScanDebugBlocksForCorruption;
  FStatus.Text := Format('%s   L(%.0f, %.0f, %.0f)  R(%.0f, %.0f, %.0f) mm   %s',
    [Mode[FStereo.Weaving], LeftMM.X, LeftMM.Y, LeftMM.Z, RightMM.X, RightMM.Y, RightMM.Z,
     FrameText]);
end;

end.

{ @abstract(SRFullScreenTest's window: a plain Win32 window, no FMX, showing
  a woven stereo image, windowed or full screen, with each suspect of the
  full-screen fault switchable from the keyboard.)

  The window is made full screen exactly as Leia's DX11 sample does it
  (Raymond Chen's method: remove @code(WS_OVERLAPPEDWINDOW) and cover the
  monitor with @code(SetWindowPos)), on the SR display. Nothing else draws
  into it, so the bridge can weave into this window itself, as the samples
  do, instead of its own child window.

  Keys (also written to the log at the start):
  @unorderedList(
    @item(F11 full screen on and off; Esc leaves full screen.)
    @item(W weave into this window itself / the bridge's child window
      (restarts the bridge).)
    @item(A adapter: most memory / default / the one driving the window's
      monitor (restarts the bridge).)
    @item(M swap chain: bitblt / flip model (restarts the bridge).)
    @item(V views: the window's size / SR's recommended size.)
    @item(R give the weaver its input every frame, on or off.)
    @item(P a second swap chain on this window, as FMX has on its form:
      none / bitblt / flip model (restarts the bridge; child window only).)
    @item(E ask the weaver for the predicted eye positions, and the bridge
      for the window's size in millimetres, every frame, as SRDemoFMX does.)
    @item(K weaver latency: SR's default, then 1 to 4 frames, as SRDemoFMX's
      Latency box.)
    @item(F submit RGBA pixels instead of BGRA, as SRDemoFMX does when FMX's
      surface is RGBA.)
    @item(T tell the taskbar the window is full screen
      (@code(ITaskbarList2.MarkFullscreenWindow)), as SRDemoFMX does.)
    @item(H hold the window at the full-screen rectangle with a
      @code(WM_WINDOWPOSCHANGING) subclass, as SRDemoFMX does.)
    @item(L lens on or off.)
    @item(N next image: the test pattern, then each image in @code(media).)
    @item(B and G write a "broken now" or "good now" mark in the log.)
  )

  The same choices can be made on the command line: @code(/fs) full screen,
  @code(/window) weave into the window, @code(/adapter=0..2), @code(/flip),
  @code(/rec) recommended views, @code(/reapply), @code(/parent=0..2), @code(/eyes), @code(/latency=0..4), @code(/rgba), @code(/mark), @code(/hold), @code(/lensoff),
  @code(/image=beer.jpg). Every change, every move of the window, Windows'
  own idea of whether a full-screen program is running
  (@code(SHQueryUserNotificationState)) and a summary each second go to
  @code(SRFullScreenTest.log). }
unit TestWindow;

interface

{ Creates the window, starts the bridge and runs the message and frame loop
  until the window is closed.
  @returns(the exit code: 0, or 1 if the bridge could not be loaded) }
function RunFullScreenTest: Integer;

implementation

uses
  Winapi.Windows, Winapi.MultiMon, Winapi.Messages, Winapi.ActiveX, Winapi.ShlObj,
  System.Win.ComObj, System.SysUtils, System.Classes,
  System.Types, System.Diagnostics, System.IOUtils, System.Math, System.StrUtils,
  SRDiagLog, SRBridge.Api, SRStereoImage;

const
  { The window class's name. }
  WindowClassName = 'SRFullScreenTestWindow';
  { The program's name, in the title bar. }
  AppTitle = 'SRFullScreenTest';
  { Seconds to wait for the SR service when the bridge starts. }
  InitTimeout = 5.0;
  { @code(WM_DPICHANGED), declared here in case the RTL's name differs. }
  MsgDpiChanged = $02E0;
  { @code(DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2). }
  DpiPerMonitorV2 = THandle(-4);
  { The bridge export added on 5 November 2026 with the other two options. }
  NewOptionsExport = 'srb_SetWeaverWindow';
  { The bridge export for the stand-in for FMX's swap chain. }
  ParentChainExport = 'srb_SetParentSwapChain';

{ user32's @code(SetProcessDpiAwarenessContext), declared here so the name
  does not depend on the RTL version.
  @param(Value a @code(DPI_AWARENESS_CONTEXT))
  @returns(@true if set; @false if the manifest had already set it) }
function SRTSetProcessDpiAwarenessContext(Value: THandle): BOOL; stdcall;
  external user32 name 'SetProcessDpiAwarenessContext' delayed;

{ user32's @code(GetDpiForWindow).
  @param(Wnd the window)
  @returns(its DPI, 96 at 100% scaling) }
function SRTGetDpiForWindow(Wnd: HWND): UINT; stdcall;
  external user32 name 'GetDpiForWindow' delayed;

{ shell32's @code(SHQueryUserNotificationState): whether Windows thinks a
  full-screen program or presentation is running.
  @param(State receives a @code(QUERY_USER_NOTIFICATION_STATE) value)
  @returns(S_OK when it worked) }
function SRTSHQueryUserNotificationState(out State: Integer): HRESULT; stdcall;
  external 'shell32.dll' name 'SHQueryUserNotificationState' delayed;

const
  { Window message sent before a window is moved or sized. }
  MsgWindowPosChanging = $0046;
  { Identifies the hold subclass of the window. }
  HoldSubclassId = $53524654;   // 'SRFT'

type
  { Signature of a comctl32 window subclass procedure. }
  TSubclassProc = function(Wnd: HWND; Msg: UINT; WP: WPARAM; LP: LPARAM;
    IdSubclass: UIntPtr; RefData: UIntPtr): LRESULT; stdcall;

{ comctl32's SetWindowSubclass, declared here as in SRDemoFMX's renderer.
  @param(Wnd the window) @param(Proc the subclass procedure)
  @param(IdSubclass our id) @param(RefData passed to Proc)
  @returns(@true on success) }
function SetWindowSubclass(Wnd: HWND; Proc: TSubclassProc; IdSubclass: UIntPtr;
  RefData: UIntPtr): BOOL; stdcall; external 'comctl32.dll';
{ comctl32's RemoveWindowSubclass. @param(Wnd the window)
  @param(Proc the subclass procedure) @param(IdSubclass our id)
  @returns(@true on success) }
function RemoveWindowSubclass(Wnd: HWND; Proc: TSubclassProc;
  IdSubclass: UIntPtr): BOOL; stdcall; external 'comctl32.dll';
{ comctl32's DefSubclassProc: passes a message on. @param(Wnd the window)
  @param(Msg the message) @param(WP its wParam) @param(LP its lParam)
  @returns(the result) }
function DefSubclassProc(Wnd: HWND; Msg: UINT; WP: WPARAM; LP: LPARAM): LRESULT;
  stdcall; external 'comctl32.dll';

type
  { The test: the window, the bridge and what is being varied. One
    instance, @link(Test), for the window procedure to reach. }
  TFullScreenTest = class
  private
    { The window. }
    FWnd: HWND;
    { @true after the window is destroyed: leave the loop. }
    FQuit: Boolean;
    { @true while the bridge is initialised. }
    FRunning: Boolean;
    { @true when a key has asked for the bridge to be restarted with new
      options; done at the start of the next frame, not inside the window
      procedure. }
    FRestartPending: Boolean;

    { @true while full screen. }
    FFullScreen: Boolean;
    { The window's placement before full screen, restored after it. }
    FPlacement: TWindowPlacement;
    { Milliseconds on @link(FClock) when full screen came on. }
    FFullScreenSinceMs: Int64;

    { Weave into this window itself (@true) or the bridge's child window. }
    FWeaveOnWindow: Boolean;
    { Adapter choice for the bridge: 0 most memory, 1 default, 2 the
      window's monitor's. }
    FAdapter: Integer;
    { Flip-model swap chain instead of bitblt. }
    FFlipModel: Boolean;
    { @true once @code(srb_SetPresentModel) has been called, so later starts
      call it too. }
    FPresentModelSet: Boolean;
    { Views at SR's recommended size instead of the window's size. }
    FRecommended: Boolean;
    { Give the weaver its input every frame. }
    FReapplyInput: Boolean;
    { Lens wanted on. }
    FLensOn: Boolean;
    { @true when the loaded bridge has the 5 November 2026 options. }
    FHasNewOptions: Boolean;
    { Second swap chain on this window, as FMX's: 0 none, 1 bitblt, 2 flip. }
    FParentChain: Integer;
    { @true when the loaded bridge has @code(srb_SetParentSwapChain). }
    FHasParentChain: Boolean;
    { Query the eye positions and the window in millimetres every frame, as
      SRDemoFMX does. }
    FQueryEyes: Boolean;
    { Weaver latency in frames, 0 for SR's default. }
    FLatency: Integer;
    { @true once a latency has been given to the weaver, so going back to 0
      says it cannot be undone without a restart. }
    FLatencySet: Boolean;
    { Submit RGBA instead of BGRA (red and blue swapped in the buffer). }
    FRgba: Boolean;
    { Mark the window full screen with @code(ITaskbarList2). }
    FMarkTaskbar: Boolean;
    { @true while the taskbar has been told the window is full screen. }
    FMarked: Boolean;
    { Hold the window at @link(FFullScreenRect) while full screen. }
    FHold: Boolean;
    { @true while the hold subclass is installed. }
    FHoldInstalled: Boolean;
    { Moves or sizes the hold has corrected since the last summary. }
    FHoldCorrections: Integer;
    { The full-screen rectangle, for the hold. }
    FFullScreenRect: TRect;
    { Eye queries since the last summary line that returned real positions. }
    FEyeQueries: Integer;
    { The last eye positions read, for the summary line. }
    FLastEyes: array[0..1] of TSRBVec3;

    { The SR display's rectangle on the desktop, physical pixels. }
    FSRRect: TRect;
    { @true when @link(FSRRect) is known. }
    FSRRectKnown: Boolean;
    { The SR display's properties. }
    FInfo: TSRBDisplayInfo;
    { @true when @link(FInfo) is known. }
    FInfoKnown: Boolean;

    { The image being shown. }
    FImage: TSRStereoImage;
    { Image files found in the @code(media) folder. }
    FImageFiles: TStringList;
    { Index into @link(FImageFiles), or -1 for the test pattern. }
    FImageIndex: Integer;
    { The side-by-side views submitted each frame. }
    FPixels: TBytes;
    { Width of each view in @link(FPixels). }
    FViewW: Integer;
    { Height of each view in @link(FPixels). }
    FViewH: Integer;
    { @true when @link(FPixels) must be rebuilt. }
    FViewsDirty: Boolean;
    { Client width last given to @code(srb_SetBounds); 0 forces a call. }
    FBoundsW: Integer;
    { Client height last given to @code(srb_SetBounds). }
    FBoundsH: Integer;

    { Time since the start. }
    FClock: TStopwatch;
    { @link(FClock) milliseconds of the last summary line. }
    FLastLogMs: Int64;
    { @link(FClock) milliseconds of the last notification-state check. }
    FLastNotifyMs: Int64;
    { Frames since the last summary line. }
    FFramesSinceLog: Integer;
    { Results of @code(srb_SubmitViews) since the last summary: woven, 2D,
      occluded, error. }
    FResults: array[0..3] of Integer;
    { The window's rectangle when last logged. }
    FLastWindowRect: TRect;
    { The last @code(SHQueryUserNotificationState) value, -1 before the
      first. }
    FNotifyState: Integer;
    { Whether this window was in the foreground when last checked, -1 before
      the first. }
    FForeground: Integer;
    { Marks written so far with B and G. }
    FMarks: Integer;

    { Reads the command line into the options. }
    procedure ParseCommandLine;
    { Finds the @code(media) folder above the executable and lists its
      images. }
    procedure FindImages;
    { Loads image @link(FImageIndex), or the test pattern. }
    procedure LoadImage;
    { Creates the window. @returns(@true if it was created) }
    function CreateTheWindow: Boolean;
    { Sets the bridge's options and initialises it. }
    procedure StartBridge;
    { Finalises the bridge, if running. }
    procedure StopBridge;
    { Moves the window onto the SR display, if it is elsewhere. @returns(@true
      if it moved) }
    function PlaceOnSRDisplay: Boolean;
    { Turns full screen on or off, as Leia's sample does.
      @param(Value @true for full screen) }
    procedure SetFullScreen(Value: Boolean);
    { Draws and submits one frame, and the checks that go with it. }
    procedure Frame;
    { Logs window moves, Windows' full-screen state, the foreground window
      and SR events, and a summary each second. }
    procedure Watch;
    { Logs the current choices, with a reason.
      @param(Why what happened) }
    procedure LogState(const Why: string);
    { Puts the current choices in the title bar. }
    procedure UpdateTitle;
    { One line describing the current choices.
      @returns(the description) }
    function StateText: string;
    { Handles a key.
      @param(Key the virtual key code) }
    procedure KeyDown(Key: WPARAM);
    { Tells the taskbar the window is or is not full screen, as SRDemoFMX does.
      @param(Value @true for full screen) }
    procedure SetTaskbarMark(Value: Boolean);
    { Installs or removes the hold subclass.
      @param(Value @true to hold the window) }
    procedure SetHoldInstalled(Value: Boolean);
    { Writes a mark the owner asked for.
      @param(What @code(BROKEN) or @code(GOOD)) }
    procedure Mark(const What: string);
  public
    { Sets the defaults. }
    constructor Create;
    { Stops the bridge and frees everything. }
    destructor Destroy; override;
    { Runs the test until the window closes.
      @returns(the exit code) }
    function Run: Integer;
    { The window procedure's work.
      @param(Msg the message) @param(WParam its word parameter)
      @param(LParam its long parameter)
      @returns(the message's result) }
    function HandleMessage(Msg: UINT; WParam: WPARAM; LParam: LPARAM): LRESULT;
  end;

var
  { The one test, for @link(TestWndProc). }
  Test: TFullScreenTest = nil;

{ The window procedure: passes everything to @link(Test).
  @param(Wnd the window) @param(Msg the message)
  @param(WParam its word parameter) @param(LParam its long parameter)
  @returns(the message's result) }
function TestWndProc(Wnd: HWND; Msg: UINT; WParam: WPARAM; LParam: LPARAM): LRESULT; stdcall;
begin
  if (Test <> nil) and (Test.FWnd = Wnd) then
    Result := Test.HandleMessage(Msg, WParam, LParam)
  else
    Result := DefWindowProc(Wnd, Msg, WParam, LParam);
end;

{ A rectangle for the log.
  @param(R the rectangle)
  @returns(@code((left, top) width x height)) }
function RectText(const R: TRect): string;
begin
  Result := Format('(%d, %d) %d x %d', [R.Left, R.Top, R.Right - R.Left, R.Bottom - R.Top]);
end;

{ @code(SHQueryUserNotificationState)'s value as words.
  @param(State the value)
  @returns(its name) }
function NotifyStateName(State: Integer): string;
begin
  case State of
    1: Result := 'NOT_PRESENT (screen saver or locked)';
    2: Result := 'BUSY (a full-screen program is running)';
    3: Result := 'RUNNING_D3D_FULL_SCREEN (exclusive full screen)';
    4: Result := 'PRESENTATION_MODE';
    5: Result := 'ACCEPTS_NOTIFICATIONS (nothing full screen)';
    6: Result := 'QUIET_TIME';
    7: Result := 'APP (a Store app full screen)';
  else
    Result := 'unknown';
  end;
  Result := Format('%d %s', [State, Result]);
end;

{ The adapter choice as words.
  @param(Choice 0, 1 or 2)
  @returns(its description) }
function AdapterName(Choice: Integer): string;
begin
  case Choice of
    1: Result := 'default adapter';
    2: Result := 'adapter of the window''s monitor';
  else
    Result := 'most dedicated memory';
  end;
end;

{ TFullScreenTest }

constructor TFullScreenTest.Create;
begin
  inherited Create;
  FImage := TSRStereoImage.Create;
  FImageFiles := TStringList.Create;
  FImageIndex := -1;
  FLensOn := True;
  FNotifyState := -1;
  FForeground := -1;
  FViewsDirty := True;
  FClock := TStopwatch.StartNew;
end;

destructor TFullScreenTest.Destroy;
begin
  StopBridge;
  FImageFiles.Free;
  FImage.Free;
  inherited;
end;

procedure TFullScreenTest.ParseCommandLine;
var
  I, N: Integer;
  S, ImageName: string;
begin
  ImageName := '';
  for I := 1 to ParamCount do
  begin
    S := LowerCase(ParamStr(I));
    if (S <> '') and CharInSet(S[1], ['/', '-']) then
      Delete(S, 1, 1);
    if S = 'fs' then
      FFullScreen := True   // applied once the window is on the SR display
    else if S = 'window' then
      FWeaveOnWindow := True
    else if S = 'flip' then
      FFlipModel := True
    else if S = 'rec' then
      FRecommended := True
    else if S = 'reapply' then
      FReapplyInput := True
    else if S = 'lensoff' then
      FLensOn := False
    else if S.StartsWith('adapter=') and TryStrToInt(Copy(S, 9, MaxInt), N) then
      FAdapter := EnsureRange(N, 0, 2)
    else if S.StartsWith('parent=') and TryStrToInt(Copy(S, 8, MaxInt), N) then
      FParentChain := EnsureRange(N, 0, 2)
    else if S = 'rgba' then
      FRgba := True
    else if S = 'mark' then
      FMarkTaskbar := True
    else if S = 'hold' then
      FHold := True
    else if S = 'eyes' then
      FQueryEyes := True
    else if S.StartsWith('latency=') and TryStrToInt(Copy(S, 9, MaxInt), N) then
      FLatency := EnsureRange(N, 0, 4)
    else if S.StartsWith('image=') then
      ImageName := Copy(ParamStr(I), Pos('=', ParamStr(I)) + 1, MaxInt)
    else
      DiagLog('Unknown command-line switch: ' + ParamStr(I));
  end;
  if ImageName <> '' then
  begin
    FImageIndex := -1;
    for I := 0 to FImageFiles.Count - 1 do
      if SameText(ExtractFileName(FImageFiles[I]), ImageName) then
        FImageIndex := I;
    if FImageIndex < 0 then
      DiagLog('Image not found in media: ' + ImageName + '; showing the test pattern');
  end;
end;

procedure TFullScreenTest.FindImages;
var
  Dir, Media: string;
  Level: Integer;
  F: string;
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
  if Media = '' then
  begin
    DiagLog('No media folder found above the executable; only the test pattern');
    Exit;
  end;
  for F in TDirectory.GetFiles(Media) do
    if MatchText(ExtractFileExt(F), ['.png', '.jpg', '.jpeg', '.bmp']) then
      FImageFiles.Add(F);
  FImageFiles.Sort;
  DiagLog(Format('%d image(s) in %s', [FImageFiles.Count, Media]));
end;

procedure TFullScreenTest.LoadImage;
begin
  try
    if (FImageIndex >= 0) and (FImageIndex < FImageFiles.Count) then
      FImage.LoadFromFile(FImageFiles[FImageIndex])
    else
    begin
      FImageIndex := -1;
      FImage.MakeTestPattern(1920, 1080);
    end;
    DiagLog(Format('Image: %s, %d x %d', [FImage.Name, FImage.SourceWidth, FImage.SourceHeight]));
  except
    on E: Exception do
    begin
      DiagLog('Could not load the image: ' + E.Message + '; showing the test pattern');
      FImageIndex := -1;
      FImage.MakeTestPattern(1920, 1080);
    end;
  end;
  FViewsDirty := True;
end;

function TFullScreenTest.CreateTheWindow: Boolean;
var
  WC: TWndClassEx;
begin
  FillChar(WC, SizeOf(WC), 0);
  WC.cbSize := SizeOf(WC);
  WC.lpfnWndProc := @TestWndProc;
  WC.hInstance := HInstance;
  WC.hCursor := LoadCursor(0, IDC_ARROW);
  WC.lpszClassName := WindowClassName;
  if RegisterClassEx(WC) = 0 then
    DiagLog('RegisterClassEx failed: ' + SysErrorMessage(GetLastError));
  FWnd := CreateWindowEx(0, WindowClassName, AppTitle, WS_OVERLAPPEDWINDOW,
    Integer(CW_USEDEFAULT), Integer(CW_USEDEFAULT), 1280, 760, 0, 0, HInstance, nil);
  Result := FWnd <> 0;
  if not Result then
    DiagLog('CreateWindowEx failed: ' + SysErrorMessage(GetLastError));
end;

function TFullScreenTest.StateText: string;
var
  Views: string;
begin
  if FRecommended then
    Views := 'recommended views'
  else
    Views := 'window-size views';
  Result := Format('%s; weave into %s; FMX-like swap chain %s; %s; %s; %s; input %s; ' +
    'eye queries %s; latency %s; %s; taskbar mark %s; hold %s; lens %s; image %s',
    [IfThen(FFullScreen, 'FULL SCREEN', 'windowed'),
     IfThen(FWeaveOnWindow, 'this window', 'child window'),
     IfThen(FParentChain = 0, 'none', IfThen(FParentChain = 1, 'bitblt', 'flip')),
     AdapterName(FAdapter),
     IfThen(FFlipModel, 'flip model', 'bitblt'),
     Views,
     IfThen(FReapplyInput, 'every frame', 'on change'),
     IfThen(FQueryEyes, 'every frame (as SRDemoFMX)', 'none'),
     IfThen(FLatency = 0, 'SR default', IntToStr(FLatency) + ' frame(s)'),
     IfThen(FRgba, 'RGBA pixels', 'BGRA pixels'),
     IfThen(FMarkTaskbar, 'on', 'off'),
     IfThen(FHold, 'on', 'off'),
     IfThen(FLensOn, 'on', 'off'),
     FImage.Name]);
end;

procedure TFullScreenTest.LogState(const Why: string);
begin
  DiagLog(Why + ': ' + StateText);
  UpdateTitle;
end;

procedure TFullScreenTest.UpdateTitle;
begin
  if FWnd <> 0 then
    SetWindowText(FWnd, PChar(AppTitle + ' - ' + StateText +
      ' - F11 W A M V R P E K F T H L N, B/G mark'));
end;

procedure TFullScreenTest.StartBridge;
var
  RC: Integer;
  R: TSRBRect;
begin
  srb_SetVSync(1);
  if FFlipModel or FPresentModelSet then
  begin
    srb_SetPresentModel(Ord(FFlipModel));
    FPresentModelSet := True;
  end;
  if FHasNewOptions then
  begin
    srb_SetWeaverWindow(Ord(FWeaveOnWindow));
    srb_SetAdapterChoice(FAdapter);
    srb_SetReapplyInput(Ord(FReapplyInput));
  end;
  if FHasParentChain then
    srb_SetParentSwapChain(FParentChain);
  LogState('Starting the bridge');
  RC := srb_Initialize(Pointer(FWnd), InitTimeout);
  if RC <> SRB_OK then
  begin
    DiagLog(Format('srb_Initialize failed (%d): %s', [RC, SRBridgeLastError]));
    FRunning := False;
    Exit;
  end;
  FRunning := True;
  srb_SetLens(Ord(FLensOn));
  if FLatency > 0 then
  begin
    srb_SetLatencyInFrames(FLatency);
    FLatencySet := True;
  end;
  FSRRectKnown := srb_GetDisplayRect(R) = SRB_OK;
  if FSRRectKnown then
    FSRRect := Rect(R[0], R[1], R[2], R[3]);
  FInfoKnown := srb_GetDisplayInfo(@FInfo) = SRB_OK;
  if FInfoKnown then
    DiagLog(Format('SR display %d x %d px, %.1f x %.1f mm, recommended views %d x %d, at %s',
      [FInfo.resolutionWidth, FInfo.resolutionHeight, FInfo.physicalWidthMM,
       FInfo.physicalHeightMM, FInfo.recommendedViewWidth, FInfo.recommendedViewHeight,
       IfThen(FSRRectKnown, RectText(FSRRect), 'an unknown place')]));
  DiagLog('SR platform ' + UTF8ToString(srb_GetPlatformVersion));
  FBoundsW := 0;
  FBoundsH := 0;
  FViewsDirty := True;
end;

procedure TFullScreenTest.StopBridge;
begin
  if FRunning then
  begin
    DiagLog('Stopping the bridge');
    srb_Finalize;
    FRunning := False;
  end;
end;

function TFullScreenTest.PlaceOnSRDisplay: Boolean;
var
  WR: TRect;
  W, H, X, Y: Integer;
begin
  Result := False;
  if not FSRRectKnown then
    Exit;
  GetWindowRect(FWnd, WR);
  if FSRRect.Contains(CenterPoint(WR)) then
    Exit;
  W := (FSRRect.Width * 2) div 3;
  H := (FSRRect.Height * 2) div 3;
  X := FSRRect.Left + (FSRRect.Width - W) div 2;
  Y := FSRRect.Top + (FSRRect.Height - H) div 2;
  SetWindowPos(FWnd, 0, X, Y, W, H, SWP_NOZORDER or SWP_NOACTIVATE);
  GetWindowRect(FWnd, WR);
  DiagLog('Moved the window onto the SR display: ' + RectText(WR));
  Result := True;
end;

procedure TFullScreenTest.SetFullScreen(Value: Boolean);
var
  Style: NativeInt;
  MI: TMonitorInfo;
  Target, WR: TRect;
begin
  Style := GetWindowLongPtr(FWnd, GWL_STYLE);
  if Value then
  begin
    // Raymond Chen's method, as in Leia's examples/directx11_weaving
    if (Style and WS_OVERLAPPEDWINDOW) = 0 then
      Exit;
    FPlacement.length := SizeOf(FPlacement);
    GetWindowPlacement(FWnd, @FPlacement);
    if FSRRectKnown then
      Target := FSRRect
    else
    begin
      MI.cbSize := SizeOf(MI);
      GetMonitorInfo(MonitorFromWindow(FWnd, MONITOR_DEFAULTTONEAREST), @MI);
      Target := MI.rcMonitor;
    end;
    FFullScreenRect := Target;
    SetWindowLongPtr(FWnd, GWL_STYLE, Style and not NativeInt(WS_OVERLAPPEDWINDOW));
    SetWindowPos(FWnd, HWND_TOP, Target.Left, Target.Top, Target.Width, Target.Height,
      SWP_NOOWNERZORDER or SWP_FRAMECHANGED);
    FFullScreen := True;
    if FHold then
      SetHoldInstalled(True);
    if FMarkTaskbar then
      SetTaskbarMark(True);
    FFullScreenSinceMs := FClock.ElapsedMilliseconds;
    GetWindowRect(FWnd, WR);
    LogState(Format('Full screen ON, wanted %s, window %s', [RectText(Target), RectText(WR)]));
  end
  else
  begin
    if (Style and WS_OVERLAPPEDWINDOW) <> 0 then
      Exit;
    SetHoldInstalled(False);
    FFullScreen := False;
    if FMarked then
      SetTaskbarMark(False);
    SetWindowLongPtr(FWnd, GWL_STYLE, Style or NativeInt(WS_OVERLAPPEDWINDOW));
    SetWindowPlacement(FWnd, @FPlacement);
    SetWindowPos(FWnd, 0, 0, 0, 0, 0, SWP_NOMOVE or SWP_NOSIZE or SWP_NOZORDER or
      SWP_NOOWNERZORDER or SWP_FRAMECHANGED);
    FFullScreen := False;
    GetWindowRect(FWnd, WR);
    LogState(Format('Full screen OFF after %.1f s, window %s',
      [(FClock.ElapsedMilliseconds - FFullScreenSinceMs) / 1000, RectText(WR)]));
  end;
end;

procedure TFullScreenTest.SetTaskbarMark(Value: Boolean);
var
  TaskBar: ITaskbarList2;
  HR: HRESULT;
begin
  try
    TaskBar := CreateComObject(CLSID_TaskbarList) as ITaskbarList2;
    HR := TaskBar.HrInit;
    if Succeeded(HR) then
      HR := TaskBar.MarkFullscreenWindow(FWnd, Value);
    if Succeeded(HR) then
    begin
      FMarked := Value;
      DiagLog(IfThen(Value, 'Taskbar told the window is full screen',
        'Taskbar told the window is no longer full screen'));
    end
    else
      DiagLog(Format('ITaskbarList2 failed, HRESULT $%.8x', [Cardinal(HR)]));
  except
    on E: Exception do
      DiagLog('ITaskbarList2 not available: ' + E.Message);
  end;
end;

{ Holds a full-screen window at the full-screen rectangle, as SRDemoFMX's
  renderer does: any move or size is rewritten before it happens.
  @param(Wnd the window) @param(Msg the message) @param(WP wParam)
  @param(LP lParam) @param(IdSubclass our id) @param(RefData the test)
  @returns(the result of the next window procedure) }
function HoldWindowProc(Wnd: HWND; Msg: UINT; WP: WPARAM; LP: LPARAM;
  IdSubclass: UIntPtr; RefData: UIntPtr): LRESULT; stdcall;
var
  T: TFullScreenTest;
  Pos: PWindowPos;
begin
  if Msg = MsgWindowPosChanging then
  begin
    T := TFullScreenTest(RefData);
    Pos := PWindowPos(LP);
    if (T <> nil) and T.FFullScreen and not T.FFullScreenRect.IsEmpty then
      with T.FFullScreenRect do
        if ((Pos.flags and SWP_NOMOVE) = 0) and ((Pos.x <> Left) or (Pos.y <> Top)) or
           ((Pos.flags and SWP_NOSIZE) = 0) and ((Pos.cx <> Width) or (Pos.cy <> Height)) then
        begin
          Inc(T.FHoldCorrections);
          Pos.x := Left;
          Pos.y := Top;
          Pos.cx := Width;
          Pos.cy := Height;
        end;
  end;
  Result := DefSubclassProc(Wnd, Msg, WP, LP);
end;

procedure TFullScreenTest.SetHoldInstalled(Value: Boolean);
begin
  if Value = FHoldInstalled then
    Exit;
  if Value then
  begin
    FHoldInstalled := SetWindowSubclass(FWnd, HoldWindowProc, HoldSubclassId, UIntPtr(Self));
    DiagLog(IfThen(FHoldInstalled, 'Hold installed', Format('Hold NOT installed (error %d)',
      [GetLastError])));
  end
  else
  begin
    RemoveWindowSubclass(FWnd, HoldWindowProc, HoldSubclassId);
    FHoldInstalled := False;
    DiagLog('Hold removed');
  end;
end;

procedure TFullScreenTest.Mark(const What: string);
begin
  Inc(FMarks);
  if FFullScreen then
    DiagLog(Format('MARK %d: %s (owner), %.1f s after full screen came on; %s',
      [FMarks, What, (FClock.ElapsedMilliseconds - FFullScreenSinceMs) / 1000, StateText]))
  else
    DiagLog(Format('MARK %d: %s (owner), windowed; %s', [FMarks, What, StateText]));
end;

procedure TFullScreenTest.KeyDown(Key: WPARAM);

  { Asks for a bridge restart, or says the bridge is too old.
    @param(Option what changed) }
  procedure NeedRestart(const Option: string);
  begin
    FRestartPending := True;
    LogState(Option + ' changed; restarting the bridge');
  end;

  { Checks the bridge has the new options, logging if not.
    @returns(@true if it has them) }
  function HaveNewOptions: Boolean;
  begin
    Result := FHasNewOptions;
    if not Result then
      DiagLog('This SRBridge.dll is older than 5 November 2026: W, A and R need the ' +
        'rebuilt bridge');
  end;

begin
  case Integer(Key) of
    VK_F11:
      SetFullScreen(not FFullScreen);
    VK_ESCAPE:
      if FFullScreen then
        SetFullScreen(False);
    Ord('W'):
      if HaveNewOptions then
      begin
        FWeaveOnWindow := not FWeaveOnWindow;
        NeedRestart('Weaver window');
      end;
    Ord('A'):
      if HaveNewOptions then
      begin
        FAdapter := (FAdapter + 1) mod 3;
        NeedRestart('Adapter');
      end;
    Ord('M'):
      begin
        FFlipModel := not FFlipModel;
        NeedRestart('Swap chain model');
      end;
    Ord('P'):
      if not FHasParentChain then
        DiagLog('This SRBridge.dll has no srb_SetParentSwapChain: P needs the bridge ' +
          'built after 5 November 2026, 03:00')
      else
      begin
        FParentChain := (FParentChain + 1) mod 3;
        if FWeaveOnWindow and (FParentChain > 0) then
          DiagLog('The FMX-like swap chain only applies with the child window (W off)');
        NeedRestart('FMX-like swap chain');
      end;
    Ord('F'):
      begin
        FRgba := not FRgba;
        FViewsDirty := True;
        LogState('Pixel format changed');
      end;
    Ord('T'):
      begin
        FMarkTaskbar := not FMarkTaskbar;
        if FFullScreen then
          SetTaskbarMark(FMarkTaskbar);
        LogState('Taskbar mark changed');
      end;
    Ord('H'):
      begin
        FHold := not FHold;
        if FFullScreen then
          SetHoldInstalled(FHold);
        LogState('Hold changed');
      end;
    Ord('E'):
      begin
        FQueryEyes := not FQueryEyes;
        LogState('Eye queries changed');
      end;
    Ord('K'):
      begin
        FLatency := (FLatency + 1) mod 5;
        if FLatency > 0 then
        begin
          if FRunning then
            srb_SetLatencyInFrames(FLatency);
          FLatencySet := True;
          LogState('Latency changed');
        end
        else if FLatencySet then
          NeedRestart('Latency back to SR''s default (the weaver keeps the last value until)')
        else
          LogState('Latency changed');
      end;
    Ord('V'):
      begin
        FRecommended := not FRecommended;
        FViewsDirty := True;
        LogState('View size changed');
      end;
    Ord('R'):
      if HaveNewOptions then
      begin
        FReapplyInput := not FReapplyInput;
        srb_SetReapplyInput(Ord(FReapplyInput));
        LogState('Weaver input changed');
      end;
    Ord('L'):
      begin
        FLensOn := not FLensOn;
        if FRunning then
          srb_SetLens(Ord(FLensOn));
        LogState('Lens changed');
      end;
    Ord('N'):
      begin
        Inc(FImageIndex);
        if FImageIndex >= FImageFiles.Count then
          FImageIndex := -1;
        LoadImage;
        LogState('Image changed');
      end;
    Ord('B'):
      Mark('BROKEN');
    Ord('G'):
      Mark('GOOD');
  end;
end;

function TFullScreenTest.HandleMessage(Msg: UINT; WParam: WPARAM; LParam: LPARAM): LRESULT;
var
  Suggested: PRect;
begin
  Result := 0;
  case Msg of
    WM_KEYDOWN:
      if (LParam and (1 shl 30)) = 0 then   // not auto-repeat
        KeyDown(WParam);
    WM_ERASEBKGND:
      Result := 1;   // the swap chain covers the window; GDI must not paint over it
    WM_PAINT:
      ValidateRect(FWnd, nil);
    MsgDpiChanged:
      begin
        Suggested := PRect(LParam);
        DiagLog(Format('WM_DPICHANGED: %d dpi, suggested %s%s', [LoWord(WParam),
          RectText(Suggested^), IfThen(FFullScreen, ', ignored (full screen)', '')]));
        if not FFullScreen then
          SetWindowPos(FWnd, 0, Suggested.Left, Suggested.Top, Suggested.Width,
            Suggested.Height, SWP_NOZORDER or SWP_NOACTIVATE);
      end;
    WM_DESTROY:
      begin
        FQuit := True;
        PostQuitMessage(0);
      end;
  else
    Result := DefWindowProc(FWnd, Msg, WParam, LParam);
  end;
end;

procedure TFullScreenTest.Frame;
var
  CR: TRect;
  W, H, VW, VH, RC: Integer;
  T0: Int64;
  Cx, Cy, Wmm, Hmm: Double;
  P: PByte;
  I, Fmt: Integer;
  B: Byte;
begin
  if FRestartPending then
  begin
    FRestartPending := False;
    StopBridge;
    StartBridge;
  end;
  if not FRunning then
  begin
    Sleep(50);
    Exit;
  end;

  GetClientRect(FWnd, CR);
  W := CR.Right - CR.Left;
  H := CR.Bottom - CR.Top;
  if IsIconic(FWnd) or (W < 1) or (H < 1) then
  begin
    Sleep(20);
    Exit;
  end;
  if (W <> FBoundsW) or (H <> FBoundsH) then
  begin
    RC := srb_SetBounds(0, 0, W, H);
    DiagLog(Format('Client %d x %d (was %d x %d), srb_SetBounds %d', [W, H, FBoundsW, FBoundsH, RC]));
    FBoundsW := W;
    FBoundsH := H;
  end;

  if FRecommended and FInfoKnown and (FInfo.recommendedViewWidth > 0) and
    (FInfo.recommendedViewHeight > 0) then
  begin
    VW := FInfo.recommendedViewWidth;
    VH := FInfo.recommendedViewHeight;
  end
  else
  begin
    VW := W;
    VH := H;
  end;
  if FViewsDirty or (VW <> FViewW) or (VH <> FViewH) then
  begin
    T0 := FClock.ElapsedMilliseconds;
    FImage.RenderViews(VW, VH, FPixels);
    if FRgba then
    begin
      // Swap blue and red: the same picture, as RGBA bytes
      P := @FPixels[0];
      for I := 0 to (Length(FPixels) div 4) - 1 do
      begin
        B := P[0];
        P[0] := P[2];
        P[2] := B;
        Inc(P, 4);
      end;
    end;
    FViewW := VW;
    FViewH := VH;
    FViewsDirty := False;
    DiagLog(Format('Views %d x %d each (%s), made in %d ms', [VW, VH,
      IfThen(FRecommended, 'recommended', 'window size'), FClock.ElapsedMilliseconds - T0]));
  end;

  if FQueryEyes then
  begin
    // What SRDemoFMX's renderer asks for every frame, before rendering
    if srb_GetEyePositions(FLastEyes[0], FLastEyes[1]) = SRB_OK then
      Inc(FEyeQueries);
    srb_GetWindowRectMM(Cx, Cy, Wmm, Hmm);
  end;

  if FRgba then
    Fmt := SRB_FMT_RGBA8
  else
    Fmt := SRB_FMT_BGRA8;
  RC := srb_SubmitViews(@FPixels[0], FViewW, FViewH, FViewW * 8, Fmt);
  case RC of
    SRB_OK: Inc(FResults[0]);
    SRB_S_2D_FALLBACK: Inc(FResults[1]);
    SRB_S_OCCLUDED:
      begin
        Inc(FResults[2]);
        Sleep(10);
      end;
  else
    Inc(FResults[3]);
  end;
  Inc(FFramesSinceLog);
  Watch;
end;

procedure TFullScreenTest.Watch;
var
  WR: TRect;
  NowMs: Int64;
  State, Fg: Integer;
  Ev: TSRBSystemEvent;
  Stats: TSRBStats;
  Secs: Double;
begin
  GetWindowRect(FWnd, WR);
  if WR <> FLastWindowRect then
  begin
    DiagLog('Window ' + RectText(WR) + IfThen(FFullScreen and FSRRectKnown and (WR <> FSRRect),
      ' - NOT the SR display''s ' + RectText(FSRRect), ''));
    FLastWindowRect := WR;
  end;

  NowMs := FClock.ElapsedMilliseconds;
  if NowMs - FLastNotifyMs >= 250 then
  begin
    FLastNotifyMs := NowMs;
    if SRTSHQueryUserNotificationState(State) = S_OK then
      if State <> FNotifyState then
      begin
        DiagLog(Format('Windows notification state: %s%s', [NotifyStateName(State),
          IfThen(FFullScreen, Format(', %.1f s after full screen came on',
            [(NowMs - FFullScreenSinceMs) / 1000]), '')]));
        FNotifyState := State;
      end;
    Fg := Ord(GetForegroundWindow = FWnd);
    if Fg <> FForeground then
    begin
      DiagLog(IfThen(Fg = 1, 'This window is in the foreground',
        'Another window is in the foreground'));
      FForeground := Fg;
    end;
  end;

  while srb_PollSystemEvent(@Ev) = 1 do
    DiagLog(Format('SR event %d: %s', [Int64(Ev.eventType), UTF8ToString(PAnsiChar(@Ev.message[0]))]));

  if NowMs - FLastLogMs >= 1000 then
  begin
    Secs := (NowMs - FLastLogMs) / 1000;
    FillChar(Stats, SizeOf(Stats), 0);
    srb_GetStats(@Stats);
    DiagLog(Format('%.0f fps%s; woven %d, 2D %d, occluded %d, errors %d; back buffer %d x %d, ' +
      'views %d x %d, weaving %d, latency %d us, last Present $%.8x',
      [FFramesSinceLog / Secs,
       IfThen(FFullScreen, Format(' FULL SCREEN %.0f s', [(NowMs - FFullScreenSinceMs) / 1000]), ''),
       FResults[0], FResults[1], FResults[2], FResults[3],
       Stats.backBufferWidth, Stats.backBufferHeight, Stats.viewWidth, Stats.viewHeight,
       Stats.weaving, Int64(Stats.weaverLatencyUs), Cardinal(Stats.lastPresentHr)]));
    if FQueryEyes then
      DiagLog(Format('  eyes queried %d time(s): L(%.0f, %.0f, %.0f) R(%.0f, %.0f, %.0f) mm',
        [FEyeQueries, FLastEyes[0][0], FLastEyes[0][1], FLastEyes[0][2],
         FLastEyes[1][0], FLastEyes[1][1], FLastEyes[1][2]]));
    if FHoldCorrections > 0 then
      DiagLog(Format('  hold corrected %d move(s) or size(s)', [FHoldCorrections]));
    FHoldCorrections := 0;
    FEyeQueries := 0;
    FLastLogMs := NowMs;
    FFramesSinceLog := 0;
    FillChar(FResults, SizeOf(FResults), 0);
  end;
end;

function TFullScreenTest.Run: Integer;
var
  Msg: TMsg;
  WantFullScreen: Boolean;
begin
  Result := 0;
  try
    if SRTSetProcessDpiAwarenessContext(DpiPerMonitorV2) then
      DiagLog('DPI awareness set to Per-Monitor v2 here (the manifest had not set it)')
    else
      DiagLog('DPI awareness already set (by the manifest)');
  except
    on E: Exception do
      DiagLog('SetProcessDpiAwarenessContext not available: ' + E.Message);
  end;
  CoInitializeEx(nil, COINIT_APARTMENTTHREADED);
  try
    FindImages;
    ParseCommandLine;
    WantFullScreen := FFullScreen;
    FFullScreen := False;
    LoadImage;
    if not CreateTheWindow then
      Exit(1);

    if not SRBridgeAvailable then
    begin
      DiagLog('Bridge not available: ' + SRBridgeLastError);
      MessageBox(FWnd, PChar(SRBridgeLastError), AppTitle, MB_ICONERROR);
      DestroyWindow(FWnd);
      Exit(1);
    end;
    DiagLogAttachBridge;
    FHasNewOptions := SRBridgeHasExport(NewOptionsExport);
    FHasParentChain := SRBridgeHasExport(ParentChainExport);
    if not FHasParentChain then
      FParentChain := 0;
    if not FHasNewOptions then
    begin
      DiagLog('This SRBridge.dll is older than 5 November 2026: it always weaves into ' +
        'its child window, picks the adapter with the most memory and gives the weaver its ' +
        'input only on change');
      FWeaveOnWindow := False;
      FAdapter := 0;
      FReapplyInput := False;
    end;
    DiagLog('Keys: F11 full screen, Esc leave it; W weave into this window / child window; ' +
      'A adapter; M bitblt / flip model; V window-size / recommended views; R weaver input ' +
      'every frame; P FMX-like swap chain none / bitblt / flip; E eye queries as SRDemoFMX; ' +
      'K latency; F RGBA pixels; T taskbar mark; H hold; L lens; N next image; ' +
      'B mark broken, G mark good');

    ShowWindow(FWnd, SW_SHOWNORMAL);
    UpdateWindow(FWnd);
    StartBridge;
    if PlaceOnSRDisplay and FRunning and (FAdapter = 2) then
    begin
      DiagLog('Restarting the bridge so it picks the SR display''s adapter');
      StopBridge;
      StartBridge;
    end;
    try
      DiagLog(Format('Window DPI %d', [SRTGetDpiForWindow(FWnd)]));
    except
      on E: Exception do
        DiagLog('GetDpiForWindow not available: ' + E.Message);
    end;
    if WantFullScreen then
      SetFullScreen(True)
    else
      UpdateTitle;

    while not FQuit do
    begin
      while PeekMessage(Msg, 0, 0, 0, PM_REMOVE) do
      begin
        if Msg.message = WM_QUIT then
        begin
          FQuit := True;
          Break;
        end;
        TranslateMessage(Msg);
        DispatchMessage(Msg);
      end;
      if FQuit then
        Break;
      Frame;
    end;
    DiagLog('Window closed');
    StopBridge;
  finally
    CoUninitialize;
  end;
end;

function RunFullScreenTest: Integer;
begin
  Test := TFullScreenTest.Create;
  try
    Result := Test.Run;
  finally
    FreeAndNil(Test);
  end;
end;

end.

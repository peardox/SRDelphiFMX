{ @abstract(What went wrong when LeiaSR was started, and the dialog that asks
  the user what to do about it.)

  When SR cannot start, or would only run very badly (FMX drawing in
  software or on a GPU that does not drive the SR display), the program
  carries on without glasses-free 3D by default: a 3D scene is still drawn,
  as an ordinary 3D view on a flat screen, but not woven for the SR display.
  @link(AskStartProblem) offers the user three ways on: continue without
  glasses-free 3D, try again, or (where it would run at all) use
  glasses-free 3D anyway, very slowly; or exit, to fix the SR set-up first. It is a Windows task dialog, modal and
  centred on the program's window, with a message box as the fallback where
  task dialogs are not available. No FMX or VCL: any program can use it. }
unit SRStartProblem;

interface

type
  { Why LeiaSR was not started, or was stopped again straight away. }
  TSRStartProblem = (
    { No problem. }
    spNone,
    { The LeiaSR runtime is not installed: this computer has no SR. Not an
      error; the renderer says nothing to the user about it. }
    spNotInstalled,
    { @code(SRBridge.dll) could not be loaded. }
    spBridgeMissing,
    { The LeiaSR runtime is installed but its service is not running. }
    spNoService,
    { The SR service is running but no SR display was found (unplugged,
      switched off, or not at its native resolution). }
    spNoDisplay,
    { LeiaSR itself would not start for another reason (or, with a bridge
      older than its quick check, no service or display in time). }
    spStartFailed,
    { The program draws in software (WARP), not on a GPU. }
    spSoftwareGpu,
    { The program draws on a different GPU from the one that drives the SR
      display, so every frame crosses between GPUs. }
    spWrongGpu,
    { FMX is not drawing with Direct3D 11, so every frame goes through the
      CPU and the GPU cannot be checked. }
    spNotDX11);

  { What to do after a start problem. }
  TSRStartChoice = (
    { Leave LeiaSR off: no glasses-free 3D, so a 3D scene is shown as an
      ordinary view on a flat screen. The default. }
    scContinueWithoutSR,
    { Start LeiaSR again (useful once the cause is fixed, such as the
      display plugged in or the SR service started). }
    scRetry,
    { Run LeiaSR anyway, with the problem: only offered when it would run at
      all, and it will be very slow. }
    scContinueDegraded,
    { Close the program, so the SR set-up can be fixed (the SR service
      started, the display plugged in, the GPU setting changed) before it is
      started again. }
    scExit);

{ The problem as a few words, for logs and status lines.
  @param(Problem the problem)
  @returns(its name) }
function StartProblemName(Problem: TSRStartProblem): string;

{ The dialog's heading for a problem.
  @param(Problem the problem)
  @returns(one sentence) }
function StartProblemHeading(Problem: TSRStartProblem): string;

{ Asks the user what to do about a start problem, in a modal dialog centred
  on the owner window. Escape or closing the dialog chooses
  @link(scContinueWithoutSR).
  @param(Owner the window that owns the dialog (the form's HWND), 0 for none)
  @param(AppName the program's name, for the title bar)
  @param(Problem what went wrong)
  @param(Msg the details, for the user)
  @param(CanDegrade whether to offer @link(scContinueDegraded); @link(scExit)
    is always offered)
  @param(FixText if not empty, a check box with this text (such as an offer
    to set the high-performance GPU), unticked)
  @param(FixChecked receives whether that check box was ticked)
  @returns(the user's choice) }
function AskStartProblem(Owner: NativeUInt; const AppName: string; Problem: TSRStartProblem;
  const Msg: string; CanDegrade: Boolean; const FixText: string;
  out FixChecked: Boolean): TSRStartChoice;

implementation

uses
  Winapi.Windows, System.SysUtils;

type
  { One custom button: TASKDIALOG_BUTTON, packed as in commctrl.h. }
  TTaskDlgButton = packed record
    { The value the dialog returns for it. }
    nButtonID: Integer;
    { Its text; for a command link, the first line is the label and the rest
      the note under it. }
    pszButtonText: PWideChar;
  end;

  { TASKDIALOGCONFIG, packed as in commctrl.h; the icon unions are given as
    their string-pointer members. Declared here so the layout does not
    depend on the RTL's declaration. }
  TTaskDlgConfig = packed record
    cbSize: Cardinal;
    hwndParent: HWND;
    hInstance: HINST;
    dwFlags: Cardinal;
    dwCommonButtons: Cardinal;
    pszWindowTitle: PWideChar;
    pszMainIcon: PWideChar;
    pszMainInstruction: PWideChar;
    pszContent: PWideChar;
    cButtons: Cardinal;
    pButtons: Pointer;
    nDefaultButton: Integer;
    cRadioButtons: Cardinal;
    pRadioButtons: Pointer;
    nDefaultRadioButton: Integer;
    pszVerificationText: PWideChar;
    pszExpandedInformation: PWideChar;
    pszExpandedControlText: PWideChar;
    pszCollapsedControlText: PWideChar;
    pszFooterIcon: PWideChar;
    pszFooter: PWideChar;
    pfCallback: Pointer;
    lpCallbackData: NativeInt;
    cxWidth: Cardinal;
  end;

  { comctl32's TaskDialogIndirect (version 6 only). }
  TTaskDialogIndirectFunc = function(const Config: TTaskDlgConfig; pnButton,
    pnRadioButton: PInteger; pfVerificationFlagChecked: PBOOL): HRESULT; stdcall;

const
  { Task dialog flag: Escape and the close button cancel. }
  TDF_ALLOW_DIALOG_CANCELLATION = $0008;
  { Task dialog flag: show the custom buttons as command links. }
  TDF_USE_COMMAND_LINKS = $0010;
  { Task dialog flag: centre on the owner window, not its monitor. }
  TDF_POSITION_RELATIVE_TO_WINDOW = $1000;
  { Task dialog: the warning icon (MAKEINTRESOURCEW(-1)). }
  TD_WARNING_ICON = PWideChar($FFFF);
  { Task dialog: the error icon (MAKEINTRESOURCEW(-2)). }
  TD_ERROR_ICON = PWideChar($FFFE);

  { Button ID: continue without glasses-free 3D. }
  BtnWithout = 101;
  { Button ID: try again. }
  BtnRetry = 102;
  { Button ID: use glasses-free 3D anyway. }
  BtnDegraded = 103;
  { Button ID: exit. }
  BtnExit = 104;
  { MessageBox: Abort, Retry and Ignore buttons. }
  MB_ABORTRETRYIGNORE_ = $00000002;

  { MessageBox: Cancel, Try Again and Continue buttons. }
  MB_CANCELTRYCONTINUE_ = $00000006;
  { MessageBox: the Try Again button. }
  IDTRYAGAIN_ = 10;
  { MessageBox: the Continue button. }
  IDCONTINUE_ = 11;

function StartProblemName(Problem: TSRStartProblem): string;
begin
  case Problem of
    spNone: Result := 'no problem';
    spNotInstalled: Result := 'LeiaSR not installed';
    spBridgeMissing: Result := 'SRBridge.dll missing';
    spNoService: Result := 'SR service not running';
    spNoDisplay: Result := 'no SR display';
    spStartFailed: Result := 'LeiaSR would not start';
    spSoftwareGpu: Result := 'drawing in software';
    spWrongGpu: Result := 'drawing on the wrong GPU';
    spNotDX11: Result := 'FMX not on Direct3D 11';
  else
    Result := 'unknown problem';
  end;
end;

function StartProblemHeading(Problem: TSRStartProblem): string;
begin
  case Problem of
    spNotInstalled:
      Result := 'Glasses-free 3D (LeiaSR) is not installed on this computer.';
    spBridgeMissing, spNoService, spNoDisplay, spStartFailed:
      Result := 'Glasses-free 3D (LeiaSR) could not be started.';
    spSoftwareGpu, spWrongGpu, spNotDX11:
      Result := 'Glasses-free 3D (LeiaSR) has been turned off: on this computer, as it is set up, it ' +
        'would run very slowly.';
  else
    Result := 'Glasses-free 3D (LeiaSR) is off.';
  end;
end;

{ The message box used where task dialogs are not available (no common
  controls 6 manifest). Centred on the owner's monitor, not the owner. A
  message box has at most three buttons, so with CanDegrade there is no
  Exit (the user can still close the program). }
function AskWithMessageBox(Owner: NativeUInt; const AppName, Heading, Msg: string;
  CanDegrade: Boolean; const FixText: string; out FixChecked: Boolean): TSRStartChoice;
var
  Text: string;
  Answer: Integer;
  Buttons: UINT;
begin
  FixChecked := False;
  Text := Heading + sLineBreak + sLineBreak + Msg + sLineBreak + sLineBreak;
  if CanDegrade then
    Text := Text + 'Cancel: continue without glasses-free 3D.' + sLineBreak +
      'Try Again: start glasses-free 3D again.' + sLineBreak +
      'Continue: use glasses-free 3D anyway (very slow).'
  else
    Text := Text + 'Abort: exit, to fix the SR set-up.' + sLineBreak +
      'Retry: start glasses-free 3D again.' + sLineBreak +
      'Ignore: continue without glasses-free 3D.';
  if CanDegrade then
    Buttons := MB_CANCELTRYCONTINUE_
  else
    Buttons := MB_ABORTRETRYIGNORE_;
  Answer := MessageBoxW(HWND(Owner), PChar(Text), PChar(AppName),
    Buttons or MB_ICONWARNING or MB_SETFOREGROUND);
  case Answer of
    IDRETRY, IDTRYAGAIN_: Result := scRetry;
    IDCONTINUE_: Result := scContinueDegraded;
    IDABORT: Result := scExit;
  else
    Result := scContinueWithoutSR;
  end;
  if (Result in [scContinueWithoutSR, scContinueDegraded, scExit]) and (FixText <> '') then
    FixChecked := MessageBoxW(HWND(Owner), PChar(FixText + '?'), PChar(AppName),
      MB_YESNO or MB_ICONQUESTION or MB_SETFOREGROUND) = IDYES;
end;

function AskStartProblem(Owner: NativeUInt; const AppName: string; Problem: TSRStartProblem;
  const Msg: string; CanDegrade: Boolean; const FixText: string;
  out FixChecked: Boolean): TSRStartChoice;
var
  Lib: HMODULE;
  TaskDialogIndirect: TTaskDialogIndirectFunc;
  Config: TTaskDlgConfig;
  Buttons: array[0..3] of TTaskDlgButton;
  TextWithout, TextRetry, TextDegraded, TextExit, Title, Heading: string;
  Count, Pressed: Integer;
  Checked: BOOL;
begin
  FixChecked := False;
  Heading := StartProblemHeading(Problem);
  // Version 6 of comctl32 (the one the program's manifest asks for) is the
  // one already loaded; version 5 has no task dialogs
  Lib := GetModuleHandle('comctl32.dll');
  if Lib = 0 then
    Lib := LoadLibrary('comctl32.dll');
  @TaskDialogIndirect := nil;
  if Lib <> 0 then
    @TaskDialogIndirect := GetProcAddress(Lib, 'TaskDialogIndirect');
  if not Assigned(TaskDialogIndirect) then
    Exit(AskWithMessageBox(Owner, AppName, Heading, Msg, CanDegrade, FixText, FixChecked));

  Title := AppName;
  TextWithout := 'Continue without glasses-free 3D' + #10 +
    'The program works normally. 3D scenes are shown as on any other screen; stereo images ' +
    'show the left eye''s view.';
  TextRetry := 'Try again' + #10 +
    'Start glasses-free 3D again. This only helps once the cause is fixed.';
  TextDegraded := 'Use glasses-free 3D anyway' + #10 +
    'It will be very slow and may misbehave, and the rest of the program slows down with it.';
  TextExit := 'Exit ' + AppName + #10 +
    'Close it now, fix the SR set-up (for example start the SR service, plug the display in ' +
    'or change the GPU setting), then start it again.';
  Count := 0;
  Buttons[Count].nButtonID := BtnWithout;
  Buttons[Count].pszButtonText := PChar(TextWithout);
  Inc(Count);
  Buttons[Count].nButtonID := BtnRetry;
  Buttons[Count].pszButtonText := PChar(TextRetry);
  Inc(Count);
  if CanDegrade then
  begin
    Buttons[Count].nButtonID := BtnDegraded;
    Buttons[Count].pszButtonText := PChar(TextDegraded);
    Inc(Count);
  end;
  Buttons[Count].nButtonID := BtnExit;
  Buttons[Count].pszButtonText := PChar(TextExit);
  Inc(Count);

  FillChar(Config, SizeOf(Config), 0);
  Config.cbSize := SizeOf(Config);
  Config.hwndParent := HWND(Owner);
  Config.hInstance := HInstance;
  Config.dwFlags := TDF_ALLOW_DIALOG_CANCELLATION or TDF_USE_COMMAND_LINKS;
  if Owner <> 0 then
    Config.dwFlags := Config.dwFlags or TDF_POSITION_RELATIVE_TO_WINDOW;
  Config.pszWindowTitle := PChar(Title);
  if Problem in [spBridgeMissing, spNoService, spNoDisplay, spStartFailed] then
    Config.pszMainIcon := TD_ERROR_ICON
  else
    Config.pszMainIcon := TD_WARNING_ICON;
  Config.pszMainInstruction := PChar(Heading);
  Config.pszContent := PChar(Msg);
  Config.cButtons := Count;
  Config.pButtons := @Buttons[0];
  Config.nDefaultButton := BtnWithout;
  if FixText <> '' then
    Config.pszVerificationText := PChar(FixText);

  Pressed := 0;
  Checked := False;
  if Failed(TaskDialogIndirect(Config, @Pressed, nil, @Checked)) then
    Exit(AskWithMessageBox(Owner, AppName, Heading, Msg, CanDegrade, FixText, FixChecked));
  FixChecked := (FixText <> '') and Checked;
  case Pressed of
    BtnRetry: Result := scRetry;
    BtnDegraded: Result := scContinueDegraded;
    BtnExit: Result := scExit;
  else
    Result := scContinueWithoutSR;   // its own button, Escape or the close button
  end;
end;

end.

{ @abstract(LenticularDemoFMX: a test scene shown on an eye-tracked lenticular 3D display.)

  @unorderedList(
    @item(@link(MainForm) holds the main window, the scene and the log.)
    @item(@link(Lenticular.StereoViewport) in @code(lib) shows the viewport on the
      3D display, through @link(LenticularBridge.Api) and the bridge DLL in
      @code(dll), copied beside the executable after each build.)
    @item(@link(Lenticular.Settings) in @code(lib) keeps the eye separation and the
      demo's choices in @code(%APPDATA%\Peardox\LenticularDemos.json), with
      the RTL's System.JSON.)
    @item(@link(Lenticular.DiagLog) in @code(lib) writes @code(LenticularDemoFMX.log) beside the
      executable, line by line, and records native crashes in it. Logs from
      earlier runs are moved into @code(oldlogs) beside it.)
    @item(FastMM5 (a submodule in @code(FastMM5)) is the memory manager. In
      Debug builds it runs in full debug mode when
      @code(FastMM_FullDebugMode64.dll) is beside the executable (the build
      copies it there), and writes @code(LenticularDemoFMX_FastMM.log).)
  )

  The @code(/warp) switch makes FMX draw in software, to test the GPU
  warning (@link(TLenticularStereoRenderer.OnGpuWarning)) on any machine.

  Build for Windows 64-bit; the display runtime is 64-bit only. }
program LenticularDemoFMX;

uses
  FastMM5 in '..\FastMM5\FastMM5.pas',
  System.StartUpCopy,
  System.SysUtils,
  FMX.Types,
  FMX.Forms,
  Lenticular.DiagLog in '..\lib\Lenticular.DiagLog.pas',
  Lenticular.Settings in '..\lib\Lenticular.Settings.pas',
  MainForm in 'ui\MainForm.pas' {frmMain},
  Lenticular.StereoViewport in '..\lib\Lenticular.StereoViewport.pas',
  LenticularBridge.Api in '..\lib\LenticularBridge.Api.pas',
  Lenticular.GpuPreference in '..\lib\Lenticular.GpuPreference.pas',
  Lenticular.StartProblem in '..\lib\Lenticular.StartProblem.pas',
  Lenticular.SettingsDialog in '..\lib\Lenticular.SettingsDialog.pas';

{$R *.res}

var
  { Path of FastMM5's event log; must live as long as the program, because
    FastMM keeps the pointer. }
  FastMMLogName: string;

begin
  DiagLogOpen(ChangeFileExt(ParamStr(0), '.log'));
  DiagLogInstallCrashHandlers;

  FastMMLogName := ChangeFileExt(ParamStr(0), '_FastMM.log');
  FastMM_SetEventLogFilename(PWideChar(FastMMLogName));
  DiagLogArchive(FastMMLogName);   // into oldlogs, like LenticularDemoFMX.log
  if FastMM_DebugModeActive then
    DiagLog('FastMM5 full debug mode ON; its events go to ' + FastMMLogName)
  else
  begin
    // Say exactly which of the two conditions is missing
{$IFDEF FastMM_FullDebugModeWhenDLLAvailable}
    if FileExists(ExtractFilePath(ParamStr(0)) + 'FastMM_FullDebugMode64.dll') then
      DiagLog('FastMM5 full debug mode off: FastMM_FullDebugMode64.dll is beside the ' +
        'executable but did not load')
    else
      DiagLog('FastMM5 full debug mode off: FastMM_FullDebugMode64.dll is not beside the ' +
        'executable (the post-build step copies it from FastMM5\FullDebugMode DLL\Precompiled)');
{$ELSE}
    DiagLog('FastMM5 full debug mode off: FastMM_FullDebugModeWhenDLLAvailable was not ' +
      'defined when FastMM5.pas was compiled (a Release build, or a Compile rather than a ' +
      'Build after the project options changed)');
{$ENDIF}
  end;

  // Test switch: make FMX draw in software (WARP), so the GPU warning can be
  // seen on any machine
  if FindCmdLineSwitch('warp') then
  begin
    GlobalUseDXSoftware := True;
    DiagLog('/warp: FMX will draw in software (GlobalUseDXSoftware), to test the GPU warning');
  end;

  Application.Initialize;
  Application.CreateForm(TfrmMain, frmMain);
  Application.Run;
  DiagLog('Application.Run returned normally');
end.

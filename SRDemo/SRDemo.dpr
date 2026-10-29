{ @abstract(SRDemo: a test scene shown on a LeiaSR eye-tracked 3D display.)

  @unorderedList(
    @item(@link(MainForm) holds the main window, the scene and the log.)
    @item(@link(FMX.SRStereoViewport) in @code(lib) shows the viewport on the
      SR display, through @link(SRFmxBridge.Api) and the bridge DLL in
      @code(dll), copied beside the executable after each build.)
    @item(@link(SimulatedReality.Api) in @code(lib) is the SDK's C API.)
    @item(@link(SRDiagLog) in @code(lib) writes @code(SRDemo.log) beside the
      executable, line by line, and records native crashes in it.)
    @item(FastMM5 (a submodule in @code(FastMM5)) is the memory manager. In
      Debug builds it runs in full debug mode when
      @code(FastMM_FullDebugMode64.dll) is beside the executable (the build
      copies it there), and writes @code(SRDemo_FastMM.log).)
  )

  Build for Windows 64-bit; the SR runtime is 64-bit only. }
program SRDemo;

uses
  FastMM5 in '..\FastMM5\FastMM5.pas',
  System.StartUpCopy,
  System.SysUtils,
  FMX.Forms,
  SRDiagLog in '..\lib\SRDiagLog.pas',
  MainForm in 'ui\MainForm.pas' {frmMain},
  FMX.SRStereoViewport in '..\lib\FMX.SRStereoViewport.pas',
  SRFmxBridge.Api in '..\lib\SRFmxBridge.Api.pas',
  SimulatedReality.Api in '..\lib\SimulatedReality.Api.pas';

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
  FastMM_DeleteEventLogFile;
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

  Application.Initialize;
  Application.CreateForm(TfrmMain, frmMain);
  Application.Run;
  DiagLog('Application.Run returned normally');
end.

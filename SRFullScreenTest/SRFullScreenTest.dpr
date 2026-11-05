{ @abstract(SRFullScreenTest: the full-screen fault, without FMX.)

  A plain Win32 window shows a woven stereo image on the LeiaSR display,
  windowed or full screen, with the suspects of the full-screen fault
  switchable from the keyboard: which window the weaver draws into, the
  adapter, the swap chain model, the view size, the weaver's input and the
  lens. See @link(TestWindow) for the keys and command line.

  @unorderedList(
    @item(@link(TestWindow) in @code(ui) is the window and the test.)
    @item(@link(SRStereoImage) in @code(lib) loads the side-by-side images
      from @code(media), or draws a numbered test pattern.)
    @item(@link(SRBridge.Api) in @code(lib) calls the bridge DLL in
      @code(dll), copied beside the executable after each build.)
    @item(@link(SRDiagLog) in @code(lib) writes @code(SRFullScreenTest.log)
      beside the executable and records native crashes in it.)
    @item(FastMM5 (a submodule in @code(FastMM5)) is the memory manager, in
      full debug mode in Debug builds, as in SRDemoFMX.)
  )

  Build for Windows 64-bit; the SR runtime is 64-bit only. }
program SRFullScreenTest;

uses
  FastMM5 in '..\FastMM5\FastMM5.pas',
  System.SysUtils,
  SRDiagLog in '..\lib\SRDiagLog.pas',
  SRBridge.Api in '..\lib\SRBridge.Api.pas',
  SRStereoImage in '..\lib\SRStereoImage.pas',
  TestWindow in 'ui\TestWindow.pas';

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
  DiagLogArchive(FastMMLogName);
  if FastMM_DebugModeActive then
    DiagLog('FastMM5 full debug mode ON; its events go to ' + FastMMLogName)
  else
    DiagLog('FastMM5 full debug mode off');

  ExitCode := RunFullScreenTest;
  DiagLog('Program ended normally');
end.

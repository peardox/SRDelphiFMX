{ @abstract(LenticularDemoVCL: a 3D scene on an eye-tracked lenticular display, from a VCL
  program.)

  VCL has no 3D, so the scene is drawn by the bridge itself on the GPU
  (@code(lnb_RenderScene)), straight into the view texture, and woven;
  nothing is read back, unlike LenticularDemoFMX's FMX route.

  @unorderedList(
    @item(@link(MainFormVCL) in @code(ui) holds the window, the controls
      and the log.)
    @item(@link(LenticularBridge.Api) in @code(lib) calls the bridge DLL in
      @code(dll), copied beside the executable after each build.)
    @item(@link(Lenticular.StereoImage) in @code(lib) loads the side-by-side images
      from @code(media) and draws the test pattern.)
    @item(@link(Lenticular.Settings) in @code(lib) keeps the choices, shared with
      LenticularDemoFMX, with the RTL's System.JSON.)
    @item(@link(Lenticular.DiagLog) in @code(lib) writes @code(LenticularDemoVCL.log) beside
      the executable and records native crashes in it.)
    @item(FastMM5 (a submodule in @code(FastMM5)) is the memory manager, in
      full debug mode in Debug builds.)
  )

  Build for Windows 64-bit; the display runtime is 64-bit only. }
program LenticularDemoVCL;

uses
  FastMM5 in '..\FastMM5\FastMM5.pas',
  System.SysUtils,
  Vcl.Forms,
  Lenticular.DiagLog in '..\lib\Lenticular.DiagLog.pas',
  Lenticular.Settings in '..\lib\Lenticular.Settings.pas',
  LenticularBridge.Api in '..\lib\LenticularBridge.Api.pas',
  Lenticular.StereoImage in '..\lib\Lenticular.StereoImage.pas',
  Lenticular.StartProblem in '..\lib\Lenticular.StartProblem.pas',
  Lenticular.SettingsDialog in '..\lib\Lenticular.SettingsDialog.pas',
  MainFormVCL in 'ui\MainFormVCL.pas' {frmMainVCL};

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

  Application.Initialize;
  Application.MainFormOnTaskbar := True;
  Application.Title := 'LenticularDemoVCL';
  Application.CreateForm(TfrmMainVCL, frmMainVCL);
  Application.Run;
  DiagLog('Application.Run returned normally');
end.

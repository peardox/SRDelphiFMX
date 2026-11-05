{ @abstract(MoviePlayerFMX: 3D films on a LeiaSR eye-tracked 3D display.)

  Opens a half side-by-side (HSBS) film, or a single frame, and weaves it at
  its proper shape as a stereo pair, with the film's sound.

  @unorderedList(
    @item(@link(PlayerForm) holds the main window, the viewport and the log.)
    @item(@link(SRStereoFrame) in @code(lib) holds a side-by-side frame
      (full or half side-by-side) and fits it into the two views; it uses
      neither FMX nor VCL.)
    @item(@link(SRVideoDecoder) in @code(lib) decodes a film's pictures with
      FFmpeg (headers in @code(ffmpeg-headers), DLLs copied from
      @code(dll\ffmpeg) by the build) on threads, timed by its sound, which
      @link(SRAudioOutput) plays through WASAPI; neither uses FMX or VCL.)
    @item(@link(FMX.SRMovieRenderer) in @code(lib) hands the current picture's
      views to @link(FMX.SRStereoViewport)'s renderer.)
    @item(@link(SRSettings) in @code(lib) keeps the eye separation and the
      shared choices in @code(%APPDATA%\SRDelphiFMX\settings.json), as the
      demos do.)
    @item(@link(SRDiagLog) in @code(lib) writes @code(MoviePlayerFMX.log)
      beside the executable, line by line, and records native crashes in it.
      Logs from earlier runs are moved into @code(oldlogs) beside it.)
    @item(FastMM5 (a submodule in @code(FastMM5)) is the memory manager. In
      Debug builds it runs in full debug mode when
      @code(FastMM_FullDebugMode64.dll) is beside the executable (the build
      copies it there), and writes @code(MoviePlayerFMX_FastMM.log).)
  )

  Build for Windows 64-bit; the SR runtime is 64-bit only. }
program MoviePlayerFMX;

uses
  FastMM5 in '..\FastMM5\FastMM5.pas',
  System.StartUpCopy,
  System.SysUtils,
  FMX.Forms,
  SRDiagLog in '..\lib\SRDiagLog.pas',
  SRSettings in '..\lib\SRSettings.pas',
  PlayerForm in 'ui\PlayerForm.pas' {frmPlayer},
  FMX.SRStereoViewport in '..\lib\FMX.SRStereoViewport.pas',
  FMX.SRMovieRenderer in '..\lib\FMX.SRMovieRenderer.pas',
  SRStereoFrame in '..\lib\SRStereoFrame.pas',
  SRVideoDecoder in '..\lib\SRVideoDecoder.pas',
  SRAudioOutput in '..\lib\SRAudioOutput.pas',
  SRBridge.Api in '..\lib\SRBridge.Api.pas',
  SRGpuPreference in '..\lib\SRGpuPreference.pas',
  SRStartProblem in '..\lib\SRStartProblem.pas',
  SRSettingsDialog in '..\lib\SRSettingsDialog.pas',
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
  DiagLogArchive(FastMMLogName);   // into oldlogs, like MoviePlayerFMX.log
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
  Application.CreateForm(TfrmPlayer, frmPlayer);
  Application.Run;
  DiagLog('Application.Run returned normally');
end.

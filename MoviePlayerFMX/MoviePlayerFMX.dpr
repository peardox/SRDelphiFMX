{ @abstract(MoviePlayerFMX: 3D films on an eye-tracked lenticular 3D display.)

  Opens a half side-by-side (HSBS) film, or a single frame, and weaves it at
  its proper shape as a stereo pair, with the film's sound.

  @unorderedList(
    @item(@link(PlayerForm) holds the main window, the viewport and the log.)
    @item(@link(Lenticular.StereoFrame) in @code(lib) holds a side-by-side frame
      (full or half side-by-side) and fits it into the two views; it uses
      neither FMX nor VCL.)
    @item(@link(Lenticular.VideoDecoder) in @code(lib) decodes a film's pictures with
      FFmpeg (headers in @code(ffmpeg-headers), DLLs copied from
      @code(dll\ffmpeg) by the build) on threads, timed by its sound, which
      @link(Lenticular.AudioOutput) plays through WASAPI; neither uses FMX or VCL.)
    @item(@link(Lenticular.MovieRenderer) in @code(lib) hands the current picture's
      views to @link(Lenticular.StereoViewport)'s renderer.)
    @item(@link(Lenticular.Settings) in @code(lib) keeps the eye separation and the
      shared choices in @code(%APPDATA%\Peardox\LenticularDemos.json), as the
      demos do.)
    @item(@link(Lenticular.DiagLog) in @code(lib) writes @code(MoviePlayerFMX.log)
      beside the executable, line by line, and records native crashes in it.
      Logs from earlier runs are moved into @code(oldlogs) beside it.)
    @item(FastMM5 (a submodule in @code(FastMM5)) is the memory manager. In
      Debug builds it runs in full debug mode when
      @code(FastMM_FullDebugMode64.dll) is beside the executable (the build
      copies it there), and writes @code(MoviePlayerFMX_FastMM.log).)
  )

  Build for Windows 64-bit; the display runtime is 64-bit only. }
program MoviePlayerFMX;

uses
  FastMM5 in '..\FastMM5\FastMM5.pas',
  System.StartUpCopy,
  System.SysUtils,
  FMX.Forms,
  Lenticular.DiagLog in '..\lib\Lenticular.DiagLog.pas',
  Lenticular.Settings in '..\lib\Lenticular.Settings.pas',
  PlayerForm in 'ui\PlayerForm.pas' {frmPlayer},
  Lenticular.StereoViewport in '..\lib\Lenticular.StereoViewport.pas',
  Lenticular.MovieRenderer in '..\lib\Lenticular.MovieRenderer.pas',
  Lenticular.StereoFrame in '..\lib\Lenticular.StereoFrame.pas',
  Lenticular.VideoDecoder in '..\lib\Lenticular.VideoDecoder.pas',
  Lenticular.AudioOutput in '..\lib\Lenticular.AudioOutput.pas',
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

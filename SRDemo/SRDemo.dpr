{ @abstract(SRDemo: a test scene shown on a LeiaSR eye-tracked 3D display.)

  @unorderedList(
    @item(@link(MainForm) holds the main window, the scene and the log.)
    @item(@link(FMX.SRStereoViewport) in @code(lib) shows the viewport on the
      SR display, through @link(SRFmxBridge.Api) and the bridge DLL in
      @code(dll), copied beside the executable after each build.)
    @item(@link(SimulatedReality.Api) in @code(lib) is the SDK's C API.)
  )

  Build for Windows 64-bit; the SR runtime is 64-bit only. }
program SRDemo;

uses
  System.StartUpCopy,
  FMX.Forms,
  MainForm in 'ui\MainForm.pas' {frmMain},
  FMX.SRStereoViewport in '..\lib\FMX.SRStereoViewport.pas',
  SRFmxBridge.Api in '..\lib\SRFmxBridge.Api.pas',
  SimulatedReality.Api in '..\lib\SimulatedReality.Api.pas';

{$R *.res}

begin
  Application.Initialize;
  Application.CreateForm(TfrmMain, frmMain);
  Application.Run;
end.

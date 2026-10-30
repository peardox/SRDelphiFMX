{ @abstract(Saved settings for the SR programs: eye separation, depth and the
  demo's last choices.)

  Settings are stored as @code(settings.json) in @code(%APPDATA%\SRDelphiFMX)
  (the SR runtime exists only on Windows). The file is written and read with
  the Neon JSON library (@url(https://github.com/paolo-rossi/delphi-neon)),
  as in GDEM: every public property of @link(TSRSettings) is saved, under its
  camel-case name, so a new setting only needs a new property. Settings
  missing from the file keep their defaults. }
unit SRSettings;

interface

uses
  System.SysUtils;

const
  { Name of the per-user folder settings are kept in. }
  SETTINGS_FOLDER_NAME = 'SRDelphiFMX';

  { Name of the settings file inside @link(SETTINGS_FOLDER_NAME). }
  SETTINGS_FILE_NAME = 'settings.json';

  { Default for @link(TSRSettings.EyeSeparationMM): the usual adult
    separation, and what the owner's SR software is set to. }
  DEFAULT_EYE_SEPARATION_MM = 63.0;

  { Default for @link(TSRSettings.FocusDistance): FMX's usual camera is 20
    units from the origin. }
  DEFAULT_FOCUS_DISTANCE = 20.0;

type
  { @abstract(Raised when settings cannot be read or written.) }
  ESettingsError = class(Exception);

  { @abstract(The user's saved settings.)

    Create one, call @link(Load), change properties and call @link(Save).
    Only public properties are saved. }
  TSRSettings = class
  private
    { Backing field for @link(EyeSeparationMM). }
    FEyeSeparationMM: Double;
    { Backing field for @link(FocusDistance). }
    FFocusDistance: Double;
    { Backing field for @link(EyeSeparationScale). }
    FEyeSeparationScale: Double;
    { Backing field for @link(LatencyFrames). }
    FLatencyFrames: Integer;
    { Backing field for @link(LookAround). }
    FLookAround: Boolean;
    { Backing field for @link(StereoImage). }
    FStereoImage: string;
    { Backing field for @link(FullScreen). }
    FFullScreen: Boolean;
    { Backing field for @link(LensMode). }
    FLensMode: Integer;
  public
    { Creates settings with default values, which are kept for any setting
      missing from the file when it is loaded. }
    constructor Create;

    { Folder settings are stored in for the current user. Not created by
      this call.
      @returns(Full path of the folder.) }
    class function SettingsFolder: string; static;

    { Full path of the settings file.
      @returns(@link(SettingsFolder) combined with
        @link(SETTINGS_FILE_NAME).) }
    class function SettingsFileName: string; static;

    { Reads the settings file into this object.
      @returns(@true if the file existed and was read; @false if there is
        no settings file yet, in which case the properties are unchanged.)
      @raises(ESettingsError if the file exists but cannot be read or is not
        valid settings JSON.) }
    function Load: Boolean;

    { Writes this object to the settings file, creating the folder if
      needed. Written to a temporary name first and then renamed, so an
      interrupted save cannot leave a half-written file.
      @raises(ESettingsError if the file cannot be written.) }
    procedure Save;

    { Eye separation in millimetres used instead of the eye tracker's
      measurement (which wanders), keeping the tracked head position; 0
      uses the tracked eyes as they are. Defaults to
      @link(DEFAULT_EYE_SEPARATION_MM). }
    property EyeSeparationMM: Double read FEyeSeparationMM write FEyeSeparationMM;

    { Distance in world units in front of the camera of the plane that falls
      on the display glass. Defaults to @link(DEFAULT_FOCUS_DISTANCE). }
    property FocusDistance: Double read FFocusDistance write FFocusDistance;

    { Depth scale: 1 is physically correct, less is gentler. Defaults to 1. }
    property EyeSeparationScale: Double read FEyeSeparationScale write FEyeSeparationScale;

    { Frames of rendering latency told to the weaver for its eye prediction;
      0 leaves SR's default. }
    property LatencyFrames: Integer read FLatencyFrames write FLatencyFrames;

    { @true (the default) to draw the scene from where the head is, so it
      can be looked around; @false to draw from a fixed position in front of
      the viewport, keeping depth but not the look-around. }
    property LookAround: Boolean read FLookAround write FLookAround;

    { File name (without folder) of the media image SRDemo last showed;
      empty for the 3D scene. }
    property StereoImage: string read FStereoImage write FStereoImage;

    { Whether SRDemo was last full screen. }
    property FullScreen: Boolean read FFullScreen write FFullScreen;

    { When the display's lens is on: 0 off while the pointer is over the
      controls (the default), 1 always on, 2 always off. The order of
      @code(TSRLensMode) in @code(FMX.SRStereoViewport), kept as a number so
      this unit does not depend on the renderer. }
    property LensMode: Integer read FLensMode write FLensMode;
  end;

implementation

uses
  System.IOUtils, Neon.Core.Persistence, Neon.Core.Persistence.JSON;

{ Returns the Neon configuration used for both reading and writing, so the
  two always agree on member names.
  @returns(Camel-case member names, pretty-printed, raising exceptions on
    bad data.) }
function SettingsNeonConfig: INeonConfiguration;
begin
  Result := TNeonConfiguration.Camel
    .SetPrettyPrint(True)
    .SetRaiseExceptions(True);
end;

{ TSRSettings }

constructor TSRSettings.Create;
begin
  inherited Create;
  FEyeSeparationMM := DEFAULT_EYE_SEPARATION_MM;
  FFocusDistance := DEFAULT_FOCUS_DISTANCE;
  FEyeSeparationScale := 1.0;
  FLatencyFrames := 0;
  FLookAround := True;
end;

class function TSRSettings.SettingsFolder: string;
begin
  // TPath.GetHomePath is %APPDATA% (the roaming profile) on Windows
  Result := TPath.Combine(TPath.GetHomePath, SETTINGS_FOLDER_NAME);
end;

class function TSRSettings.SettingsFileName: string;
begin
  Result := TPath.Combine(SettingsFolder, SETTINGS_FILE_NAME);
end;

function TSRSettings.Load: Boolean;
var
  LFileName, LJSON: string;
begin
  LFileName := SettingsFileName;
  if not TFile.Exists(LFileName) then
    Exit(False);
  try
    LJSON := TEncoding.UTF8.GetString(TFile.ReadAllBytes(LFileName));
    TNeon.JSONToObject(Self, LJSON, SettingsNeonConfig);
  except
    on E: Exception do
      raise ESettingsError.CreateFmt('Could not read settings from %s: %s',
        [LFileName, E.Message]);
  end;
  Result := True;
end;

procedure TSRSettings.Save;
var
  LFileName, LTempName, LJSON: string;
begin
  LFileName := SettingsFileName;
  LTempName := LFileName + '.tmp';
  try
    ForceDirectories(SettingsFolder);
    LJSON := TNeon.ObjectToJSONString(Self, SettingsNeonConfig);
    TFile.WriteAllBytes(LTempName, TEncoding.UTF8.GetBytes(LJSON));
    if TFile.Exists(LFileName) then
      TFile.Delete(LFileName);
    TFile.Move(LTempName, LFileName);
  except
    on E: Exception do
    begin
      if TFile.Exists(LTempName) then
        TFile.Delete(LTempName);
      raise ESettingsError.CreateFmt('Could not save settings to %s: %s',
        [LFileName, E.Message]);
    end;
  end;
end;

end.

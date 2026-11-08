{ @abstract(Saved settings for the glasses-free 3D programs here: eye
  separation, depth and the demo's last choices.)

  Settings are stored as @code(LenticularDemos.json) in the @code(Peardox)
  folder of the user's application data (@code(%APPDATA%\Peardox); the
  display runtime exists only on Windows). The file is written and read
  with the RTL's System.JSON and RTTI, no third-party library: every public
  property of @link(TLenticularSettings) is saved, under its camel-case
  name, so a new setting only needs a new property. Settings missing from
  the file keep their defaults, and members no property matches are
  ignored. }
unit Lenticular.Settings;

interface

uses
  System.SysUtils;

const
  { Name of the per-user folder settings are kept in: the owner's, shared
    with his other programs (each has its own file in it). }
  SETTINGS_FOLDER_NAME = 'Peardox';

  { Name of the settings file inside @link(SETTINGS_FOLDER_NAME). }
  SETTINGS_FILE_NAME = 'LenticularDemos.json';

  { Default for @link(TLenticularSettings.EyeSeparationMM): the usual adult
    separation, and what the owner's display software is set to. }
  DEFAULT_EYE_SEPARATION_MM = 63.0;

  { Default for @link(TLenticularSettings.FocusDistance): FMX's usual camera is 20
    units from the origin. }
  DEFAULT_FOCUS_DISTANCE = 20.0;

type
  { @abstract(Raised when settings cannot be read or written.) }
  ESettingsError = class(Exception);

  { @abstract(The user's saved settings.)

    Create one, call @link(Load), change properties and call @link(Save).
    Only public properties are saved. }
  TLenticularSettings = class
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
    { See @link(TLenticularSettings.UseGlassesFree3D). }
    FUseGlassesFree3D: Boolean;
    { See @link(TLenticularSettings.PlayerFolder). }
    FPlayerFolder: string;
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

    { Depth scale: 1 is physically correct, less is gentler. Defaults to 1.
      Kept so older settings files still load; the demos always use and save
      1 (their Depth slider is gone; LenticularDemoFMX puts back a saved other value). }
    property EyeSeparationScale: Double read FEyeSeparationScale write FEyeSeparationScale;

    { Frames of rendering latency told to the weaver for its eye prediction;
      0 leaves the runtime's default. }
    property LatencyFrames: Integer read FLatencyFrames write FLatencyFrames;

    { @true (the default) to draw the scene from where the head is, so it
      can be looked around; @false to draw from a fixed position in front of
      the viewport, keeping depth but not the look-around. }
    property LookAround: Boolean read FLookAround write FLookAround;

    { File name (without folder) of the media image LenticularDemoFMX last showed;
      empty for the 3D scene. }
    property StereoImage: string read FStereoImage write FStereoImage;

    { Whether LenticularDemoFMX was last full screen. }
    property FullScreen: Boolean read FFullScreen write FFullScreen;

    { When the display's lens is on: 0 off while the pointer is over the
      controls (the default), 1 always on, 2 always off. The order of
      @code(TLenticularLensMode) in @code(Lenticular.StereoViewport), kept as a number so
      this unit does not depend on the renderer. }
    property LensMode: Integer read FLensMode write FLensMode;

    { @true (the default) to start glasses-free 3D when the program starts,
      on a computer that has the display runtime; @false to leave it off
      until the user turns it on. Ignored where the runtime is not
      installed: there the program behaves as if it had no glasses-free 3D
      support. }
    property UseGlassesFree3D: Boolean read FUseGlassesFree3D write FUseGlassesFree3D;

    { The folder MoviePlayerFMX last opened a film or frame from, where its
      Open... starts next time; empty until it has opened one. The demos do
      not use it. }
    property PlayerFolder: string read FPlayerFolder write FPlayerFolder;
  end;

implementation

uses
  System.IOUtils, System.Rtti, System.TypInfo, System.JSON;

const
  { Spaces per level in the JSON written by @link(TLenticularSettings.Save). }
  JSON_INDENT = 2;

{ A property's JSON member name: its name with the first letter made lower
  case, as the settings files have always used (@code(eyeSeparationMM)).
  @param(AName The property's name.)
  @returns(The member name.) }
function MemberName(const AName: string): string;
begin
  Result := AName;
  if Result <> '' then
    Result[Low(Result)] := LowerCase(Result[Low(Result)])[Low(Result)];
end;

{ Whether a property is one of the settings: public, readable and writable,
  of a kind @link(TLenticularSettings.Save) can write.
  @param(AProp The property.)
  @returns(@true if it is saved and loaded.) }
function IsSetting(AProp: TRttiProperty): Boolean;
begin
  Result := (AProp.Visibility in [mvPublic, mvPublished]) and AProp.IsReadable and
    AProp.IsWritable and (AProp.PropertyType.TypeKind in [tkInteger, tkInt64, tkFloat,
    tkEnumeration, tkString, tkLString, tkWString, tkUString]);
end;

{ TLenticularSettings }

constructor TLenticularSettings.Create;
begin
  inherited Create;
  FEyeSeparationMM := DEFAULT_EYE_SEPARATION_MM;
  FFocusDistance := DEFAULT_FOCUS_DISTANCE;
  FEyeSeparationScale := 1.0;
  FLatencyFrames := 0;
  FLookAround := True;
  FUseGlassesFree3D := True;
end;

class function TLenticularSettings.SettingsFolder: string;
begin
  // TPath.GetHomePath is %APPDATA% (the roaming profile) on Windows
  Result := TPath.Combine(TPath.GetHomePath, SETTINGS_FOLDER_NAME);
end;

class function TLenticularSettings.SettingsFileName: string;
begin
  Result := TPath.Combine(SettingsFolder, SETTINGS_FILE_NAME);
end;

function TLenticularSettings.Load: Boolean;
var
  LFileName, LJSON: string;
  Parsed, Member: TJSONValue;
  Obj: TJSONObject;
  Ctx: TRttiContext;
  Prop: TRttiProperty;
  I: Integer;
begin
  LFileName := SettingsFileName;
  if not TFile.Exists(LFileName) then
    Exit(False);
  try
    LJSON := TEncoding.UTF8.GetString(TFile.ReadAllBytes(LFileName));
    Parsed := TJSONObject.ParseJSONValue(LJSON);
    try
      if not (Parsed is TJSONObject) then
        raise ESettingsError.Create('not a JSON object');
      Obj := TJSONObject(Parsed);
      Ctx := TRttiContext.Create;
      for Prop in Ctx.GetType(ClassType).GetProperties do
      begin
        if not IsSetting(Prop) then
          Continue;
        // Members are matched without regard to case
        Member := nil;
        for I := 0 to Obj.Count - 1 do
          if SameText(Obj.Pairs[I].JsonString.Value, Prop.Name) then
          begin
            Member := Obj.Pairs[I].JsonValue;
            Break;
          end;
        if Member = nil then
          Continue;
        case Prop.PropertyType.TypeKind of
          tkInteger:
            if Member is TJSONNumber then
              Prop.SetValue(Self, TValue.From<Integer>(TJSONNumber(Member).AsInt));
          tkInt64:
            if Member is TJSONNumber then
              Prop.SetValue(Self, TValue.From<Int64>(TJSONNumber(Member).AsInt64));
          tkFloat:
            if Member is TJSONNumber then
              Prop.SetValue(Self, TValue.From<Double>(TJSONNumber(Member).AsDouble));
          tkEnumeration:
            if Prop.PropertyType.Handle = TypeInfo(Boolean) then
            begin
              if Member is TJSONBool then
                Prop.SetValue(Self, TValue.From<Boolean>(TJSONBool(Member).AsBoolean));
            end
            else if (Member is TJSONString) and not (Member is TJSONNumber) then
              Prop.SetValue(Self, TValue.FromOrdinal(Prop.PropertyType.Handle,
                GetEnumValue(Prop.PropertyType.Handle, TJSONString(Member).Value)));
        else
          if (Member is TJSONString) and not (Member is TJSONNumber) then
            Prop.SetValue(Self, TValue.From<string>(TJSONString(Member).Value));
        end;
      end;
    finally
      Parsed.Free;
    end;
  except
    on E: Exception do
      raise ESettingsError.CreateFmt('Could not read settings from %s: %s',
        [LFileName, E.Message]);
  end;
  Result := True;
end;

procedure TLenticularSettings.Save;
var
  LFileName, LTempName, LJSON: string;
  Obj: TJSONObject;
  Ctx: TRttiContext;
  Prop: TRttiProperty;
  Value: TValue;
begin
  LFileName := SettingsFileName;
  LTempName := LFileName + '.tmp';
  try
    ForceDirectories(SettingsFolder);
    Obj := TJSONObject.Create;
    try
      Ctx := TRttiContext.Create;
      for Prop in Ctx.GetType(ClassType).GetProperties do
      begin
        if not IsSetting(Prop) then
          Continue;
        Value := Prop.GetValue(Self);
        case Prop.PropertyType.TypeKind of
          tkInteger, tkInt64:
            Obj.AddPair(MemberName(Prop.Name), TJSONNumber.Create(Value.AsInt64));
          tkFloat:
            Obj.AddPair(MemberName(Prop.Name), TJSONNumber.Create(Value.AsExtended));
          tkEnumeration:
            if Prop.PropertyType.Handle = TypeInfo(Boolean) then
              Obj.AddPair(MemberName(Prop.Name), TJSONBool.Create(Value.AsBoolean))
            else
              Obj.AddPair(MemberName(Prop.Name), TJSONString.Create(
                GetEnumName(Prop.PropertyType.Handle, Value.AsOrdinal)));
        else
          Obj.AddPair(MemberName(Prop.Name), TJSONString.Create(Value.AsString));
        end;
      end;
      LJSON := Obj.Format(JSON_INDENT);
    finally
      Obj.Free;
    end;
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

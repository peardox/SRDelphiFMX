{ @abstract(Windows' per-program GPU preference: the setting in Settings >
  System > Display > Graphics.)

  On laptops with an integrated GPU beside a discrete one, Windows starts
  programs on the integrated GPU unless told otherwise, and a program cannot
  choose for itself which GPU FMX (or any other framework) draws on. The
  preference is kept per executable in
  @code(HKCU\Software\Microsoft\DirectX\UserGpuPreferences), as a string
  value named after the executable's full path, such as
  @code(GpuPreference=2;). It takes effect the next time the program
  starts. Other settings in the same string (for example
  @code(SwapEffectUpgradeEnable=1;)) are kept. No FMX: any program can use
  it. }
unit SRGpuPreference;

interface

const
  { No preference set: Windows decides. }
  GpuPreferenceDefault = 0;
  { Power saving: usually the integrated GPU. }
  GpuPreferencePowerSaving = 1;
  { High performance: usually the discrete GPU. }
  GpuPreferenceHighPerformance = 2;

{ Reads a program's GPU preference.
  @param(ExeName the executable's full path; empty means this program)
  @returns(@link(GpuPreferenceDefault), @link(GpuPreferencePowerSaving) or
    @link(GpuPreferenceHighPerformance)) }
function GetGpuPreference(const ExeName: string = ''): Integer;

{ Sets a program's GPU preference, keeping any other settings in the same
  value. Takes effect the next time the program starts.
  @param(Preference one of the @code(GpuPreference...) constants)
  @param(ExeName the executable's full path; empty means this program)
  @returns(@true if it was written) }
function SetGpuPreference(Preference: Integer; const ExeName: string = ''): Boolean;

{ The preference as words, for logs and messages.
  @param(Preference one of the @code(GpuPreference...) constants)
  @returns(its name) }
function GpuPreferenceName(Preference: Integer): string;

implementation

uses
  Winapi.Windows, System.SysUtils, System.StrUtils, System.Win.Registry;

const
  { Where Windows keeps the preferences. }
  PreferencesKey = 'Software\Microsoft\DirectX\UserGpuPreferences';
  { The setting's name inside the value. }
  PreferenceName = 'GpuPreference=';

{ The executable to use. @param(ExeName given name, or empty)
  @returns(the full path) }
function ExePath(const ExeName: string): string;
begin
  if ExeName = '' then
    Result := ParamStr(0)
  else
    Result := ExeName;
end;

function GetGpuPreference(const ExeName: string): Integer;
var
  Reg: TRegistry;
  Value, Part: string;
begin
  Result := GpuPreferenceDefault;
  Reg := TRegistry.Create(KEY_READ);
  try
    Reg.RootKey := HKEY_CURRENT_USER;
    if not Reg.OpenKeyReadOnly(PreferencesKey) then
      Exit;
    if not Reg.ValueExists(ExePath(ExeName)) then
      Exit;
    Value := Reg.ReadString(ExePath(ExeName));
    for Part in Value.Split([';']) do
      if StartsText(PreferenceName, Trim(Part)) then
        Result := StrToIntDef(Copy(Trim(Part), Length(PreferenceName) + 1, MaxInt), GpuPreferenceDefault);
  finally
    Reg.Free;
  end;
end;

function SetGpuPreference(Preference: Integer; const ExeName: string): Boolean;
var
  Reg: TRegistry;
  Value, Part, NewValue: string;
begin
  Result := False;
  Reg := TRegistry.Create(KEY_READ or KEY_WRITE);
  try
    Reg.RootKey := HKEY_CURRENT_USER;
    if not Reg.OpenKey(PreferencesKey, True) then
      Exit;
    Value := '';
    if Reg.ValueExists(ExePath(ExeName)) then
      Value := Reg.ReadString(ExePath(ExeName));
    NewValue := '';
    for Part in Value.Split([';']) do
      if (Trim(Part) <> '') and not StartsText(PreferenceName, Trim(Part)) then
        NewValue := NewValue + Trim(Part) + ';';
    NewValue := PreferenceName + IntToStr(Preference) + ';' + NewValue;
    try
      Reg.WriteString(ExePath(ExeName), NewValue);
      Result := True;
    except
      on ERegistryException do
        Result := False;
    end;
  finally
    Reg.Free;
  end;
end;

function GpuPreferenceName(Preference: Integer): string;
begin
  case Preference of
    GpuPreferencePowerSaving: Result := 'Power saving';
    GpuPreferenceHighPerformance: Result := 'High performance';
  else
    Result := 'Let Windows decide';
  end;
end;

end.

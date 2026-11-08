//** @abstract(Per-user storage for the Lenticular components: where to keep files, and JSON
//** settings.)
//**
//** AppDataFolder gives the folder each platform expects an application to keep its own
//** files in, kept between sessions and private to the user. TLenticularStorage is a base
//** class for settings: a descendant declares its settings as published properties, and Load
//** and Save read and write them as a JSON file.
//**
//** After Sprite3D's Sprite3DStorage (TSprite3DJsonSettings), without its OSPaths and JsonText
//** helpers, and with the RTL's own System.JSON in place of the Neon library, so the package
//** needs nothing outside Delphi. The file is the one Neon wrote: the same member names, so a
//** file written before still loads.
//**
//** @preformatted(
//** Windows   %APPDATA%\<AppName>
//** macOS     ~/Library/Application Support/<AppName>
//** Linux     $XDG_CONFIG_HOME/<AppName>, or ~/.config/<AppName>
//** Android   the app's private files folder
//** iOS       the app's Library/Application Support folder
//** )
unit Lenticular.Storage;

{
  Per-user storage for the Lenticular components: where to keep files, and
  JSON settings.

  AppDataFolder gives the folder each platform expects an application to
  keep its own files in, kept between sessions and private to the user.
  TLenticularStorage is a base class for settings: a descendant
  declares its settings as published properties, and Load and Save read
  and write them as a JSON file with System.JSON (no third-party library).

  After Sprite3D's Sprite3DStorage (TSprite3DJsonSettings), without its
  OSPaths and JsonText helpers.

    Windows   %APPDATA%\<AppName>
    macOS     ~/Library/Application Support/<AppName>
    Linux     $XDG_CONFIG_HOME/<AppName>, or ~/.config/<AppName>
    Android   the app's private files folder
    iOS       the app's Library/Application Support folder
}

interface

uses
  System.SysUtils, System.Classes;

//** @abstract(The per-user folder an application should keep its own files in.)
//**
//** Chosen by platform, as in the unit description, and not created;
//** TLenticularStorage.Save creates it when it first writes there. On Android and iOS the
//** folder already belongs to the app, so AAppName is only added on the desktop platforms.
//**
//** @param(AAppName The folder's name on the desktop; a valid file name on every platform.)
//**
//** @returns(The folder's full path, without a trailing path delimiter.)
function AppDataFolder(const AAppName: string): string;

type
  //** @abstract(Base class for settings kept as a JSON file.)
  //**
  //** Declare each setting as a published property of a descendant, with its default set in
  //** the constructor; Load fills them from the file and Save writes them all back. The JSON
  //** member names are the property names in camel case, such as @code(eyeSeparationMM) for
  //** EyeSeparationMM; Load matches them without regard to case. Only published properties
  //** are stored, of these kinds: integers, Int64, floating point, Boolean (a JSON true or
  //** false), other enumerations (by name) and strings. Settings missing from the file keep
  //** their defaults, and members no property matches, or whose value does not suit the
  //** property, are ignored, so an older or newer file still loads.
  //**
  //** Not thread-safe; use one object from one thread, normally the main thread.
  TLenticularStorage = class(TPersistent)
  private
    //** @abstract(See FileName.)
    FFileName: string;
    //** @abstract(See LastError.)
    FLastError: string;
  protected
    //** @abstract(Every published property as a JSON object, members in declaration order.)
    //**
    //** @returns(The JSON text, laid out for people to read.)
    function ToJson: string;
    //** @abstract(Sets the published properties from the members of a JSON object.)
    //**
    //** @param(AJson The JSON text.)
    //**
    //** @raises(EJSONException If AJson is not a JSON object.)
    procedure FromJson(const AJson: string);
  public
    //** @abstract(Creates the settings with their defaults, for the given file.)
    //**
    //** Nothing is read until Load, and neither the file nor its folder is made until Save.
    //**
    //** @param(AFileName The JSON file's full path.)
    constructor Create(const AFileName: string); virtual;
    //** @abstract(Reads the settings from FileName.)
    //**
    //** A missing file, normal on the first run, or one that cannot be read or parsed leaves
    //** the settings as they were and raises nothing; LastError says why, and a damaged file
    //** is replaced at the next Save.
    //**
    //** @returns(True if the file was read; False if it was missing or unusable.)
    function Load: Boolean;
    //** @abstract(Writes every setting to FileName, making its folder if needed.)
    //**
    //** The JSON goes to a temporary file beside FileName, which then replaces it, so a failure
    //** part-way leaves the previous file whole.
    //**
    //** @raises(Exception If the folder or the file cannot be written; the class depends on
    //** the cause.)
    procedure Save;
    //** @abstract(The JSON file's full path, as given to Create.)
    property FileName: string read FFileName;
    //** @abstract(Why the last Load returned False: "no file yet", or the error; empty after a
    //** Load that worked.)
    property LastError: string read FLastError;
  end;

implementation

uses
  System.IOUtils, System.TypInfo, System.JSON;

const
  //** @abstract(Spaces per level in the JSON written by Save.)
  JSON_INDENT = 2;

function AppDataFolder(const AAppName: string): string;
{$IF DEFINED(LINUX)}
var
  ConfigHome: string;
{$ENDIF}
begin
  {$IF DEFINED(MSWINDOWS)}
  // TPath.GetHomePath is %APPDATA% on Windows
  Result := TPath.Combine(TPath.GetHomePath, AAppName);
  {$ELSEIF DEFINED(IOS)}
  // The app's own sandbox: Library/Application Support
  Result := TPath.Combine(TPath.GetLibraryPath, 'Application Support');
  {$ELSEIF DEFINED(MACOS)}
  Result := TPath.Combine(TPath.Combine(TPath.Combine(TPath.GetHomePath,
    'Library'), 'Application Support'), AAppName);
  {$ELSEIF DEFINED(ANDROID)}
  // The app's private files folder
  Result := TPath.GetDocumentsPath;
  {$ELSE}
  // Linux: the XDG base directory rules
  ConfigHome := GetEnvironmentVariable('XDG_CONFIG_HOME');
  if ConfigHome = '' then
    ConfigHome := TPath.Combine(TPath.GetHomePath, '.config');
  Result := TPath.Combine(ConfigHome, AAppName);
  {$ENDIF}
  Result := ExcludeTrailingPathDelimiter(Result);
end;

//** @abstract(A property's JSON member name: its name in camel case, as Neon wrote it.)
//**
//** @param(APropName The property's name, such as EyeSeparationMM.)
//**
//** @returns(The name with its first letter made lower case, such as eyeSeparationMM.)
function MemberName(const APropName: string): string;
begin
  Result := APropName;
  if Result <> '' then
    Result[Low(Result)] := LowerCase(Result[Low(Result)])[Low(Result)];
end;

//** @abstract(Whether a property is a Boolean, stored as a JSON true or false.)
//**
//** @param(AProp The property.)
//**
//** @returns(True for Boolean and the types declared as it.)
function IsBooleanProp(AProp: PPropInfo): Boolean;
var
  Data: PTypeData;
begin
  Result := False;
  if AProp^.PropType^^.Kind <> tkEnumeration then
    Exit;
  Data := GetTypeData(AProp^.PropType^);
  Result := (Data^.BaseType <> nil) and (Data^.BaseType^ = TypeInfo(Boolean));
end;

//** @abstract(A member of a JSON object found by name without regard to case.)
//**
//** @param(AObject The object.)
//**
//** @param(AName The member's name.)
//**
//** @returns(The member's value, or nil if there is none.)
function FindMember(AObject: TJSONObject; const AName: string): TJSONValue;
var
  I: Integer;
begin
  for I := 0 to AObject.Count - 1 do
    if SameText(AObject.Pairs[I].JsonString.Value, AName) then
      Exit(AObject.Pairs[I].JsonValue);
  Result := nil;
end;

{ TLenticularStorage }

constructor TLenticularStorage.Create(const AFileName: string);
begin
  inherited Create;
  FFileName := AFileName;
end;

function TLenticularStorage.ToJson: string;
var
  Props: PPropList;
  Count, I: Integer;
  P: PPropInfo;
  Obj: TJSONObject;
  Value: TJSONValue;
begin
  Obj := TJSONObject.Create;
  try
    Count := GetPropList(Self, Props);
    try
      for I := 0 to Count - 1 do
      begin
        P := Props^[I];
        if P^.GetProc = nil then
          Continue;
        case P^.PropType^^.Kind of
          tkInteger:
            Value := TJSONNumber.Create(GetOrdProp(Self, P));
          tkInt64:
            Value := TJSONNumber.Create(GetInt64Prop(Self, P));
          tkFloat:
            Value := TJSONNumber.Create(GetFloatProp(Self, P));
          tkEnumeration:
            if IsBooleanProp(P) then
              Value := TJSONBool.Create(GetOrdProp(Self, P) <> 0)
            else
              Value := TJSONString.Create(GetEnumProp(Self, P));
          tkString, tkLString, tkWString, tkUString:
            Value := TJSONString.Create(GetStrProp(Self, P));
        else
          // Sets, classes, events and the like are not settings
          Continue;
        end;
        Obj.AddPair(MemberName(string(P^.Name)), Value);
      end;
    finally
      FreeMem(Props);
    end;
    Result := Obj.Format(JSON_INDENT);
  finally
    Obj.Free;
  end;
end;

procedure TLenticularStorage.FromJson(const AJson: string);
var
  Parsed, Value: TJSONValue;
  Obj: TJSONObject;
  Props: PPropList;
  Count, I: Integer;
  P: PPropInfo;
begin
  Parsed := TJSONObject.ParseJSONValue(AJson);
  try
    if not (Parsed is TJSONObject) then
      raise EJSONException.Create('the file is not a JSON object');
    Obj := TJSONObject(Parsed);
    Count := GetPropList(Self, Props);
    try
      for I := 0 to Count - 1 do
      begin
        P := Props^[I];
        if P^.SetProc = nil then
          Continue;
        Value := FindMember(Obj, string(P^.Name));
        if Value = nil then
          Continue;
        try
          case P^.PropType^^.Kind of
            tkInteger:
              if Value is TJSONNumber then
                SetOrdProp(Self, P, TJSONNumber(Value).AsInt);
            tkInt64:
              if Value is TJSONNumber then
                SetInt64Prop(Self, P, TJSONNumber(Value).AsInt64);
            tkFloat:
              if Value is TJSONNumber then
                SetFloatProp(Self, P, TJSONNumber(Value).AsDouble);
            tkEnumeration:
              if IsBooleanProp(P) then
              begin
                if Value is TJSONBool then
                  SetOrdProp(Self, P, Ord(TJSONBool(Value).AsBoolean));
              end
              else if (Value is TJSONString) and not (Value is TJSONNumber) then
                SetEnumProp(Self, P, TJSONString(Value).Value);
            tkString, tkLString, tkWString, tkUString:
              if Value is TJSONString then
                SetStrProp(Self, P, TJSONString(Value).Value);
          end;
        except
          // A value that does not suit the property (an enumeration name this
          // version lacks, a number out of range): keep the default
          on EConvertError do ;
          on ERangeError do ;
          on EPropertyConvertError do ;
        end;
      end;
    finally
      FreeMem(Props);
    end;
  finally
    Parsed.Free;
  end;
end;

function TLenticularStorage.Load: Boolean;
var
  Json: string;
begin
  Result := False;
  if not TFile.Exists(FFileName) then
  begin
    FLastError := 'no file yet';
    Exit;
  end;
  try
    Json := TFile.ReadAllText(FFileName, TEncoding.UTF8);
    FromJson(Json);
    FLastError := '';
    Result := True;
  except
    // Unreadable or damaged: keep the current values; Save replaces it
    on E: Exception do
      FLastError := E.ClassName + ': ' + E.Message;
  end;
end;

procedure TLenticularStorage.Save;
var
  Json, TempName: string;
begin
  ForceDirectories(ExtractFileDir(FFileName));
  Json := ToJson;
  TempName := FFileName + '.tmp';
  // UTF-8 without a byte order mark, as JSON files normally are
  TFile.WriteAllBytes(TempName, TEncoding.UTF8.GetBytes(Json));
  if TFile.Exists(FFileName) then
    TFile.Delete(FFileName);
  TFile.Move(TempName, FFileName);
end;

end.

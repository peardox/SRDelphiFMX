{ @abstract(A crash-proof diagnostic log file, and handlers that record native
  crashes in it.)

  Every line is written straight to the file (no buffering in the program), so
  the lines before a crash are still there afterwards. Lines can come from any
  thread; each carries the time and the thread's id.

  @link(DiagLogInstallCrashHandlers) records serious hardware exceptions
  (access violations, stack overflow, heap corruption and so on) when they
  happen, with the module and offset they happened at, before anything else
  handles them. It also records any exception nothing handled, just before
  Windows ends the program. @link(DiagLogAttachBridge) sends the bridge DLL's
  own log lines, including its last-gasp FATAL lines, to the same file.

  No FMX: any program can use it. Windows only, as is the SR runtime. }
unit SRDiagLog;

interface

{ Opens a new, empty log file and writes a header line. A log left by an
  earlier run is first moved to @link(DiagLogArchive)'s folder.
  @param(FileName full path of the file) }
procedure DiagLogOpen(const FileName: string);

{ Moves a log file left by an earlier run into an @code(oldlogs) folder
  beside it, named with the time it was last written (for example
  @code(oldlogs\SRDemo_20261029_222023.log)), and deletes all but the newest
  @link(OldLogsKept) logs of the same name there. Does nothing if the file
  does not exist.
  @param(FileName full path of the log file) }
procedure DiagLogArchive(const FileName: string);

const
  { How many old logs of each name @link(DiagLogArchive) keeps. }
  OldLogsKept = 20;

{ Writes one line, with the time and thread id. Safe from any thread; does
  nothing before @link(DiagLogOpen).
  @param(Msg the line) }
procedure DiagLog(const Msg: string);

{ Writes a closing line and closes the file. }
procedure DiagLogClose;

{ @returns(the log file's path, empty before @link(DiagLogOpen)) }
function DiagLogFileName: string;

{ Installs a vectored exception handler that logs serious hardware exceptions
  as they happen (on any thread, in any module, including the SR DLLs), and an
  unhandled-exception filter that logs the exception that ends the program. }
procedure DiagLogInstallCrashHandlers;

{ Sends SRFmxBridge.dll's log lines to this log, if the DLL can be loaded.
  @returns(@true if attached) }
function DiagLogAttachBridge: Boolean;

implementation

uses
  Winapi.Windows, System.SysUtils, System.Classes, System.SyncObjs, System.IOUtils,
  SRFmxBridge.Api;

type
  { The Win64 @code(EXCEPTION_RECORD), declared here so it cannot be confused
    with the RTL's own @code(TExceptionRecord). }
  TSRExceptionRecord = record
    { Exception code, such as $C0000005 for an access violation. }
    ExceptionCode: DWORD;
    { Flags; 1 means the exception cannot be continued. }
    ExceptionFlags: DWORD;
    { A nested exception record. }
    NestedRecord: Pointer;
    { Address of the instruction that raised it. }
    ExceptionAddress: Pointer;
    { How many entries of @code(ExceptionInformation) are used. }
    NumberParameters: DWORD;
    { Extra information; for an access violation, [0] is 0 read, 1 write or
      8 execute, and [1] the address accessed. }
    ExceptionInformation: array[0..14] of NativeUInt;
  end;
  { Pointer to a @link(TSRExceptionRecord). }
  PSRExceptionRecord = ^TSRExceptionRecord;

  { The Win64 @code(EXCEPTION_POINTERS). }
  TSRExceptionPointers = record
    { The exception. }
    ExceptionRecord: PSRExceptionRecord;
    { The processor state (not used). }
    ContextRecord: Pointer;
  end;
  { Pointer to a @link(TSRExceptionPointers). }
  PSRExceptionPointers = ^TSRExceptionPointers;

  { Signature of a vectored exception handler or unhandled-exception filter. }
  TSRExceptionHandler = function(Info: PSRExceptionPointers): Longint; stdcall;

const
  { Let the next handler deal with the exception. }
  EXCEPTION_CONTINUE_SEARCH_ = 0;
  { GetModuleHandleEx: the name parameter is an address inside the module. }
  GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS_ = 4;
  { GetModuleHandleEx: do not add a reference to the module. }
  GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT_ = 2;
  { Most first-chance exceptions logged, so a flood cannot fill the disk. }
  MaxFirstChanceLogged = 40;

{ Adds a vectored exception handler (kernel32).
  @param(First nonzero to be called first)
  @param(Handler the handler)
  @returns(a handle, nil on failure) }
function SRAddVectoredExceptionHandler(First: ULONG; Handler: TSRExceptionHandler): Pointer;
  stdcall; external kernel32 name 'AddVectoredExceptionHandler';

{ Sets the unhandled-exception filter (kernel32).
  @param(Filter the filter)
  @returns(the previous filter) }
function SRSetUnhandledExceptionFilter(Filter: TSRExceptionHandler): Pointer;
  stdcall; external kernel32 name 'SetUnhandledExceptionFilter';

{ Finds the module containing an address (kernel32).
  @param(Flags GET_MODULE_HANDLE_EX_FLAG_... values)
  @param(Address the address)
  @param(Module receives the module)
  @returns(nonzero on success) }
function SRGetModuleHandleEx(Flags: DWORD; Address: Pointer; out Module: HMODULE): BOOL;
  stdcall; external kernel32 name 'GetModuleHandleExW';

var
  { Guards the file; re-entrant on one thread. }
  LogLock: TCriticalSection;
  { The open log file, nil when closed. }
  LogStream: TFileStream;
  { The log file's path. }
  LogName: string;
  { First-chance exceptions logged so far. }
  FirstChanceLogged: Integer;
  { Whether the handlers are installed. }
  HandlersInstalled: Boolean;
  { Whether the bridge is sending its lines here. }
  BridgeAttached: Boolean;

function DiagLogFileName: string;
begin
  Result := LogName;
end;

{ Appends a line to the file, under the lock.
  @param(Line the text, without a line ending) }
procedure WriteRaw(const Line: string);
var
  Bytes: TBytes;
begin
  if LogStream = nil then
    Exit;
  Bytes := TEncoding.UTF8.GetBytes(Line + #13#10);
  LogLock.Enter;
  try
    if LogStream <> nil then
      LogStream.WriteBuffer(Bytes[0], Length(Bytes));
  finally
    LogLock.Leave;
  end;
end;

procedure DiagLog(const Msg: string);
begin
  try
    WriteRaw(FormatDateTime('hh:nn:ss.zzz', Now) + ' t' + IntToStr(GetCurrentThreadId) + '  ' + Msg);
  except
    // Never let logging itself break the program
  end;
end;

procedure DiagLogArchive(const FileName: string);
var
  Folder, Stem, Ext, Target: string;
  Old: TStringList;
  F: TSearchRec;
begin
  if not FileExists(FileName) then
    Exit;
  Folder := IncludeTrailingPathDelimiter(ExtractFilePath(FileName)) + 'oldlogs';
  Stem := ChangeFileExt(ExtractFileName(FileName), '');
  Ext := ExtractFileExt(FileName);
  try
    ForceDirectories(Folder);
    Target := IncludeTrailingPathDelimiter(Folder) + Stem + '_' +
      FormatDateTime('yyyymmdd_hhnnss', TFile.GetLastWriteTime(FileName)) + Ext;
    if FileExists(Target) then
      System.SysUtils.DeleteFile(Target);
    TFile.Move(FileName, Target);
    // Keep the newest OldLogsKept; the names sort by time
    Old := TStringList.Create;
    try
      if FindFirst(IncludeTrailingPathDelimiter(Folder) + Stem + '_*' + Ext, faAnyFile, F) = 0 then
      try
        repeat
          Old.Add(F.Name);
        until FindNext(F) <> 0;
      finally
        FindClose(F);
      end;
      Old.Sort;
      while Old.Count > OldLogsKept do
      begin
        System.SysUtils.DeleteFile(IncludeTrailingPathDelimiter(Folder) + Old[0]);
        Old.Delete(0);
      end;
    finally
      Old.Free;
    end;
  except
    // An old log that cannot be moved is simply overwritten
  end;
end;

procedure DiagLogOpen(const FileName: string);
begin
  DiagLogClose;
  DiagLogArchive(FileName);
  LogName := FileName;
  LogStream := TFileStream.Create(FileName, fmCreate or fmShareDenyNone);
  DiagLog(Format('Log opened: %s, process %d', [ParamStr(0), GetCurrentProcessId]));
end;

procedure DiagLogClose;
begin
  if LogStream = nil then
    Exit;
  DiagLog('Log closed normally');
  LogLock.Enter;
  try
    FreeAndNil(LogStream);
  finally
    LogLock.Leave;
  end;
end;

{ Describes an address as module+offset.
  @param(Address the address)
  @returns(text such as SRFmxBridge.dll+$1A2B) }
function DescribeAddress(Address: Pointer): string;
var
  Module: HMODULE;
  Name: array[0..MAX_PATH] of Char;
begin
  if SRGetModuleHandleEx(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS_ or
    GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT_, Address, Module) and
    (GetModuleFileName(Module, Name, Length(Name)) > 0) then
    Result := Format('%s+$%x', [ExtractFileName(Name), Int64(NativeUInt(Address) - NativeUInt(Module))])
  else
    Result := Format('$%p (no module)', [Address]);
end;

{ Names the exception codes worth logging.
  @param(Code the exception code)
  @returns(a name, or empty for codes not logged) }
function SeriousExceptionName(Code: DWORD): string;
begin
  case Code of
    $C0000005: Result := 'ACCESS VIOLATION';
    $C00000FD: Result := 'STACK OVERFLOW';
    $C000001D: Result := 'ILLEGAL INSTRUCTION';
    $C0000096: Result := 'PRIVILEGED INSTRUCTION';
    $C0000094: Result := 'INTEGER DIVIDE BY ZERO';
    $C0000095: Result := 'INTEGER OVERFLOW';
    $C000008C..$C0000093, $C00002B4, $C00002B5: Result := 'FLOATING POINT EXCEPTION';
    $C0000374: Result := 'HEAP CORRUPTION';
    $C0000409: Result := 'STACK BUFFER OVERRUN / FAIL FAST';
    $C0000006: Result := 'IN-PAGE ERROR';
    $80000002: Result := 'DATATYPE MISALIGNMENT';
  else
    Result := '';
  end;
end;

{ Describes an exception for the log.
  @param(Rec the exception)
  @returns(one line) }
function DescribeException(Rec: PSRExceptionRecord): string;
var
  Kind: string;
begin
  Kind := SeriousExceptionName(Rec.ExceptionCode);
  if Kind = '' then
    Kind := 'exception';
  Result := Format('%s $%.8x at %s', [Kind, Rec.ExceptionCode, DescribeAddress(Rec.ExceptionAddress)]);
  if (Rec.ExceptionCode = $C0000005) and (Rec.NumberParameters >= 2) then
    case Integer(Rec.ExceptionInformation[0]) of
      0: Result := Result + Format(', reading $%x', [Int64(Rec.ExceptionInformation[1])]);
      1: Result := Result + Format(', writing $%x', [Int64(Rec.ExceptionInformation[1])]);
      8: Result := Result + Format(', executing $%x', [Int64(Rec.ExceptionInformation[1])]);
    end;
end;

{ Vectored handler: logs serious hardware exceptions when first raised.
  @param(Info the exception)
  @returns(always continue searching: the normal handling goes on) }
function FirstChanceHandler(Info: PSRExceptionPointers): Longint; stdcall;
begin
  Result := EXCEPTION_CONTINUE_SEARCH_;
  try
    if (Info <> nil) and (Info.ExceptionRecord <> nil) and
      (SeriousExceptionName(Info.ExceptionRecord.ExceptionCode) <> '') and
      (AtomicIncrement(FirstChanceLogged) <= MaxFirstChanceLogged) then
      DiagLog('FIRST CHANCE ' + DescribeException(Info.ExceptionRecord));
  except
  end;
end;

{ Unhandled-exception filter: logs the exception that is ending the program.
  @param(Info the exception)
  @returns(continue searching, so Windows reports the crash as usual) }
function LastChanceFilter(Info: PSRExceptionPointers): Longint; stdcall;
begin
  Result := EXCEPTION_CONTINUE_SEARCH_;
  try
    if (Info <> nil) and (Info.ExceptionRecord <> nil) then
      DiagLog('UNHANDLED (program ending) ' + DescribeException(Info.ExceptionRecord))
    else
      DiagLog('UNHANDLED exception (program ending), no details');
  except
  end;
end;

procedure DiagLogInstallCrashHandlers;
begin
  if HandlersInstalled then
    Exit;
  HandlersInstalled := True;
  if SRAddVectoredExceptionHandler(1, FirstChanceHandler) = nil then
    DiagLog('Could not install the vectored exception handler');
  SRSetUnhandledExceptionFilter(LastChanceFilter);
  DiagLog('Crash handlers installed');
end;

{ Receives the bridge's log lines, on any thread.
  @param(Line zero-terminated UTF-8) }
procedure BridgeLogLine(Line: PAnsiChar); cdecl;
begin
  DiagLog(UTF8ToString(Line));
end;

function DiagLogAttachBridge: Boolean;
begin
  Result := SRBridgeAvailable;
  if Result then
  begin
    srb_SetLogCallback(BridgeLogLine);
    BridgeAttached := True;
  end
  else
    DiagLog('Bridge log not attached: ' + SRBridgeLastError);
end;

initialization
  LogLock := TCriticalSection.Create;

finalization
  // Stop the bridge calling into a unit that is going away
  if BridgeAttached then
    srb_SetLogCallback(nil);
  DiagLogClose;
  FreeAndNil(LogLock);

end.

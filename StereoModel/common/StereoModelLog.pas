//** @abstract(StereoModel's log file: every status line, written as it happens.)
//**
//** LogOpen starts StereoModel.log, LogLine adds a line with the time, and LogClose ends it with
//** "Log closed normally", so a log without that line is from a run that crashed or was
//** stopped. Each line is flushed as it is written, so it survives a crash. The previous
//** run's log is kept as StereoModel.prev.log.
//**
//** @preformatted(
//** Windows, Linux   beside the executable, as FastMM5's leak log
//** macOS, mobile    the documents folder
//** )
//**
//** Main thread only: the form's status line is the one caller.
unit StereoModelLog;

{
  StereoModel's log file: every status line, written as it happens.

  LogOpen starts StereoModel.log, LogLine adds a line with the time, and
  LogClose ends it with "Log closed normally", so a log without that line
  is from a run that crashed or was stopped. Each line is flushed as it is
  written. The previous run's log is kept as StereoModel.prev.log.

    Windows, Linux   beside the executable, as FastMM5's leak log
    macOS, mobile    the documents folder

  Main thread only.
}

interface

//** @abstract(Starts the log, keeping the previous run's as StereoModel.prev.log, and writes
//** its first lines: the date, the build, whether a debugger is attached, the OS and the
//** executable.)
//**
//** Does nothing if the log is open already. If the file cannot be made the program carries
//** on without it, and LogFileName says where it would have been.
procedure LogOpen;

//** @abstract(Adds a line to the log, after the time of day; does nothing while it is
//** closed.)
//**
//** @param(AText The line.)
procedure LogLine(const AText: string);

//** @abstract(Ends the log with "Log closed normally" and closes the file.)
procedure LogClose;

//** @abstract(The log file's full path.)
//**
//** @returns(Where the log is, or would be.)
function LogFileName: string;

implementation

uses
  {$IFDEF MSWINDOWS}
  Winapi.Windows,
  {$ENDIF}
  System.SysUtils, System.Classes, System.IOUtils;

const
  //** @abstract(The log's file name.)
  LOG_FILE = 'StereoModel.log';
  //** @abstract(The previous run's log, kept beside it.)
  PREV_LOG_FILE = 'StereoModel.prev.log';

var
  //** @abstract(The open log; nil while closed.)
  Writer: TStreamWriter = nil;

//** @abstract(The folder the log goes in.)
//**
//** @returns(The executable's folder on Windows and Linux, the documents folder elsewhere.)
function LogFolder: string;
begin
  {$IF DEFINED(MSWINDOWS) or (DEFINED(LINUX) and not DEFINED(ANDROID))}
  Result := ExtractFileDir(ExpandFileName(ParamStr(0)));
  {$ELSE}
  Result := TPath.GetDocumentsPath;
  {$ENDIF}
end;

function LogFileName: string;
begin
  Result := TPath.Combine(LogFolder, LOG_FILE);
end;

procedure LogOpen;
var
  Name, Prev, Build, Debugger: string;
begin
  if Writer <> nil then
    Exit;
  Name := LogFileName;
  Prev := TPath.Combine(LogFolder, PREV_LOG_FILE);
  try
    if TFile.Exists(Name) then
    begin
      if TFile.Exists(Prev) then
        TFile.Delete(Prev);
      TFile.Move(Name, Prev);
    end;
    Writer := TStreamWriter.Create(Name, False, TEncoding.UTF8);
    Writer.AutoFlush := True;
  except
    // No log, but the program carries on
    FreeAndNil(Writer);
    Exit;
  end;
  {$IFDEF DEBUG}
  Build := 'Debug';
  {$ELSE}
  Build := 'Release';
  {$ENDIF}
  // Timings under the debugger are far slower (DLL loads), so say which
  {$IFDEF MSWINDOWS}
  if IsDebuggerPresent then
    Debugger := 'debugger attached'
  else
    Debugger := 'no debugger';
  {$ELSE}
  Debugger := 'debugger not checked';
  {$ENDIF}
  LogLine(Format('StereoModel log, %s, %s build, %s, %s', [FormatDateTime('yyyy-mm-dd', Now),
    Build, Debugger, TOSVersion.ToString]));
  LogLine('Executable ' + ExpandFileName(ParamStr(0)));
end;

procedure LogLine(const AText: string);
begin
  if Writer = nil then
    Exit;
  try
    Writer.WriteLine(FormatDateTime('hh:nn:ss.zzz', Now) + '  ' + AText);
  except
    // A full disk must not stop the program
  end;
end;

procedure LogClose;
begin
  if Writer = nil then
    Exit;
  LogLine('Log closed normally');
  FreeAndNil(Writer);
end;

initialization

finalization
  // Closed by the form normally; this only frees the writer after a fault
  FreeAndNil(Writer);

end.

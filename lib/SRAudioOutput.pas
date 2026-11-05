{ @abstract(Plays sound on Windows' default output device through WASAPI
  (shared mode), and gives the playing position as a clock; no FMX or VCL.)

  @link(TSRAudioOutput) opens the default output device in shared mode at the
  device's own rate and channel count, as 32-bit float samples, so Windows
  converts nothing. A decoder writes interleaved samples into its ring buffer
  (@link(TSRAudioOutput.Write)); a thread of its own feeds the device as
  WASAPI asks (event driven). @link(TSRAudioOutput.Clock) is the film time of
  the sound being heard now, from what has really reached the device, so
  pictures timed by it stay in step with the sound. Every WASAPI call is made
  on the output thread. Windows only. }
unit SRAudioOutput;

interface

uses
  Winapi.Windows, System.SysUtils, System.Classes, System.SyncObjs, System.Diagnostics;

type
  { Declared ahead for @link(TSRAudioThread). }
  TSRAudioOutput = class;

  { The thread that owns the WASAPI objects of one @link(TSRAudioOutput). }
  TSRAudioThread = class(TThread)
  private
    { The output it works for. }
    FOwner: TSRAudioOutput;
  protected
    { Opens the device, reports whether that worked, then feeds the device
      from the ring buffer whenever it asks, until @code(Terminate). }
    procedure Execute; override;
  public
    { Creates the thread, running.
      @param(Owner the output, which outlives the thread) }
    constructor Create(Owner: TSRAudioOutput);
  end;

  { Sound playing on the default output device, fed from a ring buffer. }
  TSRAudioOutput = class
  private
    { The output thread. }
    FThread: TSRAudioThread;
    { Guards the ring buffer and the clock. }
    FLock: TCriticalSection;
    { Set by the thread once the device is open (or failed to open). }
    FReady: TEvent;
    { Set when the ring buffer has room. }
    FSpace: TEvent;
    { Why the device could not be opened, empty if it was. }
    FOpenError: string;
    { See @link(TSRAudioOutput.SampleRate). }
    FRate: Integer;
    { See @link(TSRAudioOutput.Channels). }
    FChannels: Integer;
    { The device's channel mask, from its mix format. }
    FChannelMask: Cardinal;
    { See @link(TSRAudioOutput.Description). }
    FDescription: string;
    { The ring buffer: @link(FRingFrames) frames of @link(FChannels) floats. }
    FRing: TArray<Single>;
    { Frames the ring buffer holds at most. }
    FRingFrames: Integer;
    { Where the next frame is read from and how many are waiting. }
    FReadPos, FFill: Integer;
    { The film time of the first frame written, seconds. }
    FStartTime: Double;
    { Frames of real sound handed to the device so far. }
    FRealWritten: Int64;
    { Frames of real sound the device had played at its last report. }
    FPlayed: Int64;
    { Times @link(FPlayed) was last updated, for smoothing between reports. }
    FPlayedClock: TStopwatch;
    { Whether the device is playing (not paused, not yet started). }
    FPlaying: Boolean;
    { Whether playing has been asked for. }
    FWantPlay: Boolean;
    { Whether the decoder has written its last frame. }
    FEnded: Boolean;
    { Whether every written frame has been played. }
    FDrained: Boolean;
    { Times the device asked for sound and the ring buffer had too little. }
    FUnderruns: Int64;
    { The thread's first error while playing, empty if none. }
    FError: string;
  public
    { Opens the default output device and starts the output thread, paused.
      @param(BufferSeconds how much sound the ring buffer holds)
      @raises(Exception saying which WASAPI step failed, if no device can be
        opened) }
    constructor Create(BufferSeconds: Double);
    { Stops playing and closes the device. }
    destructor Destroy; override;
    { Sets the film time of the first frame to be written; call before the
      first @link(TSRAudioOutput.Write).
      @param(Seconds the time) }
    procedure SetStartTime(Seconds: Double);
    { Copies interleaved float frames into the ring buffer, waiting while it
      is full.
      @param(Src the first sample, @link(TSRAudioOutput.Channels) floats a
        frame)
      @param(Frames how many frames)
      @param(Cancel called while waiting; @true stops the wait)
      @returns(@false if Cancel stopped it before every frame was written) }
    function Write(Src: PSingle; Frames: Integer; const Cancel: TFunc<Boolean>): Boolean;
    { Marks the end of the sound: what is in the ring buffer still plays. }
    procedure MarkEnd;
    { Starts or resumes playing. }
    procedure Play;
    { Pauses playing; the clock stops. }
    procedure Pause;
    { The film time of the sound being heard now, seconds: the start time
      plus the real sound played, smoothed between the device's reports.
      Before playing starts it is the start time. }
    function Clock: Double;
    { Seconds of sound waiting in the ring buffer. }
    function Buffered: Double;
    { @returns(@true once the end was marked and every frame played) }
    function Drained: Boolean;
    { Times the device ran short of sound (each fills with silence). }
    function Underruns: Int64;
    { The output thread's first error while playing, empty if none. }
    function LastError: string;
    { The device's sample rate, frames a second. }
    property SampleRate: Integer read FRate;
    { The device's channel count; frames are this many floats. }
    property Channels: Integer read FChannels;
    { One line about the device for the log. }
    property Description: string read FDescription;
  end;

implementation

uses
  Winapi.ActiveX, Winapi.MMSystem, System.Math;

const
  { The MMDevice enumerator. }
  CLSID_MMDeviceEnumerator: TGUID = '{BCDE0395-E52F-467C-8E3D-C4579291692E}';
  { IAudioClient, for IMMDevice.Activate. }
  IID_IAudioClient: TGUID = '{1CB9AD4C-DBFA-4C32-B178-C2F568A703B2}';
  { IAudioRenderClient, for IAudioClient.GetService. }
  IID_IAudioRenderClient: TGUID = '{F294ACFC-3146-4483-A7BF-ADDCA7C260E2}';
  { IAudioClock, for IAudioClient.GetService. }
  IID_IAudioClock: TGUID = '{CD63314F-3FBA-4A1B-812C-EF96358728E7}';
  { 32-bit float samples, in WAVEFORMATEXTENSIBLE.SubFormat. }
  KSDATAFORMAT_SUBTYPE_IEEE_FLOAT: TGUID = '{00000003-0000-0010-8000-00AA00389B71}';
  { EDataFlow: output. }
  eRender = 0;
  { ERole: the console default. }
  eConsole = 0;
  { AUDCLNT_SHAREMODE: shared with other programs. }
  AUDCLNT_SHAREMODE_SHARED = 0;
  { The device signals an event when it wants more sound. }
  AUDCLNT_STREAMFLAGS_EVENTCALLBACK = $00040000;
  { Windows converts the format if it must. }
  AUDCLNT_STREAMFLAGS_AUTOCONVERTPCM = $80000000;
  { With AUTOCONVERTPCM: good quality rate conversion. }
  AUDCLNT_STREAMFLAGS_SRC_DEFAULT_QUALITY = $08000000;
  { ReleaseBuffer: the frames are silence. }
  AUDCLNT_BUFFERFLAGS_SILENT = 2;
  { WAVEFORMATEX.wFormatTag of a WAVEFORMATEXTENSIBLE. }
  WAVE_FORMAT_EXTENSIBLE = $FFFE;
  { The device's buffer asked for: 100 ms, in 100-ns units. }
  DeviceBufferHns = 1000000;

type
  { WAVEFORMATEXTENSIBLE: a WAVEFORMATEX (packed, 18 bytes) and the rest. }
  TWaveFormatExtensible = packed record
    { The basic format. }
    Format: TWaveFormatEx;
    { Bits that carry the sample. }
    wValidBitsPerSample: Word;
    { Which speakers the channels are. }
    dwChannelMask: DWORD;
    { The sample type. }
    SubFormat: TGUID;
  end;
  { A pointer to a @link(TWaveFormatExtensible). }
  PWaveFormatExtensible = ^TWaveFormatExtensible;

  { An audio endpoint (mmdeviceapi.h). }
  IMMDevice = interface(IUnknown)
    ['{D666063F-1587-4E43-81F1-B948E807363F}']
    { Makes an object on the device.
      @returns(an HRESULT) }
    function Activate(const iid: TGUID; dwClsCtx: DWORD; pActivationParams: Pointer;
      out ppInterface): HRESULT; stdcall;
    { Not used.
      @returns(an HRESULT) }
    function OpenPropertyStore(stgmAccess: DWORD; out ppProperties: IUnknown): HRESULT; stdcall;
    { Not used.
      @returns(an HRESULT) }
    function GetId(out ppstrId: PWideChar): HRESULT; stdcall;
    { Not used.
      @returns(an HRESULT) }
    function GetState(out pdwState: DWORD): HRESULT; stdcall;
  end;

  { Finds audio endpoints (mmdeviceapi.h). }
  IMMDeviceEnumerator = interface(IUnknown)
    ['{A95664D2-9614-4F35-A746-DE8DB63617E6}']
    { Not used.
      @returns(an HRESULT) }
    function EnumAudioEndpoints(dataFlow: Integer; dwStateMask: DWORD;
      out ppDevices: IUnknown): HRESULT; stdcall;
    { The default endpoint for a direction and role.
      @returns(an HRESULT) }
    function GetDefaultAudioEndpoint(dataFlow, role: Integer;
      out ppEndpoint: IMMDevice): HRESULT; stdcall;
    { Not used.
      @returns(an HRESULT) }
    function GetDevice(pwstrId: PWideChar; out ppDevice: IMMDevice): HRESULT; stdcall;
    { Not used.
      @returns(an HRESULT) }
    function RegisterEndpointNotificationCallback(pClient: IUnknown): HRESULT; stdcall;
    { Not used.
      @returns(an HRESULT) }
    function UnregisterEndpointNotificationCallback(pClient: IUnknown): HRESULT; stdcall;
  end;

  { A stream on an endpoint (audioclient.h). }
  IAudioClient = interface(IUnknown)
    ['{1CB9AD4C-DBFA-4C32-B178-C2F568A703B2}']
    { Opens the stream.
      @returns(an HRESULT) }
    function Initialize(ShareMode: Integer; StreamFlags: DWORD; hnsBufferDuration,
      hnsPeriodicity: Int64; pFormat: PWaveFormatEx; AudioSessionGuid: PGUID): HRESULT; stdcall;
    { The device buffer's size in frames.
      @returns(an HRESULT) }
    function GetBufferSize(out NumBufferFrames: UINT32): HRESULT; stdcall;
    { Not used.
      @returns(an HRESULT) }
    function GetStreamLatency(out phnsLatency: Int64): HRESULT; stdcall;
    { Frames in the device buffer not yet played.
      @returns(an HRESULT) }
    function GetCurrentPadding(out NumPaddingFrames: UINT32): HRESULT; stdcall;
    { Not used.
      @returns(an HRESULT) }
    function IsFormatSupported(ShareMode: Integer; pFormat: PWaveFormatEx;
      out ppClosestMatch: PWaveFormatEx): HRESULT; stdcall;
    { The shared-mode mix format; free it with CoTaskMemFree.
      @returns(an HRESULT) }
    function GetMixFormat(out ppDeviceFormat: PWaveFormatEx): HRESULT; stdcall;
    { Not used.
      @returns(an HRESULT) }
    function GetDevicePeriod(out phnsDefaultDevicePeriod,
      phnsMinimumDevicePeriod: Int64): HRESULT; stdcall;
    { Starts the stream.
      @returns(an HRESULT) }
    function Start: HRESULT; stdcall;
    { Stops the stream, keeping what is buffered.
      @returns(an HRESULT) }
    function Stop: HRESULT; stdcall;
    { Not used.
      @returns(an HRESULT) }
    function Reset: HRESULT; stdcall;
    { The event signalled when the device wants more.
      @returns(an HRESULT) }
    function SetEventHandle(eventHandle: THandle): HRESULT; stdcall;
    { Another interface on the stream.
      @returns(an HRESULT) }
    function GetService(const riid: TGUID; out ppv): HRESULT; stdcall;
  end;

  { Writes into the device buffer (audioclient.h). }
  IAudioRenderClient = interface(IUnknown)
    ['{F294ACFC-3146-4483-A7BF-ADDCA7C260E2}']
    { The next free part of the device buffer.
      @returns(an HRESULT) }
    function GetBuffer(NumFramesRequested: UINT32; out ppData: PByte): HRESULT; stdcall;
    { Hands the part back, filled.
      @returns(an HRESULT) }
    function ReleaseBuffer(NumFramesWritten: UINT32; dwFlags: DWORD): HRESULT; stdcall;
  end;

{ Raises an exception if a WASAPI call failed.
  @param(HR its result)
  @param(Step what was being done) }
procedure CheckHR(HR: HRESULT; const Step: string);
begin
  if Failed(HR) then
    raise Exception.CreateFmt('sound output: %s failed (HRESULT $%.8x, %s)',
      [Step, Cardinal(HR), SysErrorMessage(Cardinal(HR))]);
end;

{ TSRAudioThread }

constructor TSRAudioThread.Create(Owner: TSRAudioOutput);
begin
  FOwner := Owner;
  inherited Create(False);
end;

procedure TSRAudioThread.Execute;
var
  O: TSRAudioOutput;
  Enum: IMMDeviceEnumerator;
  Device: IMMDevice;
  Client: IAudioClient;
  Render: IAudioRenderClient;
  Mix: PWaveFormatEx;
  Fmt: TWaveFormatExtensible;
  WakeEvent: THandle;
  BufferFrames, Padding: UINT32;
  Want, Real, I, Chunk: Integer;
  Data: PByte;
  Dst: PSingle;
  Running: Boolean;
begin
  NameThreadForDebugging('SRAudioOutput');
  O := FOwner;
  WakeEvent := 0;
  Running := False;
  CoInitializeEx(nil, COINIT_MULTITHREADED);
  try
    // Open the default output device at its own mix rate and channels, as
    // floats, so Windows has nothing to convert
    try
      CheckHR(CoCreateInstance(CLSID_MMDeviceEnumerator, nil, CLSCTX_ALL, IMMDeviceEnumerator, Enum),
        'creating the device enumerator');
      CheckHR(Enum.GetDefaultAudioEndpoint(eRender, eConsole, Device), 'finding the default output device');
      CheckHR(Device.Activate(IID_IAudioClient, CLSCTX_ALL, nil, Client), 'opening the device');
      CheckHR(Client.GetMixFormat(Mix), 'reading its mix format');
      try
        O.FRate := Mix.nSamplesPerSec;
        O.FChannels := Mix.nChannels;
        if (Mix.wFormatTag = WAVE_FORMAT_EXTENSIBLE) and (Mix.cbSize >= 22) then
          O.FChannelMask := PWaveFormatExtensible(Mix).dwChannelMask
        else if O.FChannels = 1 then
          O.FChannelMask := $4
        else
          O.FChannelMask := $3;
      finally
        CoTaskMemFree(Mix);
      end;
      FillChar(Fmt, SizeOf(Fmt), 0);
      Fmt.Format.wFormatTag := WAVE_FORMAT_EXTENSIBLE;
      Fmt.Format.nChannels := O.FChannels;
      Fmt.Format.nSamplesPerSec := O.FRate;
      Fmt.Format.wBitsPerSample := 32;
      Fmt.Format.nBlockAlign := O.FChannels * 4;
      Fmt.Format.nAvgBytesPerSec := O.FRate * Fmt.Format.nBlockAlign;
      Fmt.Format.cbSize := 22;
      Fmt.wValidBitsPerSample := 32;
      Fmt.dwChannelMask := O.FChannelMask;
      Fmt.SubFormat := KSDATAFORMAT_SUBTYPE_IEEE_FLOAT;
      CheckHR(Client.Initialize(AUDCLNT_SHAREMODE_SHARED, AUDCLNT_STREAMFLAGS_EVENTCALLBACK or
        AUDCLNT_STREAMFLAGS_AUTOCONVERTPCM or AUDCLNT_STREAMFLAGS_SRC_DEFAULT_QUALITY,
        DeviceBufferHns, 0, @Fmt, nil), 'starting a shared stream (32-bit float)');
      CheckHR(Client.GetBufferSize(BufferFrames), 'reading its buffer size');
      WakeEvent := CreateEvent(nil, False, False, nil);
      CheckHR(Client.SetEventHandle(WakeEvent), 'setting its event');
      CheckHR(Client.GetService(IID_IAudioRenderClient, Render), 'getting its render client');
      O.FDescription := Format('default output device, %d Hz, %d channels (mask $%x), 32-bit float, ' +
        'device buffer %d frames (%.0f ms), shared mode', [O.FRate, O.FChannels, O.FChannelMask,
        BufferFrames, BufferFrames * 1000 / O.FRate]);
    except
      on E: Exception do
      begin
        O.FOpenError := E.Message;
        O.FReady.SetEvent;
        Exit;
      end;
    end;
    O.FReady.SetEvent;

    while not Terminated do
    begin
      WaitForSingleObject(WakeEvent, 20);
      // Start or pause as asked
      O.FLock.Enter;
      try
        if O.FWantPlay <> Running then
        begin
          if O.FWantPlay then
          begin
            if Succeeded(Client.Start) then
              Running := True;
          end
          else
          begin
            Client.Stop;
            Running := False;
          end;
          O.FPlaying := Running;
          O.FPlayedClock := TStopwatch.StartNew;
        end;
      finally
        O.FLock.Leave;
      end;
      if not Running then
        Continue;
      if Failed(Client.GetCurrentPadding(Padding)) then
        Continue;
      Want := BufferFrames - Padding;
      O.FLock.Enter;
      try
        // Real sound played so far: handed over, less what still waits in the
        // device buffer (silence is only ever written when nothing real waits)
        O.FPlayed := Max(O.FPlayed, O.FRealWritten - Int64(Padding));
        O.FPlayedClock := TStopwatch.StartNew;
        if O.FEnded and (O.FFill = 0) and (Padding = 0) then
          O.FDrained := True;
      finally
        O.FLock.Leave;
      end;
      if Want <= 0 then
        Continue;
      if Failed(Render.GetBuffer(Want, Data)) then
        Continue;
      O.FLock.Enter;
      try
        Real := Min(Want, O.FFill);
        Dst := PSingle(Data);
        // Copy from the ring buffer, in at most two pieces (it wraps)
        I := Real;
        while I > 0 do
        begin
          Chunk := Min(I, O.FRingFrames - O.FReadPos);
          Move(O.FRing[O.FReadPos * O.FChannels], Dst^, Chunk * O.FChannels * SizeOf(Single));
          Inc(Dst, Chunk * O.FChannels);
          O.FReadPos := (O.FReadPos + Chunk) mod O.FRingFrames;
          Dec(I, Chunk);
        end;
        Dec(O.FFill, Real);
        Inc(O.FRealWritten, Real);
        if (Real < Want) and not O.FEnded then
          Inc(O.FUnderruns);
      finally
        O.FLock.Leave;
      end;
      // The rest, if the ring ran short, as silence
      if Real < Want then
        FillChar(Dst^, (Want - Real) * O.FChannels * SizeOf(Single), 0);
      Render.ReleaseBuffer(Want, 0);
      O.FSpace.SetEvent;
    end;
  finally
    if Running and (Client <> nil) then
      Client.Stop;
    Render := nil;
    Client := nil;
    Device := nil;
    Enum := nil;
    if WakeEvent <> 0 then
      CloseHandle(WakeEvent);
    CoUninitialize;
  end;
end;

{ TSRAudioOutput }

constructor TSRAudioOutput.Create(BufferSeconds: Double);
begin
  inherited Create;
  FLock := TCriticalSection.Create;
  FReady := TEvent.Create(nil, True, False, '');
  FSpace := TEvent.Create(nil, False, False, '');
  FThread := TSRAudioThread.Create(Self);
  if FReady.WaitFor(5000) <> wrSignaled then
    raise Exception.Create('sound output: the device did not open within 5 s');
  if FOpenError <> '' then
    raise Exception.Create(FOpenError);
  FRingFrames := Max(FRate div 10, Round(FRate * BufferSeconds));
  SetLength(FRing, FRingFrames * FChannels);
end;

destructor TSRAudioOutput.Destroy;
begin
  if FThread <> nil then
  begin
    FThread.Terminate;
    FThread.WaitFor;
    FreeAndNil(FThread);
  end;
  FSpace.Free;
  FReady.Free;
  FLock.Free;
  inherited;
end;

procedure TSRAudioOutput.SetStartTime(Seconds: Double);
begin
  FLock.Enter;
  try
    FStartTime := Seconds;
  finally
    FLock.Leave;
  end;
end;

function TSRAudioOutput.Write(Src: PSingle; Frames: Integer; const Cancel: TFunc<Boolean>): Boolean;
var
  Chunk, WritePos: Integer;
begin
  while Frames > 0 do
  begin
    FLock.Enter;
    try
      // Room up to the end of the ring, or up to the read position
      WritePos := (FReadPos + FFill) mod FRingFrames;
      Chunk := Min(Frames, Min(FRingFrames - FFill, FRingFrames - WritePos));
      if Chunk > 0 then
      begin
        Move(Src^, FRing[WritePos * FChannels], Chunk * FChannels * SizeOf(Single));
        Inc(FFill, Chunk);
      end;
    finally
      FLock.Leave;
    end;
    if Chunk > 0 then
    begin
      Inc(Src, Chunk * FChannels);
      Dec(Frames, Chunk);
    end
    else
    begin
      if Cancel() then
        Exit(False);
      FSpace.WaitFor(20);
    end;
  end;
  Result := True;
end;

procedure TSRAudioOutput.MarkEnd;
begin
  FLock.Enter;
  try
    FEnded := True;
  finally
    FLock.Leave;
  end;
end;

procedure TSRAudioOutput.Play;
begin
  FLock.Enter;
  try
    FWantPlay := True;
  finally
    FLock.Leave;
  end;
end;

procedure TSRAudioOutput.Pause;
begin
  FLock.Enter;
  try
    FWantPlay := False;
  finally
    FLock.Leave;
  end;
end;

function TSRAudioOutput.Clock: Double;
var
  Frames: Double;
begin
  FLock.Enter;
  try
    Frames := FPlayed;
    // Between the device's reports (every 10 ms or so) the sound plays on;
    // never past what has really been handed over
    if FPlaying then
      Frames := Min(Frames + FPlayedClock.ElapsedTicks / TStopwatch.Frequency * FRate,
        FRealWritten);
    Result := FStartTime + Frames / FRate;
  finally
    FLock.Leave;
  end;
end;

function TSRAudioOutput.Buffered: Double;
begin
  FLock.Enter;
  try
    Result := FFill / FRate;
  finally
    FLock.Leave;
  end;
end;

function TSRAudioOutput.Drained: Boolean;
begin
  FLock.Enter;
  try
    Result := FDrained;
  finally
    FLock.Leave;
  end;
end;

function TSRAudioOutput.Underruns: Int64;
begin
  FLock.Enter;
  try
    Result := FUnderruns;
  finally
    FLock.Leave;
  end;
end;

function TSRAudioOutput.LastError: string;
begin
  FLock.Enter;
  try
    Result := FError;
  finally
    FLock.Leave;
  end;
end;

end.

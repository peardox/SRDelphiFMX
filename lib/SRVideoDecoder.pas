{ @abstract(Plays a film with FFmpeg: its pictures as BGRA frames and its
  sound through @link(SRAudioOutput), the pictures timed by the sound; no FMX
  or VCL.)

  @link(TSRVideoDecoder) opens a film and runs three threads: a reader that
  sorts the film's packets into a picture queue and a sound queue (so neither
  stream can starve the other), a picture decoder that converts each picture
  to BGRA (4 bytes a pixel: blue, green, red, alpha, top row first, rows
  padded to @link(SRVideoRowAlign)) into a small queue, and a sound decoder
  that converts the sound with swresample to the output device's own format
  and plays it through @link(TSRAudioOutput).

  The sound is the clock: @link(TSRVideoDecoder.TakeFrame), called as often
  as the program draws, gives the newest picture whose time has come by the
  sound being heard, so pictures stay in step with it. Without sound (no
  sound track, no output device) and after the sound ends, a wall clock runs
  instead. Buffers change hands (@link(TSRVideoDecoder.TakeFrame) swaps the
  caller's old one in), so playing allocates nothing once the queue is full.

  FFmpeg is loaded once, by @link(TSRVideoDecoder.LoadLibraries), from the
  program's own folder: the headers in @code(ffmpeg-headers) import every
  routine @code(delayed), so the program starts without the DLLs, and this
  unit checks each DLL itself first, so a missing or 32-bit one is named in
  the log. Windows only. }
unit SRVideoDecoder;

interface

uses
  System.SysUtils, System.Classes, System.SyncObjs, System.Diagnostics,
  System.Generics.Collections, SRAudioOutput;

const
  { Decoded pictures held ready ahead of the clock. }
  SRVideoQueueSize = 4;
  { Each converted row's length in bytes is rounded up to a multiple of this,
    and this many spare bytes follow the last row: swscale writes rows with
    SIMD instructions that run past the end of a row whose length is not a
    multiple (1916 pixels a row, 7664 bytes, overwrote the next heap block). }
  SRVideoRowAlign = 64;

type
  { Declared ahead for @link(TSRDecoderThread). }
  TSRVideoDecoder = class;

  { One of a @link(TSRVideoDecoder)'s three threads: the reader, the picture
    decoder or the sound decoder. }
  TSRDecoderThread = class(TThread)
  private
    { The decoder it works for. }
    FOwner: TSRVideoDecoder;
    { 0 the reader, 1 the picture decoder, 2 the sound decoder. }
    FKind: Integer;
  protected
    { Runs the decoder's loop for this thread's kind. }
    procedure Execute; override;
  public
    { Creates the thread, running.
      @param(Owner the decoder, which outlives the thread)
      @param(Kind 0 the reader, 1 the picture decoder, 2 the sound decoder) }
    constructor Create(Owner: TSRVideoDecoder; Kind: Integer);
  end;

  { A queue of FFmpeg packets (@code(AVPacket) pointers, owned by the queue
    until taken) between the reader and one decoder. }
  TSRPacketQueue = class
  private
    { Guards the queue. }
    FLock: TCriticalSection;
    { Set when a packet is added or the end is marked. }
    FData: TEvent;
    { The packets, oldest first. }
    FItems: TQueue<Pointer>;
    { The packets' data bytes. }
    FBytes: Int64;
    { Whether the reader has added its last packet. }
    FEnded: Boolean;
  public
    { Creates an empty queue. }
    constructor Create;
    { Frees the queue and any packets left in it. }
    destructor Destroy; override;
    { Adds a packet; the queue owns it until it is taken.
      @param(Packet an @code(AVPacket) from @code(av_packet_alloc)) }
    procedure Put(Packet: Pointer);
    { Marks that no more packets will come. }
    procedure MarkEnd;
    { Takes the oldest packet, waiting for one.
      @param(Packet receives it; the caller frees it with
        @code(av_packet_free))
      @param(Thread the waiting thread, to see when it is told to stop)
      @returns(1 for a packet, 0 at the end of the film, -1 if the thread was
        told to stop) }
    function Get(out Packet: Pointer; Thread: TSRDecoderThread): Integer;
    { Packets waiting. }
    function Count: Integer;
    { Their data bytes. }
    function Bytes: Int64;
  end;

  { One decoded picture waiting in the queue. }
  TSRVideoSlot = record
    { The picture, @link(TSRVideoSlot.Pitch) bytes a row. }
    Pixels: TBytes;
    { Bytes from one row to the next: @code(W * 4) rounded up to a multiple
      of @code(SRVideoRowAlign). }
    Pitch: Integer;
    { Its width in pixels. }
    W: Integer;
    { Its height in pixels. }
    H: Integer;
    { When it is due, seconds of film time. }
    Seconds: Double;
  end;

  { One film being played: opened at creation, read and decoded on threads,
    and timed by its sound. }
  TSRVideoDecoder = class
  private
    { The film's @code(AVFormatContext). }
    FFormat: Pointer;
    { The picture decoder's @code(AVCodecContext). }
    FCodecCtx: Pointer;
    { The sound decoder's @code(AVCodecContext), nil without sound. }
    FAudioCtx: Pointer;
    { The picture stream's index in the film. }
    FStreamIndex: Integer;
    { The sound stream's index, -1 without sound. }
    FAudioIndex: Integer;
    { Seconds per tick of the picture stream's time base. }
    FTimeBase: Double;
    { Seconds per tick of the sound stream's time base. }
    FAudioTimeBase: Double;
    { The film's start time, seconds: film time 0. }
    FOrigin: Double;
    { See @link(TSRVideoDecoder.Width). }
    FWidth: Integer;
    { See @link(TSRVideoDecoder.Height). }
    FHeight: Integer;
    { See @link(TSRVideoDecoder.FrameRate). }
    FFrameRate: Double;
    { See @link(TSRVideoDecoder.Duration). }
    FDuration: Double;
    { See @link(TSRVideoDecoder.Description). }
    FDescription: string;
    { See @link(TSRVideoDecoder.AudioDescription). }
    FAudioDescription: string;
    { The sound output, nil without sound. }
    FAudio: TSRAudioOutput;
    { Whether the sound has been started (once enough is buffered). }
    FAudioStarted: Boolean;
    { Whether the sound is the clock: it exists and has not yet ended. }
    FAudioClock: Boolean;
    { The reader, picture decoder and sound decoder threads. }
    FReader, FVideoThread, FAudioThread: TSRDecoderThread;
    { Packets for the picture decoder. }
    FVideoPackets: TSRPacketQueue;
    { Packets for the sound decoder, nil without sound. }
    FAudioPackets: TSRPacketQueue;
    { Guards the picture queue and everything the threads report. }
    FLock: TCriticalSection;
    { Set when the picture queue has room. }
    FRoom: TEvent;
    { The picture queue: @link(FCount) pictures from @link(FHead) on, in time
      order. }
    FSlots: array[0..SRVideoQueueSize - 1] of TSRVideoSlot;
    { The oldest picture in the queue. }
    FHead: Integer;
    { Pictures in the queue. }
    FCount: Integer;
    { Whether the picture decoder has stopped: the film ended, or an error. }
    FFinished: Boolean;
    { See @link(TSRVideoDecoder.LastError). }
    FError: string;
    { See @link(TSRVideoDecoder.ColourNote). }
    FColourNote: string;
    { See @link(TSRVideoDecoder.AudioNote). }
    FAudioNote: string;
    { Pictures decoded, shown and dropped. }
    FDecoded, FShown, FDropped: Int64;
    { Packets a decoder refused (damaged), so skipped. }
    FBadPackets: Int64;
    { The wall clock: runs while playing without sound. }
    FClock: TStopwatch;
    { Whether the wall clock has started (at the first picture). }
    FClockStarted: Boolean;
    { Whether playing is paused. }
    FPaused: Boolean;
    { The film time when @link(FClock) last started, seconds. }
    FClockBase: Double;
    { The reader's loop: sorts packets into the two queues, keeping each fed
      without reading the whole film into memory.
      @param(T its thread) }
    procedure ReadLoop(T: TSRDecoderThread);
    { The picture decoder's loop: decodes, converts to BGRA and queues.
      @param(T its thread) }
    procedure VideoLoop(T: TSRDecoderThread);
    { The sound decoder's loop: decodes, converts to the device's format and
      plays.
      @param(T its thread) }
    procedure AudioLoop(T: TSRDecoderThread);
    { Reserves the next free picture slot, waiting for room.
      @param(Thread the picture thread, to see when it is told to stop)
      @returns(the slot's index, or -1 if the thread was told to stop) }
    function WaitForRoom(Thread: TSRDecoderThread): Integer;
    { Puts a converted picture into the queue.
      @param(Slot the slot from @link(WaitForRoom))
      @param(W its width)
      @param(H its height)
      @param(Pitch its bytes from one row to the next)
      @param(Seconds when it is due) }
    procedure Publish(Slot, W, H, Pitch: Integer; Seconds: Double);
    { Records an error from a thread; the first one is kept.
      @param(Msg what went wrong) }
    procedure SetError(const Msg: string);
    { Counts a packet a decoder refused. }
    procedure CountBadPacket;
    { The film time now, seconds: the sound's clock while it plays, else the
      wall clock. Main thread. }
    function ClockNow: Double;
  public
    { Loads FFmpeg's DLLs (avutil, swresample, avcodec, avformat, swscale)
      from the program's folder, once: after it has succeeded it does
      nothing more. Each DLL is checked and loaded by its full path, so a
      missing one, a 32-bit one or one missing a DLL of its own is named;
      the delayed imports then use the loaded DLLs.
      @param(Report receives a line for the log: the versions and licence,
        or exactly what failed)
      @returns(@true if FFmpeg can be used) }
    class function LoadLibraries(out Report: string): Boolean; static;
    { @returns(@true once @link(TSRVideoDecoder.LoadLibraries) has
      succeeded) }
    class function LibrariesLoaded: Boolean; static;
    { Opens a film, its sound on the default output device (if it has sound
      and the device opens; otherwise it plays silent, and
      @link(TSRVideoDecoder.AudioNote) says why), and starts reading and
      decoding ahead. @link(TSRVideoDecoder.LoadLibraries) must have
      succeeded.
      @param(FileName the film's full path)
      @raises(Exception saying which step failed and FFmpeg's reason) }
    constructor Create(const FileName: string);
    { Stops the threads and the sound and closes the film. }
    destructor Destroy; override;
    { Gives the newest picture whose time has come, if it is not the one
      already given. Pictures before it that were never given are counted as
      dropped. Call it every time the program draws.
      @param(Pixels the caller's previous picture buffer (or nil), given back
        to the queue for reuse; receives the new picture, Pitch bytes a row)
      @param(W receives its width in pixels)
      @param(H receives its height in pixels)
      @param(Pitch receives the bytes from one row to the next (at least
        @code(W * 4)))
      @param(Seconds receives when it was due)
      @returns(@true if a new picture was given; @false leaves Pixels alone) }
    function TakeFrame(var Pixels: TBytes; out W, H, Pitch: Integer;
      out Seconds: Double): Boolean;
    { Pauses or resumes the film, sound and clock; decoding carries on until
      the queues are full.
      @param(Value @true to pause) }
    procedure SetPaused(Value: Boolean);
    { The film time now, seconds. }
    function Position: Double;
    { @returns(@true once every picture has been decoded and given) }
    function AtEnd: Boolean;
    { The first error a thread met, empty if none. }
    function LastError: string;
    { How the pictures' colour is converted, set by the picture thread when
      it meets the first picture (and if the format changes), empty before. }
    function ColourNote: string;
    { How the sound is converted, or why there is none; set when the sound
      thread meets the first sound, or at opening when there is no sound. }
    function AudioNote: string;
    { Pictures decoded so far. }
    function Decoded: Int64;
    { Pictures given by @link(TSRVideoDecoder.TakeFrame) so far. }
    function Shown: Int64;
    { Pictures whose time passed before they could be given. }
    function Dropped: Int64;
    { Packets the decoders refused (damaged), so skipped. }
    function BadPackets: Int64;
    { Times the sound device ran short (each is a moment of silence); 0
      without sound. }
    function Underruns: Int64;
    { @returns(@true if the film's sound is playing through the device) }
    function HasSound: Boolean;
    { The pictures' width in pixels. }
    property Width: Integer read FWidth;
    { The pictures' height in pixels. }
    property Height: Integer read FHeight;
    { Pictures per second, 0 if the film does not say. }
    property FrameRate: Double read FFrameRate;
    { The film's length in seconds, 0 if unknown. }
    property Duration: Double read FDuration;
    { One line about the film's pictures for the log: codec, size, pixel
      format, frame rate, length. }
    property Description: string read FDescription;
    { One line about the film's sound for the log: codec, rate, channels and
      the output device, or why there is no sound. }
    property AudioDescription: string read FAudioDescription;
    { Whether playing is paused. }
    property Paused: Boolean read FPaused;
  end;

implementation

uses
  Winapi.Windows, System.Math, libavutil, libavutil_error, libavutil_frame, libavutil_log,
  libavutil_pixdesc, libavutil_pixfmt, libavutil_rational, libavutil_samplefmt,
  libavutil_channel_layout, libavcodec, libavcodec_codec, libavcodec_codec_par,
  libavcodec_packet, libavformat, libswscale, libswresample;

const
  { FFmpeg's "no time stamp": INT64_MIN. }
  AV_NOPTS_VALUE = Low(Int64);
  { The DLLs needed, in the order they depend on each other. }
  FFmpegDlls: array[0..4] of string = ('avutil-60.dll', 'swresample-6.dll', 'avcodec-62.dll',
    'avformat-62.dll', 'swscale-9.dll');
  { The reader rests while both queues hold at least this many packets... }
  EnoughPackets = 60;
  { ...or while they hold this many bytes between them, whatever else. }
  MaxQueueBytes = 64 * 1024 * 1024;
  { Seconds of sound the output's ring buffer holds. }
  AudioBufferSeconds = 1.0;
  { Seconds of sound buffered before the sound starts. }
  AudioStartSeconds = 0.25;

type
  { swscale's YUV to RGB coefficients for one matrix (FFmpeg's
    @code(ff_yuv2rgb_coeffs)). The headers' @code(sws_getCoefficients)
    returns a pointer as an Integer, which loses its upper half on Win64, so
    the tables are kept here. }
  TSwsCoefficients = array[0..3] of Integer;

const
  { ITU-R BT.709, HD video. }
  Coeffs709: TSwsCoefficients = (117489, 138438, 13975, 34925);
  { ITU-R BT.601, SD video. }
  Coeffs601: TSwsCoefficients = (104597, 132201, 25675, 53279);
  { ITU-R BT.2020 (non-constant luminance). }
  Coeffs2020: TSwsCoefficients = (110013, 140363, 12277, 42626);

var
  { Whether @link(TSRVideoDecoder.LoadLibraries) has succeeded. }
  LibsLoaded: Boolean = False;

{ FFmpeg's text for an error code.
  @param(Code a negative FFmpeg result)
  @returns(the text and the code) }
function AvErrorText(Code: Integer): string;
var
  Buf: array[0..255] of AnsiChar;
begin
  if av_strerror(Code, @Buf[0], SizeOf(Buf)) = 0 then
    Result := Format('%s (%d)', [string(AnsiString(PAnsiChar(@Buf[0]))), Code])
  else
    Result := Format('FFmpeg error %d', [Code]);
end;

{ A version number from FFmpeg as text.
  @param(V major shl 16 + minor shl 8 + micro)
  @returns(such as 62.11.100) }
function VersionText(V: Cardinal): string;
begin
  Result := Format('%d.%d.%d', [V shr 16, (V shr 8) and $FF, V and $FF]);
end;

{ A stream's pointer from the film's list.
  @param(Fmt the film)
  @param(Index the stream's index)
  @returns(the stream) }
function StreamAt(Fmt: PAVFormatContext; Index: Integer): PAVStream;
begin
  Result := PPAVStream(PByte(Fmt.streams) + Index * SizeOf(Pointer))^;
end;

{ Seconds per tick of a time base.
  @param(R the time base)
  @param(Default what to use if it is empty)
  @returns(the seconds) }
function RationalSeconds(const R: TAVRational; Default: Double): Double;
begin
  if (R.den <> 0) and (R.num <> 0) then
    Result := R.num / R.den
  else
    Result := Default;
end;

{ A channel layout as text, such as "5.1(side)".
  @param(L the layout)
  @returns(the text) }
function LayoutText(const L: TAVChannelLayout): string;
var
  Buf: array[0..127] of AnsiChar;
begin
  if av_channel_layout_describe(@L, @Buf[0], SizeOf(Buf)) > 0 then
    Result := string(AnsiString(PAnsiChar(@Buf[0])))
  else
    Result := Format('%d channels', [L.nb_channels]);
end;

{ Raises an exception if an FFmpeg call failed.
  @param(Code its result)
  @param(Step what was being done)
  @param(FileName the film) }
procedure CheckAv(Code: Integer; const Step, FileName: string);
begin
  if Code < 0 then
    raise Exception.CreateFmt('%s: %s failed: %s', [ExtractFileName(FileName), Step,
      AvErrorText(Code)]);
end;

{ TSRDecoderThread }

constructor TSRDecoderThread.Create(Owner: TSRVideoDecoder; Kind: Integer);
begin
  FOwner := Owner;
  FKind := Kind;
  inherited Create(False);
end;

procedure TSRDecoderThread.Execute;
begin
  case FKind of
    0:
      begin
        NameThreadForDebugging('SRVideoDecoder reader');
        FOwner.ReadLoop(Self);
      end;
    1:
      begin
        NameThreadForDebugging('SRVideoDecoder pictures');
        FOwner.VideoLoop(Self);
      end;
    2:
      begin
        NameThreadForDebugging('SRVideoDecoder sound');
        FOwner.AudioLoop(Self);
      end;
  end;
end;

{ TSRPacketQueue }

constructor TSRPacketQueue.Create;
begin
  inherited Create;
  FLock := TCriticalSection.Create;
  FData := TEvent.Create(nil, False, False, '');
  FItems := TQueue<Pointer>.Create;
end;

destructor TSRPacketQueue.Destroy;
var
  P: PAVPacket;
begin
  if FItems <> nil then
    while FItems.Count > 0 do
    begin
      P := FItems.Dequeue;
      av_packet_free(@P);
    end;
  FItems.Free;
  FData.Free;
  FLock.Free;
  inherited;
end;

procedure TSRPacketQueue.Put(Packet: Pointer);
begin
  FLock.Enter;
  try
    FItems.Enqueue(Packet);
    Inc(FBytes, PAVPacket(Packet).size);
  finally
    FLock.Leave;
  end;
  FData.SetEvent;
end;

procedure TSRPacketQueue.MarkEnd;
begin
  FLock.Enter;
  try
    FEnded := True;
  finally
    FLock.Leave;
  end;
  FData.SetEvent;
end;

function TSRPacketQueue.Get(out Packet: Pointer; Thread: TSRDecoderThread): Integer;
begin
  Packet := nil;
  while not Thread.Terminated do
  begin
    FLock.Enter;
    try
      if FItems.Count > 0 then
      begin
        Packet := FItems.Dequeue;
        Dec(FBytes, PAVPacket(Packet).size);
        Exit(1);
      end;
      if FEnded then
        Exit(0);
    finally
      FLock.Leave;
    end;
    FData.WaitFor(20);
  end;
  Result := -1;
end;

function TSRPacketQueue.Count: Integer;
begin
  FLock.Enter;
  try
    Result := FItems.Count;
  finally
    FLock.Leave;
  end;
end;

function TSRPacketQueue.Bytes: Int64;
begin
  FLock.Enter;
  try
    Result := FBytes;
  finally
    FLock.Leave;
  end;
end;

{ TSRVideoDecoder: the threads' loops }

procedure TSRVideoDecoder.ReadLoop(T: TSRDecoderThread);
var
  Pkt, Q: PAVPacket;
  R: Integer;
  AudioCount: Integer;
  AudioBytes: Int64;
begin
  Pkt := av_packet_alloc;
  try
    if Pkt = nil then
    begin
      SetError('reading not started: FFmpeg could not allocate a packet');
      Exit;
    end;
    while not T.Terminated do
    begin
      // Rest while both decoders have enough waiting, or memory is at its
      // limit; a decoder short of packets keeps the reader going
      if FAudioPackets <> nil then
      begin
        AudioCount := FAudioPackets.Count;
        AudioBytes := FAudioPackets.Bytes;
      end
      else
      begin
        AudioCount := MaxInt;
        AudioBytes := 0;
      end;
      if ((FVideoPackets.Count >= EnoughPackets) and (AudioCount >= EnoughPackets)) or
        (FVideoPackets.Bytes + AudioBytes > MaxQueueBytes) then
      begin
        TThread.Sleep(5);
        Continue;
      end;
      R := av_read_frame(FFormat, Pkt);
      if R < 0 then
      begin
        if R <> AVERROR_EOF then
          SetError('reading the film stopped: ' + AvErrorText(R) +
            '; what was read so far still plays');
        Break;
      end;
      if Pkt.stream_index = FStreamIndex then
      begin
        Q := av_packet_alloc;
        av_packet_move_ref(Q, Pkt);
        FVideoPackets.Put(Q);
      end
      else if (FAudioPackets <> nil) and (Pkt.stream_index = FAudioIndex) then
      begin
        Q := av_packet_alloc;
        av_packet_move_ref(Q, Pkt);
        FAudioPackets.Put(Q);
      end
      else
        av_packet_unref(Pkt);
    end;
  finally
    FVideoPackets.MarkEnd;
    if FAudioPackets <> nil then
      FAudioPackets.MarkEnd;
    av_packet_free(@Pkt);
  end;
end;

procedure TSRVideoDecoder.VideoLoop(T: TSRDecoderThread);
var
  Ctx: PAVCodecContext;
  P: Pointer;
  Pkt: PAVPacket;
  Frm: PAVFrame;
  Sws: PSwsContext;
  R, Slot, W, H, Pitch, Size, SwsFmt, SwsW, SwsH: Integer;
  EofSent: Boolean;
  Ts: Int64;
  Secs, LastSecs, Step: Double;
  Dst: array[0..3] of PByte;
  DstStride: array[0..3] of Integer;
  Coeffs: ^TSwsCoefficients;
  Matrix, RangeText: string;
  FullRange: Boolean;
begin
  Ctx := FCodecCtx;
  Frm := av_frame_alloc;
  Sws := nil;
  SwsFmt := -1;
  SwsW := 0;
  SwsH := 0;
  EofSent := False;
  LastSecs := 0;
  if FFrameRate > 0 then
    Step := 1 / FFrameRate
  else
    Step := 1 / 25;
  try
    if Frm = nil then
    begin
      SetError('decoding not started: FFmpeg could not allocate a frame');
      Exit;
    end;
    while not T.Terminated do
    begin
      R := avcodec_receive_frame(Ctx, Frm);
      if R = 0 then
      begin
        Slot := WaitForRoom(T);
        if Slot < 0 then
          Break;
        // When it is due, in film time
        Ts := Frm.best_effort_timestamp;
        if Ts = AV_NOPTS_VALUE then
          Ts := Frm.pts;
        if Ts = AV_NOPTS_VALUE then
          Secs := LastSecs + Step
        else
          Secs := Ts * FTimeBase - FOrigin;
        LastSecs := Secs;
        W := Frm.width;
        H := Frm.height;
        // A converter for this format and size, with the film's own colour
        // matrix and range (swscale's default is BT.601, limited range)
        if (Frm.format <> SwsFmt) or (W <> SwsW) or (H <> SwsH) then
        begin
          Sws := sws_getCachedContext(Sws, W, H, TAVPixelFormat(Frm.format), W, H,
            AV_PIX_FMT_BGRA, Ord(SWS_BILINEAR), nil, nil, nil);   // the headers make the flags an enum
          if Sws = nil then
          begin
            SetError(Format('no converter from %s %d x %d to BGRA',
              [string(AnsiString(av_get_pix_fmt_name(TAVPixelFormat(Frm.format)))), W, H]));
            Break;
          end;
          case Frm.colorspace of
            AVCOL_SPC_BT709:
              begin
                Coeffs := @Coeffs709;
                Matrix := 'BT.709 (tagged)';
              end;
            AVCOL_SPC_BT2020_NCL, AVCOL_SPC_BT2020_CL:
              begin
                Coeffs := @Coeffs2020;
                Matrix := 'BT.2020 (tagged; HDR is not tone-mapped)';
              end;
            AVCOL_SPC_UNSPECIFIED:
              if H >= 720 then
              begin
                Coeffs := @Coeffs709;
                Matrix := 'BT.709 (untagged, HD size)';
              end
              else
              begin
                Coeffs := @Coeffs601;
                Matrix := 'BT.601 (untagged, SD size)';
              end;
          else
            Coeffs := @Coeffs601;
            Matrix := 'BT.601 (tagged)';
          end;
          FullRange := Frm.color_range = AVCOL_RANGE_JPEG;
          if FullRange then
            RangeText := 'full'
          else
            RangeText := 'limited (TV)';
          sws_setColorspaceDetails(Sws, @Coeffs^[0], Ord(FullRange), @Coeffs^[0], 1, 0,
            1 shl 16, 1 shl 16);
          SwsFmt := Frm.format;
          SwsW := W;
          SwsH := H;
          FLock.Enter;
          try
            FColourNote := Format('%s %d x %d to BGRA: matrix %s, %s range in, full range out',
              [string(AnsiString(av_get_pix_fmt_name(TAVPixelFormat(Frm.format)))), W, H, Matrix,
               RangeText]);
          finally
            FLock.Leave;
          end;
        end;
        // The slot is this thread's alone until it is published. Rows padded
        // to SRVideoRowAlign bytes, with as many spare after the last: swscale
        // may write past the end of a row that is not
        Pitch := (W * 4 + SRVideoRowAlign - 1) and not (SRVideoRowAlign - 1);
        Size := Pitch * H + SRVideoRowAlign;
        if Length(FSlots[Slot].Pixels) <> Size then
          SetLength(FSlots[Slot].Pixels, Size);
        FillChar(Dst, SizeOf(Dst), 0);
        FillChar(DstStride, SizeOf(DstStride), 0);
        Dst[0] := @FSlots[Slot].Pixels[0];
        DstStride[0] := Pitch;
        sws_scale(Sws, @Frm.data[0], @Frm.linesize[0], 0, H, @Dst[0], @DstStride[0]);
        av_frame_unref(Frm);
        Publish(Slot, W, H, Pitch, Secs);
      end
      else if R = AVERROR_EOF then
        Break   // every picture decoded
      else if R <> AVERROR_EAGAIN then
      begin
        SetError('decoding pictures failed: ' + AvErrorText(R));
        Break;
      end
      else if EofSent then
        Break
      else
        case FVideoPackets.Get(P, T) of
          1:
            begin
              Pkt := P;
              R := avcodec_send_packet(Ctx, Pkt);
              if (R < 0) and (R <> AVERROR_EAGAIN) then
                CountBadPacket;
              av_packet_free(@Pkt);
            end;
          0:
            begin
              avcodec_send_packet(Ctx, nil);   // flush: the last pictures come out
              EofSent := True;
            end;
        else
          Break;
        end;
    end;
  finally
    if Sws <> nil then
      sws_freeContext(Sws);
    av_frame_free(@Frm);
    FLock.Enter;
    try
      FFinished := True;
    finally
      FLock.Leave;
    end;
  end;
end;

procedure TSRVideoDecoder.AudioLoop(T: TSRDecoderThread);
var
  Ctx: PAVCodecContext;
  P: Pointer;
  Pkt: PAVPacket;
  Frm: PAVFrame;
  Swr: PSwrContext;
  OutLayout: TAVChannelLayout;
  Buf: TArray<Single>;
  OutPtr: PByte;
  R, N, MaxOut, InRate, InFmt, InChannels: Integer;
  EofSent, StartSet: Boolean;
  Ts: Int64;
  Cancel: TFunc<Boolean>;

  { Writes converted sound to the output and starts it once enough waits.
    @param(Frames how many frames are in Buf)
    @returns(@false if the thread was told to stop) }
  function Play(Frames: Integer): Boolean;
  begin
    Result := (Frames <= 0) or FAudio.Write(@Buf[0], Frames, Cancel);
    if Result and not FAudioStarted and (FAudio.Buffered >= AudioStartSeconds) then
    begin
      FAudioStarted := True;
      if not FPaused then
        FAudio.Play;
    end;
  end;

begin
  Ctx := FAudioCtx;
  Frm := av_frame_alloc;
  Swr := nil;
  InRate := 0;
  InFmt := -1;
  InChannels := 0;
  EofSent := False;
  StartSet := False;
  FillChar(OutLayout, SizeOf(OutLayout), 0);
  av_channel_layout_default(@OutLayout, FAudio.Channels);
  Cancel :=
    function: Boolean
    begin
      Result := T.Terminated;
    end;
  try
    if Frm = nil then
    begin
      SetError('sound not started: FFmpeg could not allocate a frame');
      Exit;
    end;
    while not T.Terminated do
    begin
      R := avcodec_receive_frame(Ctx, Frm);
      if R = 0 then
      begin
        // A converter for this format, to the device's rate and channels
        if (Swr = nil) or (Frm.sample_rate <> InRate) or (Frm.format <> InFmt) or
          (Frm.ch_layout.nb_channels <> InChannels) then
        begin
          swr_free(@Swr);
          R := swr_alloc_set_opts2(@Swr, @OutLayout, AV_SAMPLE_FMT_FLT, FAudio.SampleRate,
            @Frm.ch_layout, TAVSampleFormat(Frm.format), Frm.sample_rate, 0, nil);
          if R >= 0 then
            R := swr_init(Swr);
          if R < 0 then
          begin
            SetError('no sound converter: ' + AvErrorText(R) + '; the film plays silent');
            Break;
          end;
          InRate := Frm.sample_rate;
          InFmt := Frm.format;
          InChannels := Frm.ch_layout.nb_channels;
          FLock.Enter;
          try
            FAudioNote := Format('%s, %d Hz, %s to %d Hz, %d channels, float',
              [string(AnsiString(av_get_sample_fmt_name(TAVSampleFormat(Frm.format)))),
               Frm.sample_rate, LayoutText(Frm.ch_layout), FAudio.SampleRate, FAudio.Channels]);
          finally
            FLock.Leave;
          end;
        end;
        // The first sound's time: the output's clock counts from it
        if not StartSet then
        begin
          Ts := Frm.best_effort_timestamp;
          if Ts = AV_NOPTS_VALUE then
            Ts := Frm.pts;
          if Ts <> AV_NOPTS_VALUE then
            FAudio.SetStartTime(Ts * FAudioTimeBase - FOrigin);
          StartSet := True;
        end;
        MaxOut := swr_get_delay(Swr, FAudio.SampleRate) +
          Int64(Frm.nb_samples) * FAudio.SampleRate div Max(1, Frm.sample_rate) + 256;
        if Length(Buf) < MaxOut * FAudio.Channels then
          SetLength(Buf, MaxOut * FAudio.Channels);
        OutPtr := @Buf[0];
        N := swr_convert(Swr, @OutPtr, MaxOut, Frm.extended_data, Frm.nb_samples);
        av_frame_unref(Frm);
        if not Play(N) then
          Break;
      end
      else if R = AVERROR_EOF then
      begin
        // The converter's last samples, then the end
        if Swr <> nil then
        begin
          MaxOut := swr_get_delay(Swr, FAudio.SampleRate) + 256;
          if Length(Buf) < MaxOut * FAudio.Channels then
            SetLength(Buf, MaxOut * FAudio.Channels);
          OutPtr := @Buf[0];
          N := swr_convert(Swr, @OutPtr, MaxOut, nil, 0);
          Play(N);
        end;
        Break;
      end
      else if R <> AVERROR_EAGAIN then
      begin
        SetError('decoding the sound failed: ' + AvErrorText(R) + '; the pictures play on');
        Break;
      end
      else if EofSent then
        Break
      else
        case FAudioPackets.Get(P, T) of
          1:
            begin
              Pkt := P;
              R := avcodec_send_packet(Ctx, Pkt);
              if (R < 0) and (R <> AVERROR_EAGAIN) then
                CountBadPacket;
              av_packet_free(@Pkt);
            end;
          0:
            begin
              avcodec_send_packet(Ctx, nil);
              EofSent := True;
            end;
        else
          Break;
        end;
    end;
  finally
    // Whatever is buffered still plays; a short film starts now
    FAudio.MarkEnd;
    if not FAudioStarted and not T.Terminated then
    begin
      FAudioStarted := True;
      if not FPaused then
        FAudio.Play;
    end;
    swr_free(@Swr);
    av_channel_layout_uninit(@OutLayout);
    av_frame_free(@Frm);
  end;
end;

{ TSRVideoDecoder }

class function TSRVideoDecoder.LibrariesLoaded: Boolean;
begin
  Result := LibsLoaded;
end;

class function TSRVideoDecoder.LoadLibraries(out Report: string): Boolean;
var
  Dir, Name, Hint: string;
  H: HMODULE;
  Err: Cardinal;
begin
  if LibsLoaded then
  begin
    Report := 'FFmpeg already loaded';
    Exit(True);
  end;
  Result := False;
  Dir := ExtractFilePath(ParamStr(0));
  for Name in FFmpegDlls do
  begin
    if not FileExists(Dir + Name) then
    begin
      Report := Format('FFmpeg not loaded: %s is not in %s (the build copies dll\ffmpeg\*.dll ' +
        'there; put FFmpeg''s 64-bit GPL shared DLLs in dll\ffmpeg, see README)', [Name, Dir]);
      Exit;
    end;
    // By full path; LOAD_WITH_ALTERED_SEARCH_PATH finds its own DLLs beside it
    H := LoadLibraryEx(PChar(Dir + Name), 0, LOAD_WITH_ALTERED_SEARCH_PATH);
    if H = 0 then
    begin
      Err := GetLastError;
      case Err of
        ERROR_BAD_EXE_FORMAT:
          Hint := ': it is not a 64-bit DLL (this program is 64-bit)';
        ERROR_MOD_NOT_FOUND:
          Hint := ': a DLL it needs is missing (are all of FFmpeg''s DLLs from the same build?)';
        ERROR_PROC_NOT_FOUND:
          Hint := ': it needs a routine its other DLLs lack (DLLs from different FFmpeg builds?)';
      else
        Hint := '';
      end;
      Report := Format('FFmpeg not loaded: %s%s would not load, Windows error %d, %s%s',
        [Dir, Name, Err, SysErrorMessage(Err), Hint]);
      Exit;
    end;
  end;
  // The delayed imports bind to the DLLs now loaded
  try
    av_log_set_level(AV_LOG_ERROR);
    Report := Format('FFmpeg loaded from %s: avutil %s, avcodec %s, avformat %s, swscale %s, ' +
      'swresample %s; licence: %s', [Dir, VersionText(avutil_version), VersionText(avcodec_version),
      VersionText(avformat_version), VersionText(swscale_version), VersionText(swresample_version),
      string(AnsiString(avcodec_license))]);
  except
    on E: Exception do
    begin
      Report := Format('FFmpeg''s DLLs loaded from %s but a routine could not be found (%s: %s): ' +
        'they do not match the headers (FFmpeg 8.1)', [Dir, E.ClassName, E.Message]);
      Exit;
    end;
  end;
  LibsLoaded := True;
  Result := True;
end;

constructor TSRVideoDecoder.Create(const FileName: string);
var
  Fmt: PAVFormatContext;
  Ctx, ACtx: PAVCodecContext;
  Codec, ACodec: PAVCodec;
  St, ASt: PAVStream;
  Par, APar: PAVCodecParameters;
  Utf8: UTF8String;
  R: Integer;
  LenText: string;
begin
  inherited Create;
  FLock := TCriticalSection.Create;
  FRoom := TEvent.Create(nil, False, False, '');
  FAudioIndex := -1;
  if not LibsLoaded then
    raise Exception.Create('FFmpeg is not loaded (TSRVideoDecoder.LoadLibraries first)');
  Utf8 := UTF8Encode(FileName);
  Fmt := nil;
  CheckAv(avformat_open_input(@Fmt, PAnsiChar(Utf8), nil, nil), 'opening it', FileName);
  FFormat := Fmt;
  CheckAv(avformat_find_stream_info(Fmt, nil), 'reading its streams', FileName);
  if Fmt.start_time <> AV_NOPTS_VALUE then
    FOrigin := Fmt.start_time / 1000000;   // AV_TIME_BASE

  // The pictures
  Codec := nil;
  R := av_find_best_stream(Fmt, AVMEDIA_TYPE_VIDEO, -1, -1, @Codec, 0);
  CheckAv(R, 'finding a video stream', FileName);
  FStreamIndex := R;
  St := StreamAt(Fmt, R);
  Par := St.codecpar;
  if Codec = nil then
    raise Exception.CreateFmt('%s: this FFmpeg build has no decoder for its video (codec %d)',
      [ExtractFileName(FileName), Ord(Par.codec_id)]);
  Ctx := avcodec_alloc_context3(Codec);
  if Ctx = nil then
    raise Exception.CreateFmt('%s: FFmpeg could not allocate a decoder', [ExtractFileName(FileName)]);
  FCodecCtx := Ctx;
  CheckAv(avcodec_parameters_to_context(Ctx, Par), 'setting up the picture decoder', FileName);
  // As many threads as FFmpeg sees fit, decoding several pictures at once
  Ctx.thread_count := 0;
  Ctx.thread_type := FF_THREAD_FRAME or FF_THREAD_SLICE;
  Ctx.pkt_timebase := St.time_base;
  CheckAv(avcodec_open2(Ctx, Codec, nil), 'opening the picture decoder', FileName);
  FTimeBase := RationalSeconds(St.time_base, 1 / 90000);
  if St.avg_frame_rate.den <> 0 then
    FFrameRate := St.avg_frame_rate.num / St.avg_frame_rate.den
  else if St.r_frame_rate.den <> 0 then
    FFrameRate := St.r_frame_rate.num / St.r_frame_rate.den;
  FWidth := Par.width;
  FHeight := Par.height;
  if Fmt.duration > 0 then
    FDuration := Fmt.duration / 1000000;   // AV_TIME_BASE
  if FDuration > 0 then
    LenText := Format('%d:%.2d:%.2d', [Trunc(FDuration) div 3600, (Trunc(FDuration) div 60) mod 60,
      Trunc(FDuration) mod 60])
  else
    LenText := 'length unknown';
  FDescription := Format('%s video %d x %d, %s, %.3f fps, %s, stream %d of %d, %d decoding threads',
    [string(AnsiString(Codec.name)), FWidth, FHeight,
     string(AnsiString(av_get_pix_fmt_name(TAVPixelFormat(Par.format)))), FFrameRate, LenText,
     FStreamIndex, Fmt.nb_streams, Ctx.thread_count]);

  // The sound: the stream FFmpeg pairs with the pictures, if any. Without a
  // decoder or an output device the film plays silent.
  ACodec := nil;
  R := av_find_best_stream(Fmt, AVMEDIA_TYPE_AUDIO, -1, FStreamIndex, @ACodec, 0);
  if R < 0 then
    FAudioDescription := 'no sound track: playing silent'
  else
  begin
    ASt := StreamAt(Fmt, R);
    APar := ASt.codecpar;
    if ACodec = nil then
      FAudioDescription := Format('sound stream %d has no decoder in this FFmpeg build (codec %d): ' +
        'playing silent', [R, Ord(APar.codec_id)])
    else
    begin
      ACtx := avcodec_alloc_context3(ACodec);
      try
        if ACtx = nil then
          raise Exception.Create('FFmpeg could not allocate a sound decoder');
        CheckAv(avcodec_parameters_to_context(ACtx, APar), 'setting up the sound decoder', FileName);
        ACtx.pkt_timebase := ASt.time_base;
        CheckAv(avcodec_open2(ACtx, ACodec, nil), 'opening the sound decoder', FileName);
        FAudio := TSRAudioOutput.Create(AudioBufferSeconds);
        FAudioCtx := ACtx;
        FAudioIndex := R;
        FAudioTimeBase := RationalSeconds(ASt.time_base, 1 / 48000);
        FAudioClock := True;
        FAudioDescription := Format('%s sound, %d Hz, %s, stream %d; to the %s',
          [string(AnsiString(ACodec.name)), APar.sample_rate, LayoutText(APar.ch_layout), R,
           FAudio.Description]);
      except
        on E: Exception do
        begin
          if ACtx <> nil then
            avcodec_free_context(@ACtx);
          FreeAndNil(FAudio);
          FAudioCtx := nil;
          FAudioIndex := -1;
          FAudioDescription := 'no sound: ' + E.Message + '; playing silent';
        end;
      end;
    end;
  end;
  if FAudio = nil then
    FAudioNote := FAudioDescription;

  FVideoPackets := TSRPacketQueue.Create;
  if FAudio <> nil then
    FAudioPackets := TSRPacketQueue.Create;
  FVideoThread := TSRDecoderThread.Create(Self, 1);
  if FAudio <> nil then
    FAudioThread := TSRDecoderThread.Create(Self, 2);
  FReader := TSRDecoderThread.Create(Self, 0);
end;

destructor TSRVideoDecoder.Destroy;
var
  Fmt: PAVFormatContext;
  Ctx: PAVCodecContext;
  Threads: array[0..2] of TSRDecoderThread;
  I: Integer;
begin
  // Tell every thread to stop before waiting for any: they wait on each other
  Threads[0] := FReader;
  Threads[1] := FVideoThread;
  Threads[2] := FAudioThread;
  for I := 0 to 2 do
    if Threads[I] <> nil then
      Threads[I].Terminate;
  if FRoom <> nil then
    FRoom.SetEvent;
  for I := 0 to 2 do
    if Threads[I] <> nil then
    begin
      Threads[I].WaitFor;
      Threads[I].Free;
    end;
  FReader := nil;
  FVideoThread := nil;
  FAudioThread := nil;
  FreeAndNil(FAudio);
  FreeAndNil(FVideoPackets);
  FreeAndNil(FAudioPackets);
  Ctx := FAudioCtx;
  if Ctx <> nil then
    avcodec_free_context(@Ctx);
  FAudioCtx := nil;
  Ctx := FCodecCtx;
  if Ctx <> nil then
    avcodec_free_context(@Ctx);
  FCodecCtx := nil;
  Fmt := FFormat;
  if Fmt <> nil then
    avformat_close_input(@Fmt);
  FFormat := nil;
  FRoom.Free;
  FLock.Free;
  inherited;
end;

function TSRVideoDecoder.WaitForRoom(Thread: TSRDecoderThread): Integer;
begin
  while not Thread.Terminated do
  begin
    FLock.Enter;
    try
      // The slot after the last queued one: the main thread never touches it
      if FCount < SRVideoQueueSize then
        Exit((FHead + FCount) mod SRVideoQueueSize);
    finally
      FLock.Leave;
    end;
    FRoom.WaitFor(50);
  end;
  Result := -1;
end;

procedure TSRVideoDecoder.Publish(Slot, W, H, Pitch: Integer; Seconds: Double);
begin
  FLock.Enter;
  try
    FSlots[Slot].Pitch := Pitch;
    FSlots[Slot].W := W;
    FSlots[Slot].H := H;
    FSlots[Slot].Seconds := Seconds;
    Inc(FCount);
    Inc(FDecoded);
  finally
    FLock.Leave;
  end;
end;

procedure TSRVideoDecoder.SetError(const Msg: string);
begin
  FLock.Enter;
  try
    if FError = '' then
      FError := Msg;
  finally
    FLock.Leave;
  end;
end;

procedure TSRVideoDecoder.CountBadPacket;
begin
  FLock.Enter;
  try
    Inc(FBadPackets);
  finally
    FLock.Leave;
  end;
end;

function TSRVideoDecoder.ClockNow: Double;
begin
  if FAudioClock then
  begin
    // The sound is the clock until it has all been heard; then a wall clock
    // carries on from where it ended, for pictures that outlast it
    if not FAudio.Drained then
      Exit(FAudio.Clock);
    FAudioClock := False;
    FClockBase := FAudio.Clock;
    FClock := TStopwatch.StartNew;
    FClockStarted := True;
  end;
  if not FClockStarted then
    Result := 0
  else if FPaused then
    Result := FClockBase
  else
    Result := FClockBase + FClock.ElapsedTicks / TStopwatch.Frequency;
end;

function TSRVideoDecoder.TakeFrame(var Pixels: TBytes; out W, H, Pitch: Integer;
  out Seconds: Double): Boolean;
var
  Now: Double;
  I, Best, Idx: Integer;
  Tmp: TBytes;
begin
  Result := False;
  W := 0;
  H := 0;
  Pitch := 0;
  Seconds := 0;
  FLock.Enter;
  try
    if FCount = 0 then
      Exit;
    if not FAudioClock and not FClockStarted then
    begin
      // Without sound the clock starts at the first picture, so none is late
      FClockBase := FSlots[FHead].Seconds;
      FClock := TStopwatch.StartNew;
      FClockStarted := True;
    end;
    Now := ClockNow;
    // The newest picture already due (a millisecond early is close enough);
    // the very first is shown at once, so the screen is not black while the
    // sound fills its buffer
    Best := -1;
    for I := 0 to FCount - 1 do
      if (FSlots[(FHead + I) mod SRVideoQueueSize].Seconds <= Now + 0.001) or
        ((FShown = 0) and (I = 0)) then
        Best := I
      else
        Break;
    if Best < 0 then
      Exit;
    Inc(FDropped, Best);
    Idx := (FHead + Best) mod SRVideoQueueSize;
    // Swap buffers: the caller's old one goes back into the queue
    Tmp := FSlots[Idx].Pixels;
    FSlots[Idx].Pixels := Pixels;
    Pixels := Tmp;
    W := FSlots[Idx].W;
    H := FSlots[Idx].H;
    Pitch := FSlots[Idx].Pitch;
    Seconds := FSlots[Idx].Seconds;
    FHead := (Idx + 1) mod SRVideoQueueSize;
    Dec(FCount, Best + 1);
    Inc(FShown);
    Result := True;
  finally
    FLock.Leave;
  end;
  FRoom.SetEvent;
end;

procedure TSRVideoDecoder.SetPaused(Value: Boolean);
begin
  if Value = FPaused then
    Exit;
  if not FAudioClock and FClockStarted then
  begin
    if Value then
      FClockBase := ClockNow
    else
      FClock := TStopwatch.StartNew;
  end;
  FPaused := Value;
  if FAudio <> nil then
  begin
    if Value then
      FAudio.Pause
    else if FAudioStarted then
      FAudio.Play;
  end;
end;

function TSRVideoDecoder.Position: Double;
begin
  Result := ClockNow;
end;

function TSRVideoDecoder.AtEnd: Boolean;
begin
  FLock.Enter;
  try
    Result := FFinished and (FCount = 0);
  finally
    FLock.Leave;
  end;
end;

function TSRVideoDecoder.LastError: string;
begin
  FLock.Enter;
  try
    Result := FError;
  finally
    FLock.Leave;
  end;
end;

function TSRVideoDecoder.ColourNote: string;
begin
  FLock.Enter;
  try
    Result := FColourNote;
  finally
    FLock.Leave;
  end;
end;

function TSRVideoDecoder.AudioNote: string;
begin
  FLock.Enter;
  try
    Result := FAudioNote;
  finally
    FLock.Leave;
  end;
end;

function TSRVideoDecoder.Decoded: Int64;
begin
  FLock.Enter;
  try
    Result := FDecoded;
  finally
    FLock.Leave;
  end;
end;

function TSRVideoDecoder.Shown: Int64;
begin
  FLock.Enter;
  try
    Result := FShown;
  finally
    FLock.Leave;
  end;
end;

function TSRVideoDecoder.Dropped: Int64;
begin
  FLock.Enter;
  try
    Result := FDropped;
  finally
    FLock.Leave;
  end;
end;

function TSRVideoDecoder.BadPackets: Int64;
begin
  FLock.Enter;
  try
    Result := FBadPackets;
  finally
    FLock.Leave;
  end;
end;

function TSRVideoDecoder.Underruns: Int64;
begin
  if FAudio <> nil then
    Result := FAudio.Underruns
  else
    Result := 0;
end;

function TSRVideoDecoder.HasSound: Boolean;
begin
  Result := FAudio <> nil;
end;

end.

{ @abstract(@link(TSRMovieRenderer): @link(TSRStereoRenderer) showing
  side-by-side frames and films, the FMX side of the movie player.)

  All the work on frames and films is in units that use neither FMX nor VCL:
  @link(SRStereoFrame) (layouts, half side-by-side, fitting the views, the 2D
  left view) and @link(SRVideoDecoder) (FFmpeg, decoding on a thread, the
  playback clock). This unit only moves the current picture between them and
  hands the views to the renderer each frame, through
  @link(TSRStereoRenderer.SupplyViews), and turns the 2D left view into an FMX
  bitmap. Everything else is @link(TSRStereoRenderer)'s, unchanged. }
unit FMX.SRMovieRenderer;

interface

uses
  System.SysUtils, System.Classes, System.Diagnostics, FMX.Graphics, FMX.SRStereoViewport,
  SRStereoFrame, SRVideoDecoder;

type
  { @link(TSRStereoRenderer) that weaves the frame in
    @link(TSRMovieRenderer.Frame), a still or the film playing, instead of
    the 3D scene. }
  TSRMovieRenderer = class(TSRStereoRenderer)
  private
    { See @link(TSRMovieRenderer.Frame). }
    FFrame: TSRStereoFrame;
    { See @link(TSRMovieRenderer.Video). }
    FVideo: TSRVideoDecoder;
    { The film's file name without its folder, given to the frame as its
      name. }
    FVideoName: string;
    { See @link(TSRMovieRenderer.VideoLayout). }
    FVideoLayout: TSRStereoLayout;
    { The layout the film's pictures are given, as decided from
      @link(FVideoLayout) by @link(DecideVideoLayout): never
      @code(layoutAuto). }
    FVideoUsed: TSRStereoLayout;
    { Why @link(FVideoUsed) is what it is, for the log. }
    FVideoReason: string;
    { The buffer handed back by the frame, given to the decoder for its next
      picture. }
    FSpare: TBytes;
    { Times the film's periodic log line. }
    FVideoLogClock: TStopwatch;
    { Whether the film's end, its error and its colour conversion have been
      logged. }
    FEndLogged, FErrorLogged: Boolean;
    { The colour conversion last logged. }
    FColourLogged: string;
    { The sound conversion last logged. }
    FAudioLogged: string;
    { The fit last logged: name, layout, view size and flatness, so each new
      fit is logged once (not every film frame). }
    FLoggedName: string;
    { See @link(FLoggedName). }
    FLoggedLayout: TSRStereoLayout;
    { See @link(FLoggedName). }
    FLoggedW, FLoggedH: Integer;
    { See @link(FLoggedName). }
    FLoggedFlat: Boolean;
    { Takes the film's newest due picture into the frame, and logs the film's
      end, errors and progress. }
    procedure PumpVideo;
    { Sets @link(TSRMovieRenderer.VideoLayout).
      @param(Value the layout for the film's pictures) }
    procedure SetVideoLayout(Value: TSRStereoLayout);
    { Decides @link(FVideoUsed) and @link(FVideoReason) from
      @link(FVideoLayout) and the film's name. A film's @code(layoutAuto)
      is the name's tag, else half side-by-side: films are assumed half
      side-by-side, and a scope film (1920 x 804, say) is more than twice as
      wide as high, which the stills' shape rule would take for full
      side-by-side. }
    procedure DecideVideoLayout;
  protected
    { Supplies @link(TSRMovieRenderer.Frame)'s views while it holds a frame,
      first taking the film's newest picture when one is playing, and logs
      each new fit.
      @param(ViewportW the viewport's width in pixels)
      @param(ViewportH the viewport's height in pixels)
      @param(Flat @true while the lens is off)
      @param(Views receives the views)
      @param(W receives the width of one view)
      @param(H receives the height)
      @param(Pitch receives the bytes per row)
      @param(Fmt receives @code(SRB_FMT_BGRA8))
      @returns(@true while a frame is held) }
    function SupplyViews(ViewportW, ViewportH: Integer; Flat: Boolean; out Views: Pointer;
      out W, H, Pitch, Fmt: Integer): Boolean; override;
  public
    { Creates the renderer, inactive, with no frame.
      @param(AOwner the owner) }
    constructor Create(AOwner: TComponent); override;
    { Frees the renderer, the film and the frame. }
    destructor Destroy; override;
    { Loads a side-by-side still into @link(TSRMovieRenderer.Frame), stopping
      any film, and logs what it is; it is woven from the next frame on. On
      failure the frame shown so far stays.
      @param(FileName a PNG, JPEG or other WIC-readable file)
      @param(Layout how it is packed; @code(layoutAuto) (the default)
        decides from the name and shape)
      @raises(Exception if the file cannot be read) }
    procedure ShowFrameFile(const FileName: string; Layout: TSRStereoLayout = layoutAuto);
    { Opens a side-by-side film and plays it from the start, with its sound
      on the default output device; the pictures are timed by the sound.
      FFmpeg is loaded the first time (@link(TSRVideoDecoder.LoadLibraries))
      and stays loaded. On failure whatever was shown stays.
      @param(FileName the film)
      @param(Layout how its pictures are packed; @code(layoutAuto) (the
        default) decides from the name and shape)
      @raises(Exception saying what failed: loading FFmpeg, or opening the
        film) }
    procedure PlayFile(const FileName: string; Layout: TSRStereoLayout = layoutAuto);
    { Stops and closes the film, keeping its last picture as a still. }
    procedure StopVideo;
    { Pauses or resumes the film, if one is open. }
    procedure TogglePause;
    { Forgets the frame and any film: the viewport's 3D scene is woven
      again. }
    procedure ClearFrame;
    { Copies the frame's left view, at its proper shape, into an FMX bitmap,
      for showing in 2D while SR is off.
      @param(Dest receives it, resized)
      @returns(@false, leaving Dest alone, when no frame is held or the
        bitmap cannot be written) }
    function CopyFrameLeftView(Dest: TBitmap): Boolean;
    { The frame being woven, a still or the film's current picture; empty
      until one is loaded. Owned by the renderer. }
    property Frame: TSRStereoFrame read FFrame;
    { The film open now, nil for none. Owned by the renderer. }
    property Video: TSRVideoDecoder read FVideo;
    { The layout of the film's pictures; changing it takes effect from the
      next picture. @code(layoutAuto) (the default) means the name's tag,
      else half side-by-side: unlike a still's, a film's shape is not used. }
    property VideoLayout: TSRStereoLayout read FVideoLayout write SetVideoLayout;
  end;

implementation

uses
  System.StrUtils, FMX.Types, SRBridge.Api;

const
  { Milliseconds between the film's progress lines in the log. }
  VideoLogInterval = 5000;

{ A film time as text.
  @param(Seconds the time)
  @returns(such as 1:02:03.4 or 2:03.4) }
function TimeText(Seconds: Double): string;
var
  T: Integer;
begin
  if Seconds < 0 then
    Seconds := 0;
  T := Trunc(Seconds);
  if T >= 3600 then
    Result := Format('%d:%.2d:%.2d.%d', [T div 3600, (T div 60) mod 60, T mod 60,
      Trunc(Frac(Seconds) * 10)])
  else
    Result := Format('%d:%.2d.%d', [T div 60, T mod 60, Trunc(Frac(Seconds) * 10)]);
end;

constructor TSRMovieRenderer.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FFrame := TSRStereoFrame.Create;
  FVideoLayout := layoutAuto;
  FLoggedW := -1;
end;

destructor TSRMovieRenderer.Destroy;
begin
  inherited;
  // After the renderer has stopped, so no frame is using them
  FreeAndNil(FVideo);
  FreeAndNil(FFrame);
end;

procedure TSRMovieRenderer.ShowFrameFile(const FileName: string; Layout: TSRStereoLayout);
begin
  FFrame.LoadFromFile(FileName, Layout);
  StopVideo;
  Log(Format('Frame %s, %d x %d, %s (%s): each eye %d x %d stored, shown at %d x %d',
    [FFrame.Name, FFrame.Width, FFrame.Height, TSRStereoFrame.LayoutName(FFrame.Layout),
     FFrame.LayoutReason, FFrame.Width div 2, FFrame.Height,
     (FFrame.Width div 2) * FFrame.Squeeze, FFrame.Height]));
end;

procedure TSRMovieRenderer.PlayFile(const FileName: string; Layout: TSRStereoLayout);
var
  Report: string;
  NewVideo: TSRVideoDecoder;
begin
  // FFmpeg once, at the first film; it then stays loaded
  if not TSRVideoDecoder.LibrariesLoaded then
  begin
    if not TSRVideoDecoder.LoadLibraries(Report) then
    begin
      Log(Report);
      raise Exception.Create(Report);
    end;
    Log(Report);
  end;
  NewVideo := TSRVideoDecoder.Create(FileName);
  StopVideo;
  FVideo := NewVideo;
  FVideoName := ExtractFileName(FileName);
  FVideoLayout := Layout;
  DecideVideoLayout;
  FEndLogged := False;
  FErrorLogged := False;
  FColourLogged := '';
  FAudioLogged := '';
  FVideoLogClock := TStopwatch.StartNew;
  Log(Format('Film %s: %s; %s (%s)',
    [FVideoName, FVideo.Description, TSRStereoFrame.LayoutName(FVideoUsed), FVideoReason]));
  Log('Film sound: ' + FVideo.AudioDescription);
end;

procedure TSRMovieRenderer.DecideVideoLayout;
begin
  if FVideoLayout <> layoutAuto then
  begin
    FVideoUsed := FVideoLayout;
    FVideoReason := 'as asked';
    Exit;
  end;
  FVideoUsed := TSRStereoFrame.LayoutFromName(FVideoName);
  if FVideoUsed <> layoutAuto then
    FVideoReason := 'from its name'
  else
  begin
    FVideoUsed := layoutHalfSBS;
    FVideoReason := 'a film with no layout in its name: half side-by-side assumed';
  end;
end;

procedure TSRMovieRenderer.StopVideo;
begin
  if FVideo = nil then
    Exit;
  Log(Format('Film %s stopped at %s: %d pictures shown, %d decoded, %d dropped late',
    [FVideoName, TimeText(FVideo.Position), FVideo.Shown, FVideo.Decoded, FVideo.Dropped]));
  FreeAndNil(FVideo);
end;

procedure TSRMovieRenderer.TogglePause;
begin
  if FVideo = nil then
    Exit;
  FVideo.SetPaused(not FVideo.Paused);
  Log(Format('Film %s at %s', [IfThen(FVideo.Paused, 'paused', 'playing'),
    TimeText(FVideo.Position)]));
end;

procedure TSRMovieRenderer.SetVideoLayout(Value: TSRStereoLayout);
begin
  if Value = FVideoLayout then
    Exit;
  FVideoLayout := Value;
  if FVideo <> nil then
  begin
    DecideVideoLayout;
    Log(Format('Film layout: %s (%s) from the next picture',
      [TSRStereoFrame.LayoutName(FVideoUsed), FVideoReason]));
  end;
end;

procedure TSRMovieRenderer.ClearFrame;
begin
  StopVideo;
  if not FFrame.Loaded then
    Exit;
  FFrame.Clear;
  Log('Frame cleared: weaving the 3D scene');
end;

procedure TSRMovieRenderer.PumpVideo;
var
  W, H, Pitch: Integer;
  Secs: Double;
  Note, Err: string;
begin
  if FVideo.TakeFrame(FSpare, W, H, Pitch, Secs) then
    FFrame.SwapFrame(FSpare, W, H, Pitch, FVideoName, FVideoUsed);
  Note := FVideo.ColourNote;
  if (Note <> '') and (Note <> FColourLogged) then
  begin
    FColourLogged := Note;
    Log('Film colour: ' + Note);
  end;
  Note := FVideo.AudioNote;
  if (Note <> '') and (Note <> FAudioLogged) then
  begin
    FAudioLogged := Note;
    if FVideo.HasSound then
      Log('Film sound conversion: ' + Note + '; the pictures are timed by the sound');
  end;
  if not FErrorLogged then
  begin
    Err := FVideo.LastError;
    if Err <> '' then
    begin
      FErrorLogged := True;
      Log('Film ' + FVideoName + ': ' + Err);
    end;
  end;
  if not FEndLogged and FVideo.AtEnd then
  begin
    FEndLogged := True;
    Log(Format('Film %s ended at %s: %d pictures shown, %d decoded, %d dropped late, ' +
      '%d damaged packets skipped, %d sound shortfalls; the last picture stays',
      [FVideoName, TimeText(FVideo.Position), FVideo.Shown, FVideo.Decoded, FVideo.Dropped,
       FVideo.BadPackets, FVideo.Underruns]));
  end;
  if not FEndLogged and (FVideoLogClock.ElapsedMilliseconds >= VideoLogInterval) then
  begin
    FVideoLogClock := TStopwatch.StartNew;
    Log(Format('Film at %s of %s%s: %d pictures shown, %d decoded, %d dropped late, %s',
      [TimeText(FVideo.Position), TimeText(FVideo.Duration), IfThen(FVideo.Paused, ' (paused)', ''),
       FVideo.Shown, FVideo.Decoded, FVideo.Dropped,
       IfThen(FVideo.HasSound, Format('%d sound shortfalls', [FVideo.Underruns]), 'no sound')]));
  end;
end;

function TSRMovieRenderer.SupplyViews(ViewportW, ViewportH: Integer; Flat: Boolean;
  out Views: Pointer; out W, H, Pitch, Fmt: Integer): Boolean;
begin
  Fmt := SRB_FMT_BGRA8;
  if FVideo <> nil then
    PumpVideo;
  FFrame.RenderViews(ViewportW, ViewportH, Flat, Views, W, H, Pitch);
  Result := Views <> nil;
  if Result and ((FLoggedName <> FFrame.Name) or (FLoggedLayout <> FFrame.Layout) or
    (FLoggedW <> W) or (FLoggedH <> H) or (FLoggedFlat <> Flat)) then
  begin
    FLoggedName := FFrame.Name;
    FLoggedLayout := FFrame.Layout;
    FLoggedW := W;
    FLoggedH := H;
    FLoggedFlat := Flat;
    Log(Format('Frame %s fitted: %d x %d per eye in a %d x %d view (viewport %d x %d), %s (%s)%s',
      [FFrame.Name, FFrame.Width div 2, FFrame.Height, W, H, ViewportW, ViewportH,
       TSRStereoFrame.LayoutName(FFrame.Layout),
       IfThen(FVideo <> nil, FVideoReason, FFrame.LayoutReason),
       IfThen(Flat, ', flat (lens off): the left view in both', '')]));
  end;
end;

function TSRMovieRenderer.CopyFrameLeftView(Dest: TBitmap): Boolean;
var
  Pixels: TBytes;
  W, H, Y, X: Integer;
  Data: TBitmapData;
  Src, Dst: PByte;
begin
  Result := (Dest <> nil) and FFrame.LeftView(Pixels, W, H);
  if not Result then
    Exit;
  Dest.SetSize(W, H);
  Result := Dest.Map(TMapAccess.Write, Data);
  if not Result then
    Exit;
  try
    for Y := 0 to H - 1 do
    begin
      Src := @Pixels[Y * W * 4];
      Dst := Data.GetScanline(Y);
      if Data.PixelFormat = TPixelFormat.BGRA then
        Move(Src^, Dst^, W * 4)
      else
        // RGBA bitmaps: swap red and blue
        for X := 0 to W - 1 do
        begin
          Dst[X * 4] := Src[X * 4 + 2];
          Dst[X * 4 + 1] := Src[X * 4 + 1];
          Dst[X * 4 + 2] := Src[X * 4];
          Dst[X * 4 + 3] := Src[X * 4 + 3];
        end;
    end;
  finally
    Dest.Unmap(Data);
  end;
end;

end.

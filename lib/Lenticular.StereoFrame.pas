{ @abstract(One side-by-side stereo frame (full or half side-by-side) as raw
  pixels, fitted into a pair of views for the bridge's
  @code(lnb_SubmitViews); no FMX or VCL.)

  3D films are usually encoded half side-by-side (HSBS): each eye's view
  squeezed to half its width, the two side by side in a normal frame (a
  1920 x 1080 frame holds two 960 x 1080 halves, each shown at 1920 x 1080),
  left eye on the left. @link(TLenticularStereoFrame) holds one such frame, or a full
  side-by-side one, decides which it is (@link(TLenticularStereoLayout)), and gives:
  @unorderedList(
    @item(the two views for weaving (@link(TLenticularStereoFrame.RenderViews)),
      each at its stored width and letterboxed or pillarboxed in black so
      that, once the weaver stretches the views to the viewport, the picture
      has its proper shape;)
    @item(the left view at its proper shape, for showing in 2D while the display is
      off (@link(TLenticularStereoFrame.LeftView)).)
  )
  Frames come from a file (@link(TLenticularStereoFrame.LoadFromFile), through
  Windows Imaging Component: PNG, JPEG and anything else WIC reads) or from
  memory (@link(TLenticularStereoFrame.SetFrame), as a video decoder will give them).
  All pixels are 4 bytes, blue, green, red, alpha, top row first. Nothing here
  uses FMX or VCL, so FMX and VCL programs can share it. Windows only, as is
  the display runtime. }
unit Lenticular.StereoFrame;

interface

uses
  System.SysUtils;

type
  { How the two views are packed into a side-by-side frame. The left view is
    in the left half in every layout. }
  TLenticularStereoLayout = (
    { Decided from the file name, then the shape: a name with the word
      @code(hsbs) or @code(halfsbs), or @code(h) or @code(half) followed by
      @code(sbs), is half side-by-side; @code(fsbs), @code(fullsbs), or
      @code(f) or @code(full) followed by @code(sbs), is full side-by-side.
      Words are split at anything not a letter or digit, so
      @code(film.h-sbs.mkv) is half and @code(fresh-sbs.png) says nothing.
      Otherwise a frame at least twice as wide as it is high is full
      side-by-side, and anything narrower is half side-by-side. }
    layoutAuto,
    { Full side-by-side: each half is one view at its own shape (a 3840 x
      1080 frame holds two 1920 x 1080 views). }
    layoutFullSBS,
    { Half side-by-side (HSBS): each half is shown stretched to twice its
      width. }
    layoutHalfSBS);

  { One side-by-side stereo frame, fitted into views on request. }
  TLenticularStereoFrame = class
  private
    { The whole frame, @link(FPitch) bytes a row, top row first. }
    FPixels: TBytes;
    { Bytes from one row of @link(FPixels) to the next: at least
      @code(FWidth * 4), more when a decoder pads its rows. }
    FPitch: Integer;
    { The whole frame's width in pixels, 0 when none. }
    FWidth: Integer;
    { The whole frame's height in pixels, 0 when none. }
    FHeight: Integer;
    { See @link(TLenticularStereoFrame.Name). }
    FName: string;
    { See @link(TLenticularStereoFrame.Layout). }
    FLayout: TLenticularStereoLayout;
    { See @link(TLenticularStereoFrame.LayoutReason). }
    FLayoutReason: string;
    { See @link(TLenticularStereoFrame.Version). }
    FVersion: Integer;
    { The fitted views from @link(TLenticularStereoFrame.RenderViews). }
    FViews: TBytes;
    { The width of one fitted view in pixels. }
    FViewW: Integer;
    { The height of the fitted views in pixels. }
    FViewH: Integer;
    { @link(FVersion) when @link(FViews) was last fitted, -1 for never. }
    FFitVersion: Integer;
    { The viewport size @link(FViews) was last fitted to. }
    FFitViewportW, FFitViewportH: Integer;
    { Whether @link(FViews) was last fitted flat (the left view in both). }
    FFitFlat: Boolean;
    { Takes a new frame: decides its layout and makes the views stale.
      @param(Pixels the whole frame, Pitch bytes a row)
      @param(Width its width in pixels)
      @param(Height its height in pixels)
      @param(Pitch bytes from one row to the next)
      @param(Name what it is, for logs)
      @param(Layout the layout asked for; @code(layoutAuto) decides) }
    procedure Accept(var Pixels: TBytes; Width, Height, Pitch: Integer; const Name: string;
      Layout: TLenticularStereoLayout);
  public
    { Creates an empty frame; @link(TLenticularStereoFrame.Loaded) is @false until
      @link(TLenticularStereoFrame.LoadFromFile) or @link(TLenticularStereoFrame.SetFrame). }
    constructor Create;
    { Loads a side-by-side frame from a file with Windows Imaging Component.
      On failure the frame held so far is kept.
      @param(FileName full path of a PNG, JPEG or other WIC-readable file)
      @param(Layout how it is packed; @code(layoutAuto) (the default)
        decides from the name and shape)
      @raises(Exception saying which step failed and its HRESULT, if the
        file cannot be read, or is less than 2 pixels wide) }
    procedure LoadFromFile(const FileName: string; Layout: TLenticularStereoLayout = layoutAuto);
    { Takes a side-by-side frame from memory (a video decoder's frame, say),
      copying it.
      @param(Src the first pixel of the top row, 4 bytes a pixel: blue,
        green, red, alpha (alpha is set to 255))
      @param(Width its width in pixels, at least 2)
      @param(Height its height in pixels, at least 1)
      @param(Pitch bytes from one row to the next, at least @code(Width * 4))
      @param(Name what it is, for logs: a file name decides
        @code(layoutAuto) as in @link(TLenticularStereoFrame.LoadFromFile))
      @param(Layout how it is packed; @code(layoutAuto) (the default)
        decides from the name and shape)
      @raises(EArgumentException if the size or pitch is impossible) }
    procedure SetFrame(Src: Pointer; Width, Height, Pitch: Integer; const Name: string;
      Layout: TLenticularStereoLayout = layoutAuto);
    { Takes a side-by-side frame by swapping buffers rather than copying, for
      video: the caller's buffer becomes the frame, and the frame's previous
      buffer (nil at first) is given back for the caller to reuse.
      @param(Pixels the whole frame, Pitch bytes a row, top row first,
        already opaque (alpha 255); receives the previous buffer)
      @param(Width its width in pixels, at least 2)
      @param(Height its height in pixels, at least 1)
      @param(Pitch bytes from one row to the next, at least @code(Width * 4)
        (a decoder pads its rows: swscale writes past an unpadded row's end))
      @param(Name what it is, for logs and @code(layoutAuto))
      @param(Layout how it is packed; @code(layoutAuto) (the default)
        decides from the name and shape)
      @raises(EArgumentException if Pixels is too small for the size and
        pitch) }
    procedure SwapFrame(var Pixels: TBytes; Width, Height, Pitch: Integer; const Name: string;
      Layout: TLenticularStereoLayout = layoutAuto);
    { Forgets the frame. }
    procedure Clear;
    { @returns(@true once a frame is held) }
    function Loaded: Boolean;
    { Fits the two halves into a pair of views for a viewport of the given
      size, side by side in one buffer: each half at its stored width, with
      black bars so the picture keeps its proper shape once the weaver
      stretches the views to the viewport. Kept until the frame, the
      viewport size or Flat changes, so calling it every frame costs
      nothing.
      @param(ViewportW the viewport's width in pixels)
      @param(ViewportH the viewport's height in pixels)
      @param(Flat @true puts the left half in both views (the lens is off
        and the viewport is seen in 2D))
      @param(Views receives the first pixel of the top row, valid until the
        next call or the next frame; 4 bytes a pixel, blue, green, red,
        alpha)
      @param(W receives the width of one view in pixels)
      @param(H receives the height in pixels)
      @param(Pitch receives the bytes from one row to the next, @code(W * 2 *
        4))
      @returns(@true if the views were fitted again by this call (the frame,
        the viewport size or Flat changed), @false if they were kept; Views is
        nil and the result @false when no frame is held) }
    function RenderViews(ViewportW, ViewportH: Integer; Flat: Boolean; out Views: Pointer;
      out W, H, Pitch: Integer): Boolean;
    { The left view at its proper shape, for showing in 2D: a half
      side-by-side half stretched smoothly to twice its width, a full
      side-by-side half as it is.
      @param(Pixels receives it, @code(W * 4) bytes a row, top row first;
        4 bytes a pixel, blue, green, red, alpha)
      @param(W receives its width in pixels)
      @param(H receives its height in pixels)
      @returns(@false, with W and H 0, when no frame is held) }
    function LeftView(out Pixels: TBytes; out W, H: Integer): Boolean;
    { How many times wider each half is shown than it is stored.
      @returns(2 for half side-by-side, 1 for full side-by-side) }
    function Squeeze: Integer;
    { The side-by-side layout a name's tags give (see @code(layoutAuto)).
      @param(FileName a file name, with or without its folder)
      @returns(@code(layoutHalfSBS) or @code(layoutFullSBS), or
        @code(layoutAuto) when the name has no such tag) }
    class function LayoutFromName(const FileName: string): TLenticularStereoLayout; static;
    { A layout's name, for logs and menus.
      @param(Layout the layout)
      @returns(its name, such as @code(half side-by-side)) }
    class function LayoutName(Layout: TLenticularStereoLayout): string; static;
    { The whole frame's width in pixels, 0 when none. }
    property Width: Integer read FWidth;
    { The whole frame's height in pixels, 0 when none. }
    property Height: Integer read FHeight;
    { What the frame is, for logs: the file name without its folder, or the
      name given to @link(TLenticularStereoFrame.SetFrame). }
    property Name: string read FName;
    { The frame's layout as decided when it was taken (never
      @code(layoutAuto)). }
    property Layout: TLenticularStereoLayout read FLayout;
    { Why the layout is what it is, for logs: as asked, from the name, or
      from the shape. }
    property LayoutReason: string read FLayoutReason;
    { Counts the frames taken, so a caller can tell a new one has come. }
    property Version: Integer read FVersion;
  end;

implementation

uses
  Winapi.Windows, Winapi.ActiveX, Winapi.Wincodec, System.Win.ComObj, System.Math;

{ Raises an exception naming the step and its HRESULT if the call failed.
  @param(HR the call's result)
  @param(Step what was being done)
  @param(FileName the file it was done to) }
procedure CheckWic(HR: HRESULT; const Step, FileName: string);
begin
  if Failed(HR) then
    raise Exception.CreateFmt('%s: %s failed (HRESULT $%.8x)',
      [ExtractFileName(FileName), Step, Cardinal(HR)]);
end;

{ Sets every pixel's alpha to 255: the weaver and the 2D image should never
  see a frame as see-through.
  @param(Pixels 4 bytes a pixel, alpha last)
  @param(Count bytes in Pixels) }
procedure MakeOpaque(Pixels: PByte; Count: Integer);
var
  I: Integer;
begin
  Inc(Pixels, 3);
  for I := 0 to (Count div 4) - 1 do
  begin
    Pixels^ := $FF;
    Inc(Pixels, 4);
  end;
end;

constructor TLenticularStereoFrame.Create;
begin
  inherited Create;
  FLayout := layoutFullSBS;
  FFitVersion := -1;
end;

class function TLenticularStereoFrame.LayoutName(Layout: TLenticularStereoLayout): string;
const
  Names: array[TLenticularStereoLayout] of string = ('auto', 'full side-by-side',
    'half side-by-side');
begin
  Result := Names[Layout];
end;

class function TLenticularStereoFrame.LayoutFromName(const FileName: string): TLenticularStereoLayout;
var
  Words: TArray<string>;
  Name: string;
  I: Integer;
begin
  Result := layoutAuto;
  Name := LowerCase(ChangeFileExt(ExtractFileName(FileName), ''));
  for I := 1 to Length(Name) do
    if not CharInSet(Name[I], ['a'..'z', '0'..'9']) then
      Name[I] := ' ';
  Words := Name.Split([' '], TStringSplitOptions.ExcludeEmpty);
  // Whole words only: "fresh-sbs" says nothing
  for I := 0 to High(Words) do
  begin
    if (Words[I] = 'hsbs') or (Words[I] = 'halfsbs') or
      (((Words[I] = 'h') or (Words[I] = 'half')) and (I < High(Words)) and
       (Words[I + 1] = 'sbs')) then
      Exit(layoutHalfSBS);
    if (Words[I] = 'fsbs') or (Words[I] = 'fullsbs') or
      (((Words[I] = 'f') or (Words[I] = 'full')) and (I < High(Words)) and
       (Words[I + 1] = 'sbs')) then
      Exit(layoutFullSBS);
  end;
end;

procedure TLenticularStereoFrame.Accept(var Pixels: TBytes; Width, Height, Pitch: Integer;
  const Name: string; Layout: TLenticularStereoLayout);
begin
  if Layout <> layoutAuto then
    FLayoutReason := 'as asked'
  else
  begin
    Layout := LayoutFromName(Name);
    if Layout <> layoutAuto then
      FLayoutReason := 'from its name'
    else if Width >= 2 * Height then
    begin
      Layout := layoutFullSBS;
      FLayoutReason := 'from its shape: at least twice as wide as high';
    end
    else
    begin
      Layout := layoutHalfSBS;
      FLayoutReason := 'from its shape: less than twice as wide as high';
    end;
  end;
  FPixels := Pixels;   // reference counted: no copy
  Pixels := nil;
  FWidth := Width;
  FHeight := Height;
  FPitch := Pitch;
  FName := Name;
  FLayout := Layout;
  Inc(FVersion);
end;

procedure TLenticularStereoFrame.LoadFromFile(const FileName: string; Layout: TLenticularStereoLayout);
var
  HR: HRESULT;
  ComInit: Boolean;
  Factory: IWICImagingFactory;
  Decoder: IWICBitmapDecoder;
  Frame: IWICBitmapFrameDecode;
  Converter: IWICFormatConverter;
  W, H: UINT;
  Pixels: TBytes;
begin
  // WIC is COM: initialise it on this thread if nothing has yet (FMX and
  // VCL have on the main thread; a decoder thread may not have)
  HR := CoInitializeEx(nil, COINIT_APARTMENTTHREADED);
  ComInit := Succeeded(HR);
  try
    Factory := CreateComObject(CLSID_WICImagingFactory) as IWICImagingFactory;
    CheckWic(Factory.CreateDecoderFromFilename(PWideChar(FileName), GUID_NULL, GENERIC_READ,
      WICDecodeMetadataCacheOnDemand, Decoder), 'opening it (CreateDecoderFromFilename)', FileName);
    CheckWic(Decoder.GetFrame(0, Frame), 'reading its first frame', FileName);
    CheckWic(Factory.CreateFormatConverter(Converter), 'making a format converter', FileName);
    CheckWic(Converter.Initialize(Frame, GUID_WICPixelFormat32bppBGRA, WICBitmapDitherTypeNone,
      nil, 0, WICBitmapPaletteTypeCustom), 'converting it to 32-bit BGRA', FileName);
    CheckWic(Converter.GetSize(W, H), 'reading its size', FileName);
    if (W < 2) or (H < 1) then
      raise Exception.CreateFmt('%s is %d x %d: too small to hold two views',
        [ExtractFileName(FileName), W, H]);
    SetLength(Pixels, Int64(W) * H * 4);
    CheckWic(Converter.CopyPixels(nil, W * 4, Length(Pixels), @Pixels[0]),
      'reading its pixels', FileName);
  finally
    Converter := nil;
    Frame := nil;
    Decoder := nil;
    Factory := nil;
    if ComInit then
      CoUninitialize;
  end;
  MakeOpaque(@Pixels[0], Length(Pixels));
  Accept(Pixels, W, H, W * 4, ExtractFileName(FileName), Layout);
end;

procedure TLenticularStereoFrame.SetFrame(Src: Pointer; Width, Height, Pitch: Integer;
  const Name: string; Layout: TLenticularStereoLayout);
var
  Pixels: TBytes;
  Y: Integer;
  P: PByte;
begin
  if (Src = nil) or (Width < 2) or (Height < 1) or (Pitch < Width * 4) then
    raise EArgumentException.CreateFmt('SetFrame: impossible frame %d x %d, pitch %d',
      [Width, Height, Pitch]);
  SetLength(Pixels, Width * Height * 4);
  P := Src;
  for Y := 0 to Height - 1 do
  begin
    Move(P^, Pixels[Y * Width * 4], Width * 4);
    Inc(P, Pitch);
  end;
  MakeOpaque(@Pixels[0], Length(Pixels));
  Accept(Pixels, Width, Height, Width * 4, Name, Layout);
end;

procedure TLenticularStereoFrame.SwapFrame(var Pixels: TBytes; Width, Height, Pitch: Integer;
  const Name: string; Layout: TLenticularStereoLayout);
var
  Old: TBytes;
begin
  if (Width < 2) or (Height < 1) or (Pitch < Width * 4) or
    (Length(Pixels) < Int64(Pitch) * (Height - 1) + Width * 4) then
    raise EArgumentException.CreateFmt('SwapFrame: %d bytes cannot hold a %d x %d frame, pitch %d',
      [Length(Pixels), Width, Height, Pitch]);
  Old := FPixels;
  Accept(Pixels, Width, Height, Pitch, Name, Layout);   // takes Pixels, leaves it nil
  Pixels := Old;
end;

procedure TLenticularStereoFrame.Clear;
begin
  FPixels := nil;
  FViews := nil;
  FWidth := 0;
  FHeight := 0;
  FPitch := 0;
  FName := '';
  FLayoutReason := '';
  Inc(FVersion);
end;

function TLenticularStereoFrame.Loaded: Boolean;
begin
  Result := (FWidth >= 2) and (FHeight >= 1) and (Length(FPixels) > 0);
end;

function TLenticularStereoFrame.Squeeze: Integer;
begin
  if FLayout = layoutHalfSBS then
    Result := 2
  else
    Result := 1;
end;

function TLenticularStereoFrame.RenderViews(ViewportW, ViewportH: Integer; Flat: Boolean;
  out Views: Pointer; out W, H, Pitch: Integer): Boolean;
var
  SrcW, SrcH, OffX, OffY, Y, RightSrc: Integer;
  Aspect: Double;
  Row: PByte;
  Fill: PCardinal;
  I: Integer;
begin
  Views := nil;
  W := 0;
  H := 0;
  Pitch := 0;
  Result := False;
  if not Loaded then
    Exit;
  if (FFitVersion = FVersion) and (FFitViewportW = ViewportW) and
    (FFitViewportH = ViewportH) and (FFitFlat = Flat) and (Length(FViews) > 0) then
  begin
    Views := @FViews[0];
    W := FViewW;
    H := FViewH;
    Pitch := W * 2 * 4;
    Exit;
  end;
  // Each view gets the viewport's shape divided by the squeeze: the weaver
  // stretches it to the viewport, which widens a half side-by-side half,
  // and its bars, back to the shape it had before it was squeezed
  SrcW := FWidth div 2;
  SrcH := FHeight;
  Aspect := Max(1, ViewportW) / Max(1, ViewportH) / Squeeze;
  if SrcW / SrcH < Aspect then
  begin
    W := Max(SrcW, Round(SrcH * Aspect));
    H := SrcH;
  end
  else
  begin
    W := SrcW;
    H := Max(SrcH, Round(SrcW / Aspect));
  end;
  Pitch := W * 2 * 4;
  SetLength(FViews, Pitch * H);
  // Opaque black bars
  Fill := @FViews[0];
  for I := 0 to (Length(FViews) div 4) - 1 do
  begin
    Fill^ := $FF000000;
    Inc(Fill);
  end;
  OffX := (W - SrcW) div 2;
  OffY := (H - SrcH) div 2;
  if Flat then
    RightSrc := 0
  else
    RightSrc := SrcW;
  for Y := 0 to SrcH - 1 do
  begin
    Row := @FPixels[Y * FPitch];
    Move(Row^, FViews[(Y + OffY) * Pitch + OffX * 4], SrcW * 4);
    Move(PByte(Row + RightSrc * 4)^, FViews[(Y + OffY) * Pitch + (W + OffX) * 4], SrcW * 4);
  end;
  FViewW := W;
  FViewH := H;
  FFitVersion := FVersion;
  FFitViewportW := ViewportW;
  FFitViewportH := ViewportH;
  FFitFlat := Flat;
  Views := @FViews[0];
  Result := True;
end;

function TLenticularStereoFrame.LeftView(out Pixels: TBytes; out W, H: Integer): Boolean;
var
  SrcW, S, X, Y, C: Integer;
  X0: TArray<Integer>;
  Frac: TArray<Single>;
  Pos: Single;
  Src, Dst: PByte;
begin
  Pixels := nil;
  W := 0;
  H := 0;
  Result := Loaded;
  if not Result then
    Exit;
  SrcW := FWidth div 2;
  S := Squeeze;
  W := SrcW * S;
  H := FHeight;
  SetLength(Pixels, W * H * 4);
  if S = 1 then
  begin
    for Y := 0 to H - 1 do
      Move(FPixels[Y * FPitch], Pixels[Y * W * 4], W * 4);
    Exit;
  end;
  // Stretch across only, sampling between neighbouring pixels (linear), so
  // edges stay smooth; each output pixel's source position, worked out once
  SetLength(X0, W);
  SetLength(Frac, W);
  for X := 0 to W - 1 do
  begin
    Pos := EnsureRange((X + 0.5) / S - 0.5, 0.0, SrcW - 1.0);
    X0[X] := Min(Integer(Trunc(Pos)), SrcW - 2);
    if X0[X] < 0 then
      X0[X] := 0;
    Frac[X] := Pos - X0[X];
  end;
  for Y := 0 to H - 1 do
  begin
    Src := @FPixels[Y * FPitch];
    Dst := @Pixels[Y * W * 4];
    for X := 0 to W - 1 do
    begin
      for C := 0 to 3 do
        Dst[X * 4 + C] := Round(Src[X0[X] * 4 + C] * (1 - Frac[X]) +
          Src[Min(X0[X] + 1, SrcW - 1) * 4 + C] * Frac[X]);
    end;
  end;
end;

end.

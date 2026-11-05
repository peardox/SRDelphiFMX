{ @abstract(A side-by-side stereo image, fitted into a pair of views of any
  size, as top-down BGRA pixels for @code(srb_SubmitViews).)

  The image is loaded with Windows Imaging Component (PNG, JPEG and anything
  else WIC reads), or drawn as a numbered test pattern. Each half is scaled
  with GDI's halftone filter to fit its view, keeping its shape, with black
  bars. No FMX: used by programs that have no FMX canvas, such as
  SRDemoVCL. Windows only, as is the SR runtime. }
unit SRStereoImage;

interface

uses
  System.SysUtils, Vcl.Graphics;

type
  { One side-by-side stereo image: the left view in the left half. }
  TSRStereoImage = class
  private
    { The whole side-by-side image, 32 bits per pixel. }
    FSource: Vcl.Graphics.TBitmap;
    { What the image is: the file name without its folder, or
      @code(test pattern). }
    FName: string;
  public
    { Creates an empty image; call @link(LoadFromFile) or
      @link(MakeTestPattern) before @link(RenderViews). }
    constructor Create;
    { Frees the image. }
    destructor Destroy; override;
    { Loads a side-by-side image file. Raises an exception if it cannot be
      read.
      @param(FileName full path of a PNG, JPEG or other WIC-readable file) }
    procedure LoadFromFile(const FileName: string);
    { Draws a test pattern: in each view ten numbered vertical bands, the
      eye's name, and a white square drawn 48 pixels further right in the
      left view than in the right, so it stands in front of the screen. A
      view showing the wrong part of an image shows the wrong numbers.
      @param(ViewWidth width of each view in pixels)
      @param(ViewHeight height of each view in pixels) }
    procedure MakeTestPattern(ViewWidth, ViewHeight: Integer);
    { Fits each half of the image into a view of the given size and writes
      both views side by side, top row first, 4 bytes per pixel (blue,
      green, red, alpha 255): @code(ViewWidth * 2 * 4) bytes a row.
      @param(ViewWidth width of each view in pixels)
      @param(ViewHeight height of each view in pixels)
      @param(Pixels receives the pixels; resized as needed) }
    procedure RenderViews(ViewWidth, ViewHeight: Integer; var Pixels: TBytes);
    { @returns(@true once an image or pattern is loaded) }
    function Loaded: Boolean;
    { @returns(the whole side-by-side image's width in pixels, 0 when none) }
    function SourceWidth: Integer;
    { @returns(the image's height in pixels, 0 when none) }
    function SourceHeight: Integer;
    { What the image is, for logs: the file name or @code(test pattern). }
    property Name: string read FName;
  end;

implementation

uses
  Winapi.Windows, System.Types, System.Math;

constructor TSRStereoImage.Create;
begin
  inherited Create;
  FName := '';
end;

destructor TSRStereoImage.Destroy;
begin
  FreeAndNil(FSource);
  inherited;
end;

function TSRStereoImage.Loaded: Boolean;
begin
  Result := (FSource <> nil) and (FSource.Width > 1) and (FSource.Height > 0);
end;

function TSRStereoImage.SourceWidth: Integer;
begin
  if FSource = nil then
    Result := 0
  else
    Result := FSource.Width;
end;

function TSRStereoImage.SourceHeight: Integer;
begin
  if FSource = nil then
    Result := 0
  else
    Result := FSource.Height;
end;

procedure TSRStereoImage.LoadFromFile(const FileName: string);
var
  Wic: TWICImage;
  Bmp: Vcl.Graphics.TBitmap;
begin
  Wic := TWICImage.Create;
  try
    Wic.LoadFromFile(FileName);
    Bmp := Vcl.Graphics.TBitmap.Create;
    try
      Bmp.PixelFormat := pf32bit;
      Bmp.SetSize(Wic.Width, Wic.Height);
      Bmp.Canvas.Brush.Color := clBlack;
      Bmp.Canvas.FillRect(Rect(0, 0, Bmp.Width, Bmp.Height));
      Bmp.Canvas.Draw(0, 0, Wic);
    except
      Bmp.Free;
      raise;
    end;
  finally
    Wic.Free;
  end;
  FreeAndNil(FSource);
  FSource := Bmp;
  FName := ExtractFileName(FileName);
end;

procedure TSRStereoImage.MakeTestPattern(ViewWidth, ViewHeight: Integer);
const
  Bands = 10;
  Disparity = 24;   // pixels each way: the square is 48 px further right in the left view
var
  Bmp: Vcl.Graphics.TBitmap;
  Eye, Band, X0, BandW, Side, Cx, Cy, Shift: Integer;
  C: TCanvas;
  Txt: string;
begin
  ViewWidth := Max(ViewWidth, 64);
  ViewHeight := Max(ViewHeight, 64);
  Bmp := Vcl.Graphics.TBitmap.Create;
  try
    Bmp.PixelFormat := pf32bit;
    Bmp.SetSize(ViewWidth * 2, ViewHeight);
    C := Bmp.Canvas;
    BandW := ViewWidth div Bands;
    for Eye := 0 to 1 do
    begin
      X0 := Eye * ViewWidth;
      for Band := 0 to Bands - 1 do
      begin
        if Odd(Band) then
          C.Brush.Color := RGB(70, 70, 90)
        else
          C.Brush.Color := RGB(40, 40, 55);
        C.Brush.Style := bsSolid;
        C.FillRect(Rect(X0 + Band * BandW, 0, X0 + (Band + 1) * BandW, ViewHeight));
        C.Brush.Style := bsClear;
        C.Font.Name := 'Arial';
        C.Font.Height := -(ViewHeight div 8);
        C.Font.Color := RGB(255, 220, 0);
        Txt := IntToStr(Band);
        C.TextOut(X0 + Band * BandW + (BandW - C.TextWidth(Txt)) div 2, ViewHeight div 20, Txt);
      end;
      // Thin red lines at the view's own edges
      C.Brush.Style := bsSolid;
      C.Brush.Color := RGB(255, 0, 0);
      C.FillRect(Rect(X0, 0, X0 + 4, ViewHeight));
      C.FillRect(Rect(X0 + ViewWidth - 4, 0, X0 + ViewWidth, ViewHeight));

      // The square in front of the screen
      Side := ViewHeight div 4;
      if Eye = 0 then
        Shift := Disparity
      else
        Shift := -Disparity;
      Cx := X0 + ViewWidth div 2 + Shift;
      Cy := ViewHeight div 2;
      C.Brush.Color := RGB(255, 255, 255);
      C.FillRect(Rect(Cx - Side div 2, Cy - Side div 2, Cx + Side div 2, Cy + Side div 2));

      // The eye's name, at the screen (same place in both views)
      C.Brush.Style := bsClear;
      C.Font.Height := -(ViewHeight div 10);
      C.Font.Color := RGB(0, 255, 120);
      if Eye = 0 then
        Txt := 'LEFT EYE'
      else
        Txt := 'RIGHT EYE';
      C.TextOut(X0 + (ViewWidth - C.TextWidth(Txt)) div 2, (ViewHeight * 3) div 4, Txt);
    end;
  except
    Bmp.Free;
    raise;
  end;
  FreeAndNil(FSource);
  FSource := Bmp;
  FName := Format('test pattern %d x %d', [ViewWidth, ViewHeight]);
end;

procedure TSRStereoImage.RenderViews(ViewWidth, ViewHeight: Integer; var Pixels: TBytes);
var
  Dest: Vcl.Graphics.TBitmap;
  DC, SrcDC: HDC;
  HalfW, SrcH, FitW, FitH, OffX, OffY, Y, RowBytes, I: Integer;
  Scale: Double;
  P: PByte;
begin
  if (ViewWidth < 1) or (ViewHeight < 1) then
    raise EArgumentException.Create('RenderViews: empty view size');
  RowBytes := ViewWidth * 2 * 4;
  SetLength(Pixels, RowBytes * ViewHeight);
  Dest := Vcl.Graphics.TBitmap.Create;
  try
    Dest.PixelFormat := pf32bit;
    Dest.SetSize(ViewWidth * 2, ViewHeight);
    Dest.Canvas.Brush.Color := clBlack;
    Dest.Canvas.FillRect(Rect(0, 0, Dest.Width, Dest.Height));
    if Loaded then
    begin
      HalfW := FSource.Width div 2;
      SrcH := FSource.Height;
      Scale := Min(ViewWidth / HalfW, ViewHeight / SrcH);
      FitW := Max(1, Round(HalfW * Scale));
      FitH := Max(1, Round(SrcH * Scale));
      OffX := (ViewWidth - FitW) div 2;
      OffY := (ViewHeight - FitH) div 2;
      Dest.Canvas.Lock;
      FSource.Canvas.Lock;
      try
        DC := Dest.Canvas.Handle;
        SrcDC := FSource.Canvas.Handle;
        SetStretchBltMode(DC, HALFTONE);
        SetBrushOrgEx(DC, 0, 0, nil);
        StretchBlt(DC, OffX, OffY, FitW, FitH, SrcDC, 0, 0, HalfW, SrcH, SRCCOPY);
        StretchBlt(DC, ViewWidth + OffX, OffY, FitW, FitH, SrcDC, HalfW, 0, HalfW, SrcH, SRCCOPY);
        GdiFlush;
      finally
        FSource.Canvas.Unlock;
        Dest.Canvas.Unlock;
      end;
    end;
    for Y := 0 to ViewHeight - 1 do
      Move(Dest.ScanLine[Y]^, Pixels[Y * RowBytes], RowBytes);
  finally
    Dest.Free;
  end;
  // GDI leaves alpha at 0
  P := @Pixels[3];
  for I := 0 to (Length(Pixels) div 4) - 1 do
  begin
    P^ := $FF;
    Inc(P, 4);
  end;
end;

end.

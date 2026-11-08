{ @abstract(The demos' settings dialog: the eye separation used for
  glasses-free 3D.)

  A plain Windows dialog, built in memory (no resource file), modal, owned
  by the program's window and centred on it, so it is in front of the
  window and readable (FMX's own dialogs once came up behind it). No FMX or
  VCL: both demos use it. }
unit Lenticular.SettingsDialog;

interface

const
  { The largest eye separation the dialog accepts, mm. }
  MaxEyeSeparationMM = 90;

{ Asks for the eye separation.
  @param(Owner the window that owns the dialog (the form's HWND), 0 for none)
  @param(AppName the program's name, for the title bar)
  @param(SeparationMM the current separation in mm (0 = as tracked) on
    entry; the new one on @true)
  @returns(@true if the user pressed OK with a valid value) }
function AskEyeSeparation(Owner: NativeUInt; const AppName: string;
  var SeparationMM: Integer): Boolean;

implementation

uses
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Classes;

const
  { The edit box's ID. }
  IdEdit = 100;
  { The prompt's ID. }
  IdPrompt = 101;
  { The note's ID. }
  IdNote = 102;
  { Control class atom: button. }
  AtomButton = $0080;
  { Control class atom: edit box. }
  AtomEdit = $0081;
  { Control class atom: static text. }
  AtomStatic = $0082;

{ Pads the template to a 4-byte boundary, as each item must start on one.
  @param(S the template) }
procedure AlignDWord(S: TMemoryStream);
const
  Zero: Byte = 0;
begin
  while S.Position mod 4 <> 0 do
    S.WriteBuffer(Zero, 1);
end;

{ Writes a 16-bit value. @param(S the template) @param(W the value) }
procedure WriteWord(S: TMemoryStream; W: Word);
begin
  S.WriteBuffer(W, 2);
end;

{ Writes a 32-bit value. @param(S the template) @param(D the value) }
procedure WriteDWord(S: TMemoryStream; D: Cardinal);
begin
  S.WriteBuffer(D, 4);
end;

{ Writes a string as UTF-16 with its terminating zero.
  @param(S the template) @param(Text the string) }
procedure WriteStr(S: TMemoryStream; const Text: string);
begin
  if Text <> '' then
    S.WriteBuffer(Text[1], Length(Text) * SizeOf(Char));
  WriteWord(S, 0);
end;

{ Writes one control's item template.
  @param(S the template)
  @param(Style the control's window style)
  @param(X left, dialog units) @param(Y top, dialog units)
  @param(CX width, dialog units) @param(CY height, dialog units)
  @param(Id the control's ID)
  @param(Atom the control class atom)
  @param(Text the control's text) }
procedure WriteItem(S: TMemoryStream; Style: Cardinal; X, Y, CX, CY: SmallInt; Id: Word;
  Atom: Word; const Text: string);
begin
  AlignDWord(S);
  WriteDWord(S, Style or WS_CHILD or WS_VISIBLE);
  WriteDWord(S, 0);   // extended style
  WriteWord(S, Word(X));
  WriteWord(S, Word(Y));
  WriteWord(S, Word(CX));
  WriteWord(S, Word(CY));
  WriteWord(S, Id);
  WriteWord(S, $FFFF);   // a class atom follows
  WriteWord(S, Atom);
  WriteStr(S, Text);
  WriteWord(S, 0);       // no creation data
end;

{ The dialog procedure. @param(Dlg the dialog) @param(Msg the message)
  @param(WP its WPARAM) @param(LP its LPARAM: on WM_INITDIALOG, a pointer
  to the separation)
  @returns(non-zero when the message was handled) }
function DlgProc(Dlg: HWND; Msg: UINT; WP: WPARAM; LP: LPARAM): INT_PTR; stdcall;
var
  Owner: HWND;
  R, DR: TRect;
  Value: UINT;
  Ok: BOOL;
begin
  Result := 0;
  case Msg of
    WM_INITDIALOG:
      begin
        SetWindowLongPtr(Dlg, DWLP_USER, LP);
        SetDlgItemInt(Dlg, IdEdit, UINT(PInteger(LP)^), False);
        SendDlgItemMessage(Dlg, IdEdit, EM_LIMITTEXT, 2, 0);
        // Centred on the owner, not on its monitor
        Owner := GetWindow(Dlg, GW_OWNER);
        if (Owner <> 0) and GetWindowRect(Owner, R) and GetWindowRect(Dlg, DR) then
          SetWindowPos(Dlg, 0, R.Left + (R.Width - DR.Width) div 2, R.Top + (R.Height - DR.Height) div 2,
            0, 0, SWP_NOSIZE or SWP_NOZORDER or SWP_NOACTIVATE);
        Result := 1;   // focus to the first control that takes it: the edit box
      end;
    WM_COMMAND:
      case LOWORD(WP) of
        IDOK:
          begin
            Value := GetDlgItemInt(Dlg, IdEdit, Ok, False);
            if Ok and (Value <= MaxEyeSeparationMM) then
            begin
              PInteger(GetWindowLongPtr(Dlg, DWLP_USER))^ := Integer(Value);
              EndDialog(Dlg, IDOK);
            end
            else
            begin
              MessageBeep(MB_ICONWARNING);
              SetFocus(GetDlgItem(Dlg, IdEdit));
              SendDlgItemMessage(Dlg, IdEdit, EM_SETSEL, 0, -1);
            end;
            Result := 1;
          end;
        IDCANCEL:
          begin
            EndDialog(Dlg, IDCANCEL);
            Result := 1;
          end;
      end;
  end;
end;

function AskEyeSeparation(Owner: NativeUInt; const AppName: string;
  var SeparationMM: Integer): Boolean;
var
  S: TMemoryStream;
  Value: Integer;
begin
  Value := SeparationMM;
  if (Value < 0) or (Value > MaxEyeSeparationMM) then
    Value := 0;
  S := TMemoryStream.Create;
  try
    // DLGTEMPLATE, then menu, class, title and font
    WriteDWord(S, DS_MODALFRAME or DS_SETFONT or WS_POPUP or WS_CAPTION or WS_SYSMENU);
    WriteDWord(S, 0);   // extended style
    WriteWord(S, 5);    // controls
    WriteWord(S, 0);    // x, y: centred on the owner in WM_INITDIALOG
    WriteWord(S, 0);
    WriteWord(S, 230);  // width, dialog units
    WriteWord(S, 86);   // height
    WriteWord(S, 0);    // no menu
    WriteWord(S, 0);    // standard dialog class
    WriteStr(S, AppName + ' settings');
    WriteWord(S, 9);    // font size, points
    WriteStr(S, 'Segoe UI');

    WriteItem(S, SS_LEFT, 10, 12, 140, 10, IdPrompt, AtomStatic, 'Eye separation (mm):');
    WriteItem(S, WS_BORDER or WS_TABSTOP or ES_NUMBER or ES_AUTOHSCROLL, 160, 10, 40, 13, IdEdit,
      AtomEdit, '');
    WriteItem(S, SS_LEFT, 10, 30, 210, 28, IdNote, AtomStatic,
      'The distance between the centres of your pupils. 0 uses the eye tracker''s ' +
      'measurement; 63 mm is typical. Up to ' + IntToStr(MaxEyeSeparationMM) + ' mm.');
    WriteItem(S, WS_TABSTOP or BS_DEFPUSHBUTTON, 110, 64, 50, 14, IDOK, AtomButton, 'OK');
    WriteItem(S, WS_TABSTOP or BS_PUSHBUTTON, 170, 64, 50, 14, IDCANCEL, AtomButton, 'Cancel');

    Result := DialogBoxIndirectParam(HInstance, PDlgTemplate(S.Memory)^, HWND(Owner), @DlgProc,
      LPARAM(@Value)) = IDOK;
  finally
    S.Free;
  end;
  if Result then
    SeparationMM := Value;
end;

end.

{ @abstract(Shows a form's main menu on Linux with an FMX menu bar instead
  of GTK's.)

  On Linux FMX shows a TMainMenu as a native GTK menu bar, which shows only
  the first letter of each menu and item ("F" instead of "File").
  @link(ReplaceMainMenu) puts COPIES of the menus on an FMX TMenuBar and
  removes the TMainMenu item by item, which neither leaves GTK's bar showing
  nor leaves items pointing at destroyed GTK widgets (moving the original
  items crashes in libgobject or floods the terminal with GTK-CRITICAL
  warnings; freeing the TMainMenu with its items still in it leaves GTK's
  bar on screen). On other platforms it does nothing.

  Method tested by the owner in another project (GDEMFetch, Delphi 13,
  Ubuntu / GTK 3, October 2026). Identical copies live in this
  repository - in the src folder of SteamDemo, SteamInputDemo,
  VirtualGamepad and RemoteLogging/LogReceiver - because projects use only
  their own sources; tools/project_check.py lists them (MENU_DIRS) and
  reports any difference. }
unit FmxLinuxMenu;

interface

uses
  FMX.Forms, FMX.Menus;

{ Replaces a form's TMainMenu with an FMX TMenuBar, on Linux only. Call it
  FIRST in the form's OnCreate, before any code changes a menu item or adds
  items at run time.

  Every item is copied with its submenus: Text, Enabled, Visible, AutoCheck,
  IsChecked, RadioItem, GroupIndex, ShortCut, Tag and OnClick (add any other
  property a form uses to CopyItem). Each copy is then given its original's
  name, which points the form's published field at it, so code that uses
  those fields carries on working. References to the original items kept
  anywhere else are left pointing at freed objects, so take none before
  calling this.
  @param(AForm The form the menu bar goes on.)
  @param(AMenu The form's TMainMenu, usually its published field. It is
    freed and set to nil on Linux.)
  @returns(The new menu bar, owned by AForm; nil on other platforms, or if
    AMenu is nil.) }
function ReplaceMainMenu(AForm: TCommonCustomForm; var AMenu: TMainMenu): TMenuBar;

implementation

uses
  System.SysUtils, System.Classes, FMX.Types;

{$IF defined(LINUX) and not defined(ANDROID)}
function ReplaceMainMenu(AForm: TCommonCustomForm; var AMenu: TMainMenu): TMenuBar;
var
  LOwner: TComponent;
  LCopies: TArray<TMenuItem>;
  LNames: TArray<string>;
  LIndex: Integer;

  { Copies AItem and its submenus into AParent (the menu bar or a menu
    item), noting the original's name for later. }
  procedure CopyItem(AItem: TMenuItem; AParent: TFmxObject);
  var
    LCopy: TMenuItem;
    LSub: Integer;
  begin
    // owned like the original, so naming it later sets the owner's field
    LCopy := TMenuItem.Create(LOwner);
    LCopy.Text := AItem.Text;
    LCopy.Enabled := AItem.Enabled;
    LCopy.Visible := AItem.Visible;
    LCopy.AutoCheck := AItem.AutoCheck;
    LCopy.IsChecked := AItem.IsChecked;
    LCopy.RadioItem := AItem.RadioItem;
    LCopy.GroupIndex := AItem.GroupIndex;
    LCopy.ShortCut := AItem.ShortCut;
    LCopy.Tag := AItem.Tag;
    LCopy.OnClick := AItem.OnClick;
    LCopy.Parent := AParent;
    LCopies := LCopies + [LCopy];
    LNames := LNames + [AItem.Name];
    for LSub := 0 to AItem.ItemsCount - 1 do
      CopyItem(AItem.Items[LSub], LCopy);
  end;

begin
  Result := nil;
  if AMenu = nil then
    Exit;
  LOwner := AMenu.Owner;
  if LOwner = nil then
    LOwner := AForm;

  Result := TMenuBar.Create(AForm);
  Result.Parent := AForm;
  // top-aligned controls are laid out in the order of their positions, so
  // this puts the menu bar above any other top-aligned control
  Result.Position.Y := -1;
  Result.Align := TAlignLayout.Top;
  for LIndex := 0 to AMenu.ItemsCount - 1 do
    if AMenu.Items[LIndex] is TMenuItem then
      CopyItem(TMenuItem(AMenu.Items[LIndex]), Result);

  // empty the TMainMenu item by item: each removal makes FMX rebuild the GTK
  // bar without that item, so it ends up empty and goes (freeing the
  // TMainMenu with items still in it leaves GTK's bar showing); each
  // original's field on the form is set to nil as it is freed
  while AMenu.ItemsCount > 0 do
    AMenu.Items[0].Free;
  AMenu.RecreateOSMenu;
  FreeAndNil(AMenu);

  // naming a copy points the owner's published field of that name at it
  for LIndex := 0 to High(LCopies) do
    if LNames[LIndex] <> '' then
      LCopies[LIndex].Name := LNames[LIndex];
end;
{$ELSE}
function ReplaceMainMenu(AForm: TCommonCustomForm; var AMenu: TMainMenu): TMenuBar;
begin
  Result := nil;
end;
{$ENDIF}

end.

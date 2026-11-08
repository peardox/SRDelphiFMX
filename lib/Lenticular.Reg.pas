//** @abstract(Registers the Lenticular components on the Lenticular page of the IDE's
//** palette.)
//**
//** Design-time only: it goes in the dclLenticular design package, never in a program. The
//** palette icons come from Lenticular.Reg.dcr beside it, made from lib/icons by
//** tools/gen_icon_res.py; never edit the .dcr by hand.
//**
//** The components work with FireMonkey controls, so they are grouped with TFmxObject and show
//** on the palette only while an FMX form or frame is being designed. Nothing here needs
//** Gorilla3D or the Spritely components: either set may be installed without the other.
unit Lenticular.Reg;

{
  Registers the Lenticular components on the Lenticular page of the IDE's
  palette.

  Design-time only: it goes in the dclLenticular design package, never in
  a program. The palette icons come from Lenticular.Reg.dcr beside it, made
  from lib/icons by tools/gen_icon_res.py; never edit the .dcr by hand.

  The components work with FireMonkey controls, so they are grouped with
  TFmxObject and show on the palette only while an FMX form or frame is
  being designed. Nothing here needs Gorilla3D or the Spritely components.
}

interface

//** @abstract(Called by the IDE when the design package is installed: puts every Lenticular
//** component on the Lenticular page.)
procedure Register;

implementation

{$R Lenticular.Reg.dcr}

uses
  System.Classes, FMX.Types,
  Lenticular.Display;

const
  //** @abstract(The palette page, the component group, the components appear on.)
  LENTICULAR_PALETTE_PAGE = 'Lenticular';

procedure Register;
begin
  // FMX-only: hidden from the palette while a VCL form is designed
  GroupDescendentsWith(TLenticularDisplay, TFmxObject);
  RegisterComponents(LENTICULAR_PALETTE_PAGE, [TLenticularDisplay]);
end;

end.

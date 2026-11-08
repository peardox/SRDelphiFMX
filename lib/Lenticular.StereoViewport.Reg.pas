{ @abstract(Registers @link(TLenticularStereoRenderer) on the IDE's component
  palette.)

  Put this unit in a design-time package that requires the runtime package
  holding @link(Lenticular.StereoViewport). }
unit Lenticular.StereoViewport.Reg;

interface

{ Adds @link(TLenticularStereoRenderer) to the Lenticular palette page. }
procedure Register;

implementation

uses
  System.Classes, Lenticular.StereoViewport;

procedure Register;
begin
  RegisterComponents('Lenticular', [TLenticularStereoRenderer]);
end;

end.

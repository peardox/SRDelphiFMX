{ @abstract(Registers @link(TSRStereoRenderer) on the IDE's component
  palette.)

  Put this unit in a design-time package that requires the runtime package
  holding @link(FMX.SRStereoViewport). }
unit FMX.SRStereoViewport.Reg;

interface

{ Adds @link(TSRStereoRenderer) to the LeiaSR palette page. }
procedure Register;

implementation

uses
  System.Classes, FMX.SRStereoViewport;

procedure Register;
begin
  RegisterComponents('LeiaSR', [TSRStereoRenderer]);
end;

end.

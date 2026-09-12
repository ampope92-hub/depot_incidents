{ Programme list for the depot safety programme.
  Usage: watch <data-dir> <output-json>. Writes the depots to put on the programme. }
program watch;
{$mode objfpc}{$H+}
uses
  SysUtils;
begin
  { TODO: read the export in ParamStr(1), pick the depots, write ParamStr(2) }
  writeln(StdErr, 'not implemented');
  Halt(1);
end.

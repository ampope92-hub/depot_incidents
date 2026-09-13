{ Programme list for the depot safety programme: which depots get the intervention.

  The league table in the memo ranks depots by logged incidents per hour worked, and most of
  what it ranks is how keen a depot's staff are to log a minor incident, which varies from
  almost never to almost always. A severe incident is logged whatever the depot's habits are,
  the insurer sees every one of them, so the count of severe incidents per hour worked is
  the one figure in the log that measures the depot and not its paperwork. The list is the
  depots with the highest severe rate over the logged years, as many as the policy asks for.

  A depot's rate does not move from one year to the next, so the severe rate over the logged
  years is the rate it will be running at in the programme year.

  Three things about the export. The hours a depot works sit in two sets of columns, payroll and
  agency, and the rate is per hour worked, so both are summed. A depot the register marks as
  merged into another is the same depot as its survivor: from the merge its incidents are logged
  under the survivor's id while payroll kept its hours on the old row, so the two rows are folded
  into one before anything is ranked, and the merged id is not a candidate. And the log's depot
  column is the injured person's own depot, not where it happened: the site column is where it
  happened, and the app counts an incident where it happened, so the tally here is by site. }
program watch;
{$mode objfpc}{$H+}
uses
  SysUtils, Classes;

type
  TDepot = record
    id: string;
    mergedInto: string; { blank, or the id of the depot this one was folded into }
    hours: Double;      { hours worked over the log years, payroll and agency together }
    severe: Integer;    { severe incidents over the log years }
    logged: Integer;    { every logged incident, for reference }
    score: Double;
  end;

var
  depots: array of TDepot;
  dataDir, outPath: string;
  listSize, yearFrom, yearTo: Integer;

function ReadWhole(const path: string): string;
var
  s: TStringList;
begin
  s := TStringList.Create;
  try
    s.LoadFromFile(path);
    Result := s.Text;
  finally
    s.Free;
  end;
end;

{ the policy is a small JSON object; the two things needed are pulled out by name }
function JsonInt(const text, key: string; nth: Integer): Integer;
var
  p, q: Integer;
  digits: string;
begin
  p := Pos('"' + key + '"', text);
  if p = 0 then
  begin
    writeln(StdErr, 'policy.json has no ', key);
    Halt(1);
  end;
  p := p + Length(key) + 2;
  { skip to the nth run of digits after the key }
  while nth > 0 do
  begin
    while (p <= Length(text)) and not (text[p] in ['0'..'9']) do Inc(p);
    q := p;
    while (q <= Length(text)) and (text[q] in ['0'..'9']) do Inc(q);
    digits := Copy(text, p, q - p);
    p := q;
    Dec(nth);
  end;
  Result := StrToInt(digits);
end;

function FindDepot(const id: string): Integer;
var
  i: Integer;
begin
  for i := 0 to High(depots) do
    if depots[i].id = id then Exit(i);
  Result := -1;
end;

procedure Split(const line: string; fields: TStringList);
begin
  fields.Clear;
  fields.StrictDelimiter := True;
  fields.Delimiter := ',';
  fields.DelimitedText := line;
end;

procedure LoadDepots;
var
  rows, f: TStringList;
  i, c, y, n, mergedCol: Integer;
  hoursCol: array of Integer;
begin
  rows := TStringList.Create;
  f := TStringList.Create;
  try
    rows.LoadFromFile(dataDir + '/depots.csv');
    Split(rows[0], f);
    mergedCol := f.IndexOf('merged_into');
    SetLength(hoursCol, 0);
    { every hours column for a log year counts, payroll (labour_hours_) and agency (agency_hours_) }
    for c := 0 to f.Count - 1 do
      if (Pos('labour_hours_', f[c]) = 1) or (Pos('agency_hours_', f[c]) = 1) then
      begin
        y := StrToInt(Copy(f[c], Length('labour_hours_') + 1, 8));
        if (y >= yearFrom) and (y <= yearTo) then
        begin
          SetLength(hoursCol, Length(hoursCol) + 1);
          hoursCol[High(hoursCol)] := c;
        end;
      end;
    n := 0;
    SetLength(depots, rows.Count - 1);
    for i := 1 to rows.Count - 1 do
    begin
      if Trim(rows[i]) = '' then Continue;
      Split(rows[i], f);
      depots[n].id := f[0];
      if mergedCol >= 0 then depots[n].mergedInto := Trim(f[mergedCol]) else depots[n].mergedInto := '';
      depots[n].hours := 0;
      for c := 0 to High(hoursCol) do
        depots[n].hours := depots[n].hours + StrToFloat(f[hoursCol[c]]);
      depots[n].severe := 0;
      depots[n].logged := 0;
      Inc(n);
    end;
    SetLength(depots, n);
  finally
    rows.Free;
    f.Free;
  end;
end;

{ An incident is tallied at the site where it happened, not under the depot column, which is
  the depot the injured person is on the books of. Columns are found by name. }
procedure LoadIncidents;
var
  rows, f: TStringList;
  i, d, y, siteCol, dateCol, sevCol: Integer;
begin
  rows := TStringList.Create;
  f := TStringList.Create;
  try
    rows.LoadFromFile(dataDir + '/incidents.csv');
    Split(rows[0], f);
    siteCol := f.IndexOf('site');
    dateCol := f.IndexOf('date');
    sevCol := f.IndexOf('severity');
    if (siteCol < 0) or (dateCol < 0) or (sevCol < 0) then
    begin
      writeln(StdErr, 'incidents.csv needs site, date and severity columns');
      Halt(1);
    end;
    for i := 1 to rows.Count - 1 do
    begin
      if Trim(rows[i]) = '' then Continue;
      Split(rows[i], f);
      y := StrToInt(Copy(f[dateCol], 1, 4));
      d := FindDepot(f[siteCol]);
      if d < 0 then Continue;
      if (y < yearFrom) or (y > yearTo) then Continue;
      Inc(depots[d].logged);
      if f[sevCol] = 'severe' then Inc(depots[d].severe);
    end;
  finally
    rows.Free;
    f.Free;
  end;
end;

{ A merged depot's row carries its hours and, up to the merge, its incidents; from the merge
  they are under the survivor's id. A merged depot can itself have been merged on again, so
  the survivor named on a row is not always the one still standing: follow merged_into to
  the depot nobody else's row names in turn, and fold this row's own hours and incidents
  there directly, not into whichever depot happens to sit between the two in the register.
  Every row's figures are read once, from the row itself, and added to that end point once,
  so it does not matter what order the rows come in or how many hops a chain runs. A
  merged_into cycle would mean the register is broken (nobody is left standing to fold into),
  so a row like that is left out of everyone's total rather than guessed at. }
procedure FoldMerged;
var
  i, j, n, hops: Integer;
begin
  for i := 0 to High(depots) do
    if depots[i].mergedInto <> '' then
    begin
      j := i;
      hops := 0;
      while (depots[j].mergedInto <> '') and (hops <= Length(depots)) do
      begin
        j := FindDepot(depots[j].mergedInto);
        if j < 0 then Break;
        Inc(hops);
      end;
      if (j < 0) or (j = i) or (depots[j].mergedInto <> '') then Continue;
      depots[j].hours := depots[j].hours + depots[i].hours;
      depots[j].severe := depots[j].severe + depots[i].severe;
      depots[j].logged := depots[j].logged + depots[i].logged;
    end;
  n := 0;
  for i := 0 to High(depots) do
    if depots[i].mergedInto = '' then
    begin
      depots[n] := depots[i];
      Inc(n);
    end;
  SetLength(depots, n);
end;

{ highest score first, ties broken by depot id so the list is the same on every run }
procedure SortByScore;
var
  i, j: Integer;
  t: TDepot;
begin
  for i := 1 to High(depots) do
  begin
    t := depots[i];
    j := i - 1;
    while (j >= 0) and ((depots[j].score < t.score) or
          ((depots[j].score = t.score) and (depots[j].id > t.id))) do
    begin
      depots[j + 1] := depots[j];
      Dec(j);
    end;
    depots[j + 1] := t;
  end;
end;

procedure WriteReport;
var
  o: TextFile;
  i: Integer;
begin
  AssignFile(o, outPath);
  Rewrite(o);
  write(o, '{"depots": [');
  for i := 0 to listSize - 1 do
  begin
    if i > 0 then write(o, ', ');
    write(o, '"', depots[i].id, '"');
  end;
  writeln(o, ']}');
  CloseFile(o);
end;

var
  policy: string;
  i: Integer;
begin
  if ParamCount <> 2 then
  begin
    writeln(StdErr, 'usage: watch <data-dir> <output-json>');
    Halt(2);
  end;
  dataDir := ParamStr(1);
  outPath := ParamStr(2);
  DefaultFormatSettings.DecimalSeparator := '.';

  policy := ReadWhole(dataDir + '/policy.json');
  listSize := JsonInt(policy, 'list_size', 1);
  yearFrom := JsonInt(policy, 'log_years', 1);
  yearTo := JsonInt(policy, 'log_years', 2);

  LoadDepots;
  LoadIncidents;
  FoldMerged;
  for i := 0 to High(depots) do
    depots[i].score := depots[i].severe / depots[i].hours;
  SortByScore;
  if listSize > Length(depots) then listSize := Length(depots);
  WriteReport;
end.

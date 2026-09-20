{ Programme list for the depot safety programme: which depots get the intervention.

  The league table in the memo ranks depots by logged incidents per hour worked, and most of
  what it ranks is how keen a depot's staff are to log a minor incident, which varies from
  almost never to almost always. A severe incident is logged whatever the depot's habits are,
  the insurer sees every one of them, so the count of severe incidents per hour worked is
  the one figure in the log that measures the depot and not its paperwork. The list is the
  depots with the highest severe rate over the logged years, as many as the policy asks for.

  A depot's rate does not move from one year to the next, so the severe rate over the logged
  years is the rate it will be running at in the programme year. The list is held to a rate
  against the whole network over the hours the listed depots work in that year, so the ranking
  is checked against that bar on the register's budgeted hours before it is written out, and
  on an export where the highest rates would not clear it the strongest list of that size is
  taken instead.

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
  SysUtils, Classes, fpjson, jsonparser;

type
  TDepot = record
    id: string;
    mergedInto: string; { blank, or the id of the depot this one was folded into }
    hours: Int64;       { hours worked over the log years, payroll and agency together }
    next: Int64;        { hours budgeted for the programme year, the same two columns }
    severe: Int64;      { severe incidents over the log years }
    logged: Int64;      { every logged incident, for reference }
    rate: Double;       { severe incidents per hour worked }
    score: Double;      { what the list is sorted on }
  end;

var
  depots: array of TDepot;
  dataDir, outPath: string;
  listSize, yearFrom, yearTo, progYear: Integer;
  rateBar: Double;
  exactRate: Boolean = True;  { the ranking sort compares rates exactly }

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

{ the policy is JSON, so it is decoded as JSON rather than searched as text: spacing,
  key order and string escapes are left to the parser, not to us }
procedure ReadPolicy(const path: string; out places, firstYear, lastYear, progYear: Integer;
  out bar: Double);
var
  root: TJSONData;
  o: TJSONObject;
  years: TJSONArray;
begin
  root := nil;
  try
    root := GetJSON(ReadWhole(path));
    if not (root is TJSONObject) then raise Exception.Create('not a JSON object');
    o := TJSONObject(root);
    if o.Find('list_size', jtNumber) = nil then raise Exception.Create('no list_size');
    places := o.Integers['list_size'];
    years := o.Get('log_years', TJSONArray(nil));
    if (years = nil) or (years.Count <> 2) then raise Exception.Create('log_years is not [first, last]');
    firstYear := years.Integers[0];
    lastYear := years.Integers[1];
    { the programme year and the bar the list is held to: the year after the log and no bar at
      all if the policy leaves either out, which leaves the ranking to stand as it is }
    progYear := lastYear + 1;
    if o.Find('programme_year', jtNumber) <> nil then progYear := o.Integers['programme_year'];
    bar := 0;
    if o.Find('minimum_rate_ratio', jtNumber) <> nil then bar := o.Floats['minimum_rate_ratio'];
  except
    on E: Exception do
    begin
      writeln(StdErr, 'policy.json: ', E.Message);
      Halt(1);
    end;
  end;
  root.Free;
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
  hoursCol, nextCol: array of Integer;
begin
  rows := TStringList.Create;
  f := TStringList.Create;
  try
    rows.LoadFromFile(dataDir + '/depots.csv');
    Split(rows[0], f);
    mergedCol := f.IndexOf('merged_into');
    SetLength(hoursCol, 0);
    SetLength(nextCol, 0);
    { every hours column for a log year counts, payroll (labour_hours_) and agency (agency_hours_),
      and the pair for the programme year is kept apart: those are the hours the list's rate is
      weighted by. Columns are found by the year in the name, so a register that carries a longer
      or a shorter log reads the same way. }
    for c := 0 to f.Count - 1 do
      if (Pos('labour_hours_', f[c]) = 1) or (Pos('agency_hours_', f[c]) = 1) then
      begin
        y := StrToInt(Copy(f[c], Length('labour_hours_') + 1, 8));
        if (y >= yearFrom) and (y <= yearTo) then
        begin
          SetLength(hoursCol, Length(hoursCol) + 1);
          hoursCol[High(hoursCol)] := c;
        end
        else if y = progYear then
        begin
          SetLength(nextCol, Length(nextCol) + 1);
          nextCol[High(nextCol)] := c;
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
        depots[n].hours := depots[n].hours + StrToInt64(Trim(f[hoursCol[c]]));
      depots[n].next := 0;
      for c := 0 to High(nextCol) do
        depots[n].next := depots[n].next + StrToInt64(Trim(f[nextCol[c]]));
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
  the depot the injured person is on the books of. The log is the big file in the export and
  nothing here needs more than the row in hand, so it is read a line at a time rather than held
  in memory. Columns are found by name. }
procedure LoadIncidents;
var
  fh: TextFile;
  f: TStringList;
  line: string;
  d, siteCol, sevCol: Integer;
begin
  f := TStringList.Create;
  AssignFile(fh, dataDir + '/incidents.csv');
  Reset(fh);
  try
    if Eof(fh) then
    begin
      writeln(StdErr, 'incidents.csv is empty');
      Halt(1);
    end;
    ReadLn(fh, line);
    Split(line, f);
    siteCol := f.IndexOf('site');
    sevCol := f.IndexOf('severity');
    if (siteCol < 0) or (sevCol < 0) then
    begin
      writeln(StdErr, 'incidents.csv needs site and severity columns');
      Halt(1);
    end;
    while not Eof(fh) do
    begin
      ReadLn(fh, line);
      if Trim(line) = '' then Continue;
      Split(line, f);
      d := FindDepot(f[siteCol]);
      if d < 0 then Continue;
      Inc(depots[d].logged);
      if f[sevCol] = 'severe' then Inc(depots[d].severe);
    end;
  finally
    CloseFile(fh);
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
      depots[j].next := depots[j].next + depots[i].next;
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

{ which of two rates is the higher, each given as a whole count of incidents over a whole
  number of hours, worked out exactly and with no product in it that could run past Int64:
  compare the whole part of the two rates, and while those agree compare what is left over
  by turning both remainders up the other way, which swaps which of the two is the larger.
  A depot with no hours on the register is read the way it always was read here: with
  incidents and no hours it comes above a depot that has hours, and two of them are level.
  1 when a is the higher rate, -1 when b is, 0 when the two are exactly equal. }
function CmpRate(an, ad, bn, bd: Int64): Integer;
var
  qa, qb, ra, rb: Int64;
  flip: Boolean;
begin
  if (ad <= 0) and (bd <= 0) then Exit(0);
  if ad <= 0 then
  begin
    if an > 0 then Exit(1);
    Exit(0);
  end;
  if bd <= 0 then
  begin
    if bn > 0 then Exit(-1);
    Exit(0);
  end;
  flip := False;
  Result := 0;
  while True do
  begin
    qa := an div ad;
    qb := bn div bd;
    if qa <> qb then
    begin
      if qa > qb then Result := 1 else Result := -1;
      Break;
    end;
    ra := an mod ad;
    rb := bn mod bd;
    if (ra = 0) and (rb = 0) then Break;
    if ra = 0 then
    begin
      Result := -1;
      Break;
    end;
    if rb = 0 then
    begin
      Result := 1;
      Break;
    end;
    an := ad; ad := ra;
    bn := bd; bd := rb;
    flip := not flip;
  end;
  if flip then Result := -Result;
end;

{ a goes before b: while the ranking is the severe rate, two depots are compared as a whole
  severe count over whole hours, so two depots on exactly the same rate come out level
  however large the hours are and the id decides between them; the bar climb ranks on a
  weighted score, which is a real number, and compares that. }
function Ahead(const a, b: TDepot): Boolean;
var
  c: Integer;
begin
  if exactRate then
  begin
    c := CmpRate(a.severe, a.hours, b.severe, b.hours);
    if c <> 0 then Exit(c > 0);
  end
  else if a.score <> b.score then
    Exit(a.score > b.score);
  Result := a.id < b.id;
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
    while (j >= 0) and Ahead(t, depots[j]) do
    begin
      depots[j + 1] := depots[j];
      Dec(j);
    end;
    depots[j + 1] := t;
  end;
end;

{ the rate the first count depots run at over the programme year, their incidents against
  their hours, each depot's rate read off the log and its hours off the register }
function ListRate(count: Integer): Double;
var
  i: Integer;
  ev, hv: Double;
begin
  ev := 0;
  hv := 0;
  for i := 0 to count - 1 do
  begin
    ev := ev + depots[i].rate * depots[i].next;
    hv := hv + depots[i].next;
  end;
  if hv <= 0 then Exit(0);
  Result := ev / hv;
end;

{ The places go to the worst depots, but the list is held to a rate against the whole network
  and that rate is over the hours the listed depots work, so the highest rates are not always
  the strongest list: one big depot on a middling rate carries enough hours to pull the list
  under the bar while a smaller one just behind it would leave it clear. Where the ranking
  already clears the bar this changes nothing. Where it does not, the best list of this size
  is found: for any rate L the list that maximises hours * (rate - L) is the best candidate
  against L, and taking that list's own rate as the next L climbs to the strongest list of
  that size in a few passes. }
procedure ClearTheBar;
var
  i, pass: Integer;
  network, lam, better: Double;
begin
  network := ListRate(Length(depots));
  if (network <= 0) or (rateBar <= 0) then Exit;
  exactRate := False;
  lam := ListRate(listSize);
  pass := 0;
  while (ListRate(listSize) < rateBar * network) and (pass < 20) do
  begin
    for i := 0 to High(depots) do
      depots[i].score := depots[i].next * (depots[i].rate - lam);
    SortByScore;
    better := ListRate(listSize);
    if better <= lam then Break;
    lam := better;
    Inc(pass);
  end;
end;

{ ids come out of the CSV, so quote them for JSON: escape the two structural
  characters and the control range rather than trust the field to be clean }
function JsonEscape(const s: string): string;
var
  i: Integer;
  c: Char;
begin
  Result := '';
  for i := 1 to Length(s) do
  begin
    c := s[i];
    case c of
      '"': Result := Result + '\"';
      '\': Result := Result + '\\';
      #8:  Result := Result + '\b';
      #9:  Result := Result + '\t';
      #10: Result := Result + '\n';
      #12: Result := Result + '\f';
      #13: Result := Result + '\r';
    else
      if c < #32 then
        Result := Result + '\u' + LowerCase(IntToHex(Ord(c), 4))
      else
        Result := Result + c;
    end;
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
    write(o, '"', JsonEscape(depots[i].id), '"');
  end;
  writeln(o, ']}');
  CloseFile(o);
end;

var
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

  ReadPolicy(dataDir + '/policy.json', listSize, yearFrom, yearTo, progYear, rateBar);

  LoadDepots;
  LoadIncidents;
  FoldMerged;
  for i := 0 to High(depots) do
  begin
    if depots[i].hours > 0 then depots[i].rate := depots[i].severe / depots[i].hours
    else depots[i].rate := 0;
    depots[i].score := depots[i].rate;
  end;
  SortByScore;
  if listSize > Length(depots) then listSize := Length(depots);
  ClearTheBar;
  WriteReport;
end.

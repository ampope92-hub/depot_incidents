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
  { An hours total, kept in two halves so that adding up a register's columns is exact whatever
    the columns hold. The top half carries the sign. }
  TWide = record
    hi: Int64;
    lo: QWord;
  end;

  TDepot = record
    id: string;
    mergedInto: string; { blank, or the id of the depot this one was folded into }
    hours: TWide;       { hours worked over the log years, payroll and agency together }
    next: TWide;        { hours budgeted for the programme year, the same two columns }
    severe: Int64;      { severe incidents over the log years }
    logged: Int64;      { every logged incident, for reference }
    rate: Double;       { severe incidents per hour worked }
    score: Double;      { what the list is sorted on }
  end;

var
  depots: array of TDepot;
  depotSlot: array of Integer; { a slot table over depots, -1 where a slot is free }
  slotMask: Int64;             { the slot table is a power of two long, so this masks an id into it }
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

{ Hours are whole numbers and they are added up exactly. A single column holds a whole number
  the size of an Int64, and a register can carry a great many of them, so the running total is
  kept in two halves rather than one: the bottom half takes the addition, its carry goes into
  the top half, and the pair is read as one number. The two halves reach past any total this
  program can be given. The loader indexes rows and columns with an Integer, so a register has
  at most High(Integer) rows with at most High(Integer) hours columns each, and each column is
  an Int64, which puts the largest total the loader can form under 2^125, well inside the pair.
  The carry out of the top half is still tested, because ranking a depot on a total that had
  wrapped round would be a wrong answer rather than a visible one; the test is written out
  rather than left to a compiler switch so it holds whatever the build line is. }
function Wide(v: Int64): TWide;
begin
  Result.lo := QWord(v);
  if v < 0 then Result.hi := -1 else Result.hi := 0;
end;

function WideAdd(const a, b: TWide; const where, id: string): TWide;
begin
  Result.lo := a.lo + b.lo;
  Result.hi := a.hi + b.hi;
  if Result.lo < a.lo then Result.hi := Result.hi + 1;
  if ((a.hi < 0) = (b.hi < 0)) and ((Result.hi < 0) <> (a.hi < 0)) then
  begin
    writeln(StdErr, where, ': the figures for ', id, ' add up past what a whole number holds here');
    Halt(1);
  end;
end;

{ -1, 0 or 1 as the total is negative, nothing or positive }
function WideSign(const v: TWide): Integer;
begin
  if v.hi < 0 then Exit(-1);
  if (v.hi = 0) and (v.lo = 0) then Exit(0);
  Result := 1;
end;

{ the pair as a real number, for the weighted score and the bar, which are real numbers anyway }
function WideFloat(const v: TWide): Double;
begin
  Result := v.hi * 18446744073709551616.0
            + (v.lo shr 32) * 4294967296.0 + (v.lo and $FFFFFFFF);
end;

{ the id turned into a number, taken modulo a prime at every step so nothing in it runs past
  an Int64 and the value is the same on any build }
function IdHash(const s: string): Int64;
var
  i: Integer;
begin
  Result := 0;
  for i := 1 to Length(s) do
    Result := (Result * 131 + Ord(s[i])) mod 1000000007;
end;

{ A depot is looked up by id once for every row of the log, and the log is the big file in the
  export, so the register goes into a slot table rather than being walked row by row for each
  lookup. The id picks the slot, a taken slot moves on to the next one, and a lookup follows
  the same path, so the first row written under an id is the one a lookup finds, as it was when
  the register was walked from the top. The table is twice the length of the register, so a
  lookup takes a step or two whatever size the register is. }
procedure BuildIndex;
var
  i, slot: Integer;
  cap: Int64;
begin
  cap := 16;
  while cap < 2 * Int64(Length(depots)) do cap := cap * 2;
  SetLength(depotSlot, cap);
  slotMask := cap - 1;
  for i := 0 to High(depotSlot) do depotSlot[i] := -1;
  for i := 0 to High(depots) do
  begin
    slot := Integer(IdHash(depots[i].id) and slotMask);
    while depotSlot[slot] >= 0 do slot := Integer((Int64(slot) + 1) and slotMask);
    depotSlot[slot] := i;
  end;
end;

function FindDepot(const id: string): Integer;
var
  slot: Integer;
begin
  if Length(depotSlot) = 0 then Exit(-1);
  slot := Integer(IdHash(id) and slotMask);
  while depotSlot[slot] >= 0 do
  begin
    if depots[depotSlot[slot]].id = id then Exit(depotSlot[slot]);
    slot := Integer((Int64(slot) + 1) and slotMask);
  end;
  Result := -1;
end;

procedure Split(const line: string; fields: TStringList);
var
  row: string;
begin
  { a file written on a Windows machine ends its rows with a carriage return: drop it so the
    last column on the row reads like the rest }
  row := line;
  if (row <> '') and (row[Length(row)] = #13) then SetLength(row, Length(row) - 1);
  fields.Clear;
  fields.StrictDelimiter := True;
  fields.Delimiter := ',';
  fields.DelimitedText := row;
end;

{ The register is read a row at a time too. Nothing here needs more than the row in hand, and
  a register that carries a lot of text in columns this job never reads would otherwise be held
  in memory whole on top of the depots taken out of it. }
procedure LoadDepots;
var
  fh: TextFile;
  f: TStringList;
  line: string;
  c, y, n, mergedCol: Integer;
  hoursCol, nextCol: array of Integer;
begin
  f := TStringList.Create;
  AssignFile(fh, dataDir + '/depots.csv');
  Reset(fh);
  try
    if Eof(fh) then
    begin
      writeln(StdErr, 'depots.csv is empty');
      Halt(1);
    end;
    ReadLn(fh, line);
    Split(line, f);
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
    SetLength(depots, 0);
    while not Eof(fh) do
    begin
      ReadLn(fh, line);
      if Trim(line) = '' then Continue;
      Split(line, f);
      { room for the row in hand, doubling rather than one row at a time }
      if n = Length(depots) then
        if n = 0 then SetLength(depots, 64) else SetLength(depots, n * 2);
      depots[n].id := f[0];
      if mergedCol >= 0 then depots[n].mergedInto := Trim(f[mergedCol]) else depots[n].mergedInto := '';
      depots[n].hours := Wide(0);
      for c := 0 to High(hoursCol) do
        depots[n].hours := WideAdd(depots[n].hours, Wide(StrToInt64(Trim(f[hoursCol[c]]))), 'depots.csv', depots[n].id);
      depots[n].next := Wide(0);
      for c := 0 to High(nextCol) do
        depots[n].next := WideAdd(depots[n].next, Wide(StrToInt64(Trim(f[nextCol[c]]))), 'depots.csv', depots[n].id);
      depots[n].severe := 0;
      depots[n].logged := 0;
      Inc(n);
    end;
    SetLength(depots, n);
  finally
    CloseFile(fh);
    f.Free;
  end;
  BuildIndex;
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
      depots[j].hours := WideAdd(depots[j].hours, depots[i].hours, 'depots.csv', depots[j].id);
      depots[j].next := WideAdd(depots[j].next, depots[i].next, 'depots.csv', depots[j].id);
      { the counts need no such care: every one of them is a row of the log counted once, so
        the two being added here have already been counted apart from each other and their
        total is still at most the number of rows the log has }
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
  { the slot table describes the register as it was read, which the fold has just changed, and
    nothing looks a depot up again }
  SetLength(depotSlot, 0);
end;

{ one half of the register times the other, in quarters, so no step of it needs more room
  than the machine has }
procedure Mul64(a, b: QWord; out hi, lo: QWord);
var
  a0, a1, b0, b1, p00, p01, p10, mid: QWord;
begin
  a0 := a and $FFFFFFFF; a1 := a shr 32;
  b0 := b and $FFFFFFFF; b1 := b shr 32;
  p00 := a0 * b0;
  p01 := a0 * b1;
  p10 := a1 * b0;
  mid := (p00 shr 32) + (p01 and $FFFFFFFF) + (p10 and $FFFFFFFF);
  lo := (p00 and $FFFFFFFF) or (mid shl 32);
  hi := a1 * b1 + (p01 shr 32) + (p10 shr 32) + (mid shr 32);
end;

{ a count of incidents times an hours total, in three halves. Both are nothing or more, the
  count because each one of them is a row of the log and the hours because a rate is only
  compared this way when both depots have hours on the register. }
procedure MulCount(const h: TWide; c: Int64; out r2, r1, r0: QWord);
var
  m1, t1, t0: QWord;
begin
  Mul64(h.lo, QWord(c), m1, r0);
  Mul64(QWord(h.hi), QWord(c), t1, t0);
  r1 := m1 + t0;
  r2 := t1;
  if r1 < m1 then r2 := r2 + 1;
end;

{ which of two rates is the higher, each given as a whole count of incidents over a whole
  number of hours, worked out exactly: the count on each side is taken against the other
  side's hours, which puts the two rates over the same hours without dividing either, and
  the two products are compared a half at a time. A depot with no hours on the register is
  read the way it always was read here: with incidents and no hours it comes above a depot
  that has hours, and two of them are level.
  1 when a is the higher rate, -1 when b is, 0 when the two are exactly equal. }
function CmpRate(an: Int64; const ad: TWide; bn: Int64; const bd: TWide): Integer;
var
  a2, a1, a0, b2, b1, b0: QWord;
begin
  if (WideSign(ad) <= 0) and (WideSign(bd) <= 0) then Exit(0);
  if WideSign(ad) <= 0 then
  begin
    if an > 0 then Exit(1);
    Exit(0);
  end;
  if WideSign(bd) <= 0 then
  begin
    if bn > 0 then Exit(-1);
    Exit(0);
  end;
  MulCount(bd, an, a2, a1, a0);
  MulCount(ad, bn, b2, b1, b0);
  if a2 <> b2 then
  begin
    if a2 > b2 then Exit(1);
    Exit(-1);
  end;
  if a1 <> b1 then
  begin
    if a1 > b1 then Exit(1);
    Exit(-1);
  end;
  if a0 <> b0 then
  begin
    if a0 > b0 then Exit(1);
    Exit(-1);
  end;
  Result := 0;
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

{ Highest score first, ties broken by depot id so the list is the same on every run. No two
  depots left standing carry the same id, so Ahead puts any two rows one way round and the
  sorted register is one order however the sort reaches it. It is a heap sort rather than an
  insertion pass: an insertion pass moves every row it steps over, so a register that arrives
  in the wrong order costs a move for every pair of rows in it. }
procedure SiftDown(root, last: Integer);
var
  child: Integer;
  t: TDepot;
begin
  while root * 2 + 1 <= last do
  begin
    child := root * 2 + 1;
    { of the two children take the one that belongs further down the list }
    if (child + 1 <= last) and Ahead(depots[child], depots[child + 1]) then Inc(child);
    if not Ahead(depots[root], depots[child]) then Exit;
    t := depots[root]; depots[root] := depots[child]; depots[child] := t;
    root := child;
  end;
end;

procedure SortByScore;
var
  i, last: Integer;
  t: TDepot;
begin
  last := High(depots);
  if last < 1 then Exit;
  for i := (last - 1) div 2 downto 0 do SiftDown(i, last);
  for i := last downto 1 do
  begin
    t := depots[0]; depots[0] := depots[i]; depots[i] := t;
    SiftDown(0, i - 1);
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
    ev := ev + depots[i].rate * WideFloat(depots[i].next);
    hv := hv + WideFloat(depots[i].next);
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
      depots[i].score := WideFloat(depots[i].next) * (depots[i].rate - lam);
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
    if WideSign(depots[i].hours) > 0 then depots[i].rate := depots[i].severe / WideFloat(depots[i].hours)
    else depots[i].rate := 0;
    depots[i].score := depots[i].rate;
  end;
  SortByScore;
  if listSize > Length(depots) then listSize := Length(depots);
  ClearTheBar;
  WriteReport;
end.

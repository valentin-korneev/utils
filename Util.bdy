prompt create or replace package body Util

create or replace package body Util
as

gcRadix36Alphabet               constant varchar2(36) := '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ';
gcRadix26Alphabet               constant varchar2(26) := 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';

NUM_FORMAT                      constant varchar2(99) := rpad(lpad('0', 20, '9')||'D', 40, '9');
NLS_NUM_CHAR                    constant varchar2(30) := 'nls_numeric_characters='', ''';

-- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

---------
function DBCharset return varchar2
is
begin
  return regexp_replace(sys_context('USERENV', 'LANGUAGE'), '^([^.]+\.)(.*)', '\2');
end DBCharset;

---------
function IsMultiByteDB return boolean
is
begin
  return lengthb('Ё') > 1;
end IsMultiByteDB;

---------
function FixCharset(aStr varchar2) return varchar2
is
  fRes varchar2(32767) := aStr;
begin
  if IsMultiByteDB then
    fRes := case
              when utl_i18n.raw_to_char(utl_i18n.string_to_raw(aStr, Util.DBCharset),'utf8') <> aStr
                then utl_i18n.raw_to_char(utl_i18n.string_to_raw(aStr, Util.DBCharset),'cl8mswin1251')
                else aStr
            end;
  end if;
  return fRes;
end FixCharset;

---------
function TStrs2TInts(aStrs TStrs) return TInts
is
  fInts TInts;
begin
  if aStrs is not null then
    fInts := TInts();
    fInts.extend(aStrs.count);
    for i in 1 .. aStrs.count loop
      fInts(i) := aStrs(i);
    end loop;
  end if;
  return fInts;
end TStrs2TInts;

---------
function TInts2TStrs(aInts TInts) return TStrs
is
  fStrs TStrs;
begin
  if aInts is not null then
    fStrs := TStrs();
    fStrs.extend(aInts.count);
    for i in 1 .. aInts.count loop
      fStrs(i) := aInts(i);
    end loop;
  end if;
  return fStrs;
end TInts2TStrs;

---------
function TInts2TpIntTable(aInts TInts) return tp_int_table
is
  fInts tp_int_table := tp_int_table();
begin
  fInts.extend(aInts.count);
  for i in 1 .. aInts.count loop
    fInts(i) := aInts(i);
  end loop;
  return fInts;
end TInts2TpIntTable;

---------
function TpIntTable2TInts(aInts tp_int_table) return TInts
is
  fInts Util.TInts := TInts();
begin
  fInts.extend(aInts.count);
  for i in 1 .. aInts.count loop
    fInts(i) := aInts(i);
  end loop;
  return fInts;
end TpIntTable2TInts;

---------
function Reverse(aStrs TStrs) return TStrs
is
  fStrs TStrs;
begin
  if aStrs is not null then
    fStrs := TStrs();
    fStrs.extend(aStrs.count);
    for i in 1 .. aStrs.count loop
      fStrs(i) := aStrs(aStrs.count - i + 1);
    end loop;
  end if;
  return fStrs;
end Reverse;

---------
function IndexOf(aStrs TStrs, aValue varchar2) return pls_integer
is
  i pls_integer := aStrs.first;
begin
  while i is not null and aStrs(i) <> aValue loop
    i := aStrs.next(i);
  end loop;
  return i;
end IndexOf;

---------
function IndexOf(aInts TInts, aValue int) return pls_integer
is
  i pls_integer := aInts.first;
begin
  while i is not null and aInts(i) <> aValue loop
    i := aInts.next(i);
  end loop;
  return i;
end IndexOf;

---------
function IndexOf(aStrArr TStrArr, aValue varchar2) return pls_integer
is
  i pls_integer := aStrArr.first;
begin
  while i is not null and aStrArr(i) <> aValue loop
    i := aStrArr.next(i);
  end loop;
  return i;
end IndexOf;

---------
function IndexOf(aIntArr TIntArr, aValue int) return pls_integer
is
  i pls_integer := aIntArr.first;
begin
  while i is not null and aIntArr(i) <> aValue loop
    i := aIntArr.next(i);
  end loop;
  return i;
end IndexOf;


---------
function Occurences(SubStr varchar2, Str varchar2) return pls_integer
is
begin
  return case
           when SubStr is null or Str is null
             then 0
           else (length(Str) - nvl(length(replace(Str, SubStr)), 0)) / length(SubStr)
         end;
end Occurences;

---------
function SubName(Name varchar2, Ind pls_integer, Separator varchar2 := '|') return varchar2
is
  S varchar2(32767) := Separator || Name || Separator;
  I1 pls_integer := nullif(instr(S, Separator, 1, Ind), 0) + length(Separator);
  I2 pls_integer := nullif(instr(S, Separator, I1), 0);
begin
  return substr(S, I1 , I2 - I1);
end SubName;

---------
function SubNameCount(Name varchar2, Separator varchar2 := '|') return pls_integer
is
begin
  return case when Name is null then 0 else Occurences(Separator, Name) + 1 end;
end SubNameCount;

---------
function SubNameIndex(SubStr varchar2, Name varchar2, Separator varchar2 := '|') return pls_integer
is
begin
  for i in 1 .. SubNameCount(Name, Separator) loop
    if SubStr = SubName(Name, i, Separator) then
      return i;
    end if;
  end loop;
  return 0;
end SubNameIndex;

---------
function SubNameExists(SubStr varchar2, Name varchar2, Separator varchar2 := '|') return boolean
is
begin
  return SubNameIndex(SubStr, Name, Separator) > 0;
end SubNameExists;

---------
function SubNames2TStrs(Name varchar2, Separator varchar2 := '|') return TStrs
is
  fResult TStrs := TStrs();
begin
  for i in 1 .. SubNameCount(Name, Separator) loop
    fResult.extend;
    fResult(i) := SubName(Name, i, Separator);
  end loop;
  return fResult;
end SubNames2TStrs;

---------
function TStrs2SubNames(aStrs TStrs,   Separator varchar2 := '|') return varchar2
is
  fResult varchar2(32767);
begin
  if aStrs is not null then
    for i in 1 .. aStrs.count loop
      fResult := fResult || case when i > 1 then Separator end || aStrs(i);
    end loop;
  end if;
  return fResult;
end TStrs2SubNames;

---------
function SubNameReverse(Name varchar2, Separator varchar2 := '|') return varchar2
is
begin
  return TStrs2SubNames(Reverse(SubNames2TStrs(Name, Separator)), Separator);
end SubNameReverse;

---------
function SubNames2TpVarchar4000Table(Name varchar2, Separator varchar2 := '|') return tp_varchar2_4000_table
is
  fResult tp_varchar2_4000_table := tp_varchar2_4000_table();
begin
  for i in 1 .. SubNameCount(Name, Separator) loop
    fResult.extend;
    fResult(i) := SubName(Name, i, Separator);
  end loop;
  return fResult;
end SubNames2TpVarchar4000Table;

---------
function TStrs2TpVarchar4000Table(aStrs TStrs) return tp_varchar2_4000_table
is
  fResult tp_varchar2_4000_table;
begin
  if aStrs is not null then
    fResult := tp_varchar2_4000_table();
    fResult.extend(aStrs.count);
    for i in 1 .. aStrs.count loop
      fResult(i) := aStrs(i);
    end loop;
  end if;
  return fResult;
end TStrs2TpVarchar4000Table;

---------
function TpVarchar4000Table2TStrs(aStrs tp_varchar2_4000_table) return TStrs
is
  fResult TStrs;
begin
  if aStrs is not null then
    fResult := TStrs();
    fResult.extend(aStrs.count);
    for i in 1 .. aStrs.count loop
      fResult(i) := aStrs(i);
    end loop;
  end if;
  return fResult;
end TpVarchar4000Table2TStrs;

---------
function TStrs2TStrs2D(aStrs TStrs, aSubItemCount pls_integer := 2) return TStrs2D
is
  fResult TStrs2D;
begin
  if aStrs is not null then
    fResult := TStrs2D();
    fResult.extend(trunc(aStrs.count / aSubItemCount));
    for i in 1 .. fResult.count loop
      fResult(i) := TStrs();
      fResult(i).extend(aSubItemCount);
      for j in 1 .. aSubItemCount loop
        fResult(i)(j) := aStrs((i - 1) * aSubItemCount + j);
      end loop;
    end loop;
  end if;
  return fResult;
end TStrs2TStrs2D;

---------
procedure TStrArr2Clob(aStrArr TStrArr, aClob in out nocopy clob, aAddCR boolean := true)
is
  cNewLine constant varchar2(2) := case when aAddCR then chr(13) end || chr(10);
  fBuf varchar2(32767);
  fLen int;
  fIdx int;
  --
  procedure FlushBuf
  is
  begin
    aClob := aClob || fBuf;
    fBuf := null;
  end;
begin
  if aClob is null then
    dbms_lob.createtemporary(aClob, true);
  end if;

  fIdx := aStrArr.first;
  while fIdx is not null loop
    fLen := nvl(lengthb(aStrArr(fIdx)), 0);
    if fLen > 32765 then
      FlushBuf;
      aClob := aClob || aStrArr(fIdx);
    else
      if lengthb(fBuf) + fLen > 32765 then
        FlushBuf;
      end if;
      fBuf := fBuf || aStrArr(fIdx);
    end if;
    fBuf := fBuf || cNewLine;
    fIdx := aStrArr.next(fIdx);
  end loop;
  FlushBuf;
end TStrArr2Clob;

---------
function TStrArr2Clob(aStrArr TStrArr, aAddCR boolean := true) return clob
is
  fResult clob;
begin
  TStrArr2Clob(aStrArr, fResult, aAddCR);
  return fResult;
end TStrArr2Clob;

---------
procedure Clob2TStrArr(aClob clob, aStrArr in out nocopy TStrArr)
is
  fStr          varchar2(32767);
  fSubName      varchar2(32767);
  fPartLength   int := 16000;
  fClobLength   int;
begin
  fClobLength := nvl(dbms_lob.getlength(aClob), 0);
  Util.CheckErr(fClobLength > 1073741824, '‘айл не может быть больше 1Gb');
  if fClobLength > 0 then
    aStrArr(1) := null;
    for i in 1 .. ceil(fClobLength / fPartLength) loop
      fStr := replace(dbms_lob.substr(aClob, fPartLength, (i - 1) * fPartLength + 1), chr(13));
      for j in 1..Util.SubNameCount(fStr, chr(10)) loop
        fSubName := Util.SubName(fStr, j, chr(10));
        if j = 1 then
          Util.CheckErr(nvl(lengthb(aStrArr(aStrArr.count)), 0) + nvl(lengthb(fSubName), 0) > 32767, '—трока не может быть больше 32767b');
          aStrArr(aStrArr.count) := aStrArr(aStrArr.count) || fSubName;
        else
          aStrArr(aStrArr.count + 1) := fSubName;
        end if;
      end loop;
    end loop;
    if aStrArr(aStrArr.last) is null then
      aStrArr.delete(aStrArr.last);
    end if;
  end if;
end Clob2TStrArr;

---------
function Clob2TStrArr(aClob clob) return TStrArr
is
  fResult TStrArr;
begin
  Clob2TStrArr(aClob, fResult);
  return fResult;
end Clob2TStrArr;

---------
function Clob2TpVarchar4000Table(aClob clob, aIgnoreNullLines varchar2 := 'Y') return tp_varchar2_4000_table
is
  fResult tp_varchar2_4000_table := tp_varchar2_4000_table();
  fStrArr TStrArr;
begin
  fStrArr := Clob2TStrArr(aClob);
  if fStrArr is not null then
    for i in 1 .. fStrArr.count loop
      if aIgnoreNullLines <> 'Y' or trim(fStrArr(i)) is not null then
        fResult.extend;
        fResult(fResult.count) := trim(fStrArr(i));
      end if;
    end loop;
  end if;
  return fResult;
end Clob2TpVarchar4000Table;

---------
function Clob2TpNumTable(aClob clob, aIgnoreNullLines varchar2 := 'Y', aIgnoreNumErr varchar2 := 'Y') return tp_num_table
is
  fResult tp_num_table := tp_num_table();
  fStrArr TStrArr;
begin
  fStrArr := Clob2TStrArr(aClob);
  if fStrArr is not null then
    for i in 1 .. fStrArr.count loop
      if aIgnoreNullLines <> 'Y' or trim(fStrArr(i)) is not null then
        fResult.extend;
        begin
          fResult(fResult.count) := regexp_replace(fStrArr(i), '[.,]', to_char(0, 'fmd'));
        exception
          when value_error then
            if aIgnoreNumErr <> 'Y' then
              raise;
            end if;
            fResult.trim;
        end;
      end if;
    end loop;
  end if;
  return fResult;
end Clob2TpNumTable;

---------
function Interval2Sec(aInterval dsinterval_unconstrained) return number
is
begin
  return extract(day    from (aInterval))*24*60*60
       + extract(hour   from (aInterval))   *60*60
       + extract(minute from (aInterval))      *60
       + extract(second from (aInterval))
  ;
end Interval2Sec;

---------
function Num2Str(aValue number) return varchar2
is
begin
  return case aValue when 0 then '0' else rtrim(rtrim(to_char(aValue, NUM_FORMAT, NLS_NUM_CHAR), '0'), ',') end;
end Num2Str;

---------
function Str2Num(aValue varchar2) return number
is
begin
  return to_number(aValue, NUM_FORMAT, NLS_NUM_CHAR);
exception
  when value_error then
    Util.RaiseErr('"%s" - неверное число', aValue);
end Str2Num;

---------
function DMY(aDate date) return varchar2
is
begin
  return to_char(aDate, 'dd.mm.yyyy');
end DMY;

---------
function DMYHMS(aDate date) return varchar2
is
begin
  return to_char(aDate, 'dd.mm.yyyy hh24:mi:ss');
end DMYHMS;

---------
function DMY2D(aString varchar2, aFormat varchar2) return date
is
begin
  return to_date(aString, aFormat);
exception
  when others then
    if sqlcode between -1899 and -1800 then                        -- date function errors
      Util.RaiseErr('"%s" - неверна€ дата', aString);
    else
      raise;
    end if;
end DMY2D;

---------
function DMY2Date(aString varchar2) return date
is
begin
  return DMY2D(aString, 'dd.mm.yyyy');
end DMY2Date;

---------
function DMYHMS2Date(aString varchar2) return date
is
begin
  return DMY2D(aString, 'dd.mm.yyyy hh24:mi:ss');
end DMYHMS2Date;

---------
function BOOL(aBoolean boolean) return varchar2
is
begin
  return case aBoolean when true then 'Y' when false then 'N' else '?' end;
end BOOL;

---------
function BOOL2Boolean(aBOOL varchar2) return boolean
is
begin
  if translate(aBOOL, '.YN?', '.') is not null then
    Util.RaiseErr('"%s" - неверное значение', aBOOL);
  end if;
  return case aBOOL when 'Y' then true when 'N' then false end;
end BOOL2Boolean;


---------
function NumberToHex(Value int, Digits int := null) return varchar2
is
  fRes varchar2(512) := to_char(Value, rpad('fm', 40, 'X'));
begin
  if length(fRes) < Digits then
    fRes := lpad(fRes, Digits, '0');
  end if;
  return fRes;
end NumberToHex;

---------
function Format(FormatStr varchar2, Args TStrs) return varchar2
is
  fFormatStr varchar2(32767) := replace(FormatStr, '\n', chr(10)); --!! работа с локальной переменной почему-то гораздо быстрее в 10g
  NextArgPos pls_integer;
  Res varchar2(32767);
  ArgIndex pls_integer := 0;
  Value varchar2(32767);
  CurrentPos pls_integer := 1;
  --
  pragma inline (GetArg, 'YES');
  function GetArg return varchar2
  is
  begin
    ArgIndex := ArgIndex + 1;
    return Args(ArgIndex);
  exception
    when no_data_found
      or subscript_beyond_count
      or collection_is_null
    then
      return null;
  end GetArg;
  --
  function Parse return boolean
  is
    StartPos pls_integer := CurrentPos;
    LeftAligned boolean := false;
    Width pls_integer;
    Precision pls_integer;
    FmtType char;
    Ch char := substr(fFormatStr, CurrentPos, 1);
    --
    pragma inline (NextChar, 'YES');
    procedure NextChar
    is
    begin
      CurrentPos := CurrentPos + 1;
      Ch := substr(fFormatStr, CurrentPos, 1);
    end NextChar;
    --
    function ReadInt return pls_integer
    is
      n pls_integer;
    begin
      while Ch between '0' and '9' loop
        n := nvl(n, 0) * 10 + to_number(Ch);
        NextChar;
      end loop;
      return n;
    end ReadInt;
    --
  begin
    if Ch = '-' then
      LeftAligned := true;
      NextChar;
    end if;
    Width := ReadInt;
    if Ch = '.' then
      NextChar;
      Precision := ReadInt;
    end if;
    FmtType := Ch;
    NextChar;
    if FmtType = 's' then
      Value := GetArg;
      if Precision is not null then
        Value := substr(Value, 1, Precision);
      end if;
    elsif FmtType in ('d', 'x') then
      Value := GetArg;
      declare
        n number;
      begin
        n := to_number(Value);
        if FmtType = 'd' then
          if Precision is not null then
            Value := to_char(n, 'fm' || rpad('0', Precision, '0'));
            if instr(Value, '#') > 0 then
              Value := Num2Str(n);
            end if;
          else
            Value := Num2Str(n);
          end if;
        else
          Value := NumberToHex(n, Precision);
        end if;
      exception
        when value_error then
          null;
      end;
    elsif FmtType = 'D' then
      Value := GetArg;
      declare
        d date;
      begin
        d := to_date(Value);
        Value := to_char
                 ( d
                 , case Width
                     when 2 then 'yy'
                     when 3 then 'yy'
                     when 4 then 'yyyy'
                     when 5 then 'mm.yy'
                     when 6 then 'mm.yy'
                     when 7 then 'mm.yyyy'
                     when 8 then 'dd.mm.yy'
                            else 'dd.mm.yyyy'
                   end
                 );
      exception
        when others then
          null;
      end;
    elsif FmtType = 'i' then
      Value := rtrim(regexp_replace(GetArg, '^([+]|(-))[0 :]*([1-9][0-9: ]*|0)((\.\d{' || nvl(least(Precision, 9), 3) || '})\d*|)$', '\2\3\5'), '.');
    else
      CurrentPos := StartPos;
      return false;
    end if;
    if Width is not null and length(Value) < Width then
      if LeftAligned then
        Value := rpad(Value, Width);
      else
        Value := lpad(Value, Width);
      end if;
    end if;
    return true;
  end Parse;
  --
begin
  loop
    NextArgPos := nvl(instr(fFormatStr, '%', CurrentPos), 0);
    exit when NextArgPos = 0;
    Res := Res || substr(fFormatStr, CurrentPos, NextArgPos - CurrentPos);
    CurrentPos := NextArgPos + 1;
    if Parse then
      Res := Res || Value;
    else
      Res := Res || '%';
    end if;
    --Res := Res || case when Parse then Value else '%' end; -- if быстрее :(
  end loop;
  return Res || substr(fFormatStr, CurrentPos);
end Format;

---------
procedure Format(aStr in out nocopy varchar2, aArgs TStrs)
is
begin
  aStr := Format(aStr, aArgs);
end Format;

---------
function Format(FormatStr varchar2, S1 varchar2,
  S2 varchar2 := '', S3 varchar2 := '', S4 varchar2 := '',
  S5 varchar2 := '', S6 varchar2 := '', S7 varchar2 := '',
  S8 varchar2 := '', S9 varchar2 := '', S10 varchar2 := ''
) return varchar2
is
begin
  return Format(FormatStr, TStrs(S1, S2, S3, S4, S5, S6, S7, S8, S9, S10));
end Format;

---------
procedure ReplaceMacros(aStr in out nocopy varchar2, aMacros TStrs)
is
begin
  if aMacros is not null then
    for i in 1 .. trunc(aMacros.count / 2) loop
      aStr := replace(aStr, aMacros(i*2-1), aMacros(i*2));
    end loop;
  end if;
end ReplaceMacros;

---------
function ReplaceMacros(aStr varchar2, aMacros TStrs) return varchar2
is
  fStr varchar2(32767) := aStr;
begin
  ReplaceMacros(fStr, aMacros);
  return fStr;
end ReplaceMacros;

---------
procedure ReplaceOptionalMacros(aStr in out nocopy varchar2, aMacros TStrs, aBracketChars varchar2 := '{}')
is
begin
  aStr := ReplaceOptionalMacros(aStr, aMacros, aBracketChars);
end ReplaceOptionalMacros;

---------
function ReplaceOptionalMacros(aStr varchar2, aMacros TStrs, aBracketChars varchar2 := '{}') return varchar2
is
  cReOptional constant varchar2(20) := '\' || substr(aBracketChars, 1, 1) || '[^' || substr(aBracketChars, 2, 1) || ']*\' || substr(aBracketChars, 2, 1);
  fEmptyMacros TStrs;
  fStr varchar2(32767) := aStr;
  fResult varchar2(32767);
  fOptional varchar2(32767);
  fPos pls_integer;
  --
  function ReplaceOrEmpty(aOptinal varchar2) return varchar2
  is
    fActual varchar2(32767) := ReplaceMacros(aOptinal, aMacros);
    fEmpty  varchar2(32767) := ReplaceMacros(aOptinal, fEmptyMacros);
  begin
    return case when fActual =  aOptinal /* no macros present */
                  or fActual <> fEmpty   /* any macros is not null */
                then fActual
           end;
  end ReplaceOrEmpty;
  --
begin
  if aMacros is not null then
    fEmptyMacros := aMacros;
    for i in 1 .. trunc(aMacros.count / 2) loop
      fEmptyMacros(i*2) := null;
    end loop;
    for i in 1 .. 100 loop
      fPos := regexp_instr(fStr, cReOptional);
      exit when nvl(fPos, 0) = 0;
      fOptional := regexp_substr(fStr, cReOptional);
      fResult := fResult
              || ReplaceMacros(substr(fStr, 1, fPos - 1), aMacros)
              || ReplaceOrEmpty(substr(fStr, fPos + 1, length(fOptional) - 2));
      fStr := substr(fStr, fPos + length(fOptional));
    end loop;
  end if;
  return fResult
      || ReplaceMacros(fStr, aMacros);
end ReplaceOptionalMacros;

---------
procedure ReplaceMacros(aStr in out nocopy clob, aMacros TStrs)
is
begin
  if aMacros is not null then
    for i in 1 .. trunc(aMacros.count / 2) loop
      aStr := replace(aStr, aMacros(i*2-1), aMacros(i*2));
    end loop;
  end if;
end ReplaceMacros;

---------
function ReplaceMacros(aStr clob, aMacros TStrs) return clob
is
  fStr clob := aStr;
begin
  ReplaceMacros(fStr, aMacros);
  return fStr;
end ReplaceMacros;

----------
procedure ReplaceMacros(aStr in out nocopy clob, aMacros tp_clob_table)
is
  procedure ReplaceClob(aClob in out clob, aOld varchar2, aNew clob)
  is
    fClob       clob;
    fClobLength int;
    fLength     int;
    fOldOffset  int;
    fOffset     int := 0;
  begin
    dbms_lob.createtemporary(fClob, true);
    fClobLength := dbms_lob.getlength(aClob);
    if fClobLength > 0 then
      loop
        fOldOffset := dbms_lob.instr(aClob, aOld, fOffset + 1);
        if fOldOffset = 0 then
          fLength := fClobLength - fOffset;
          exit when fLength = 0;
        else
          fLength := fOldOffset - fOffset - 1;
        end if;
        for i in 1..ceil(fLength / 8191) loop
          dbms_lob.append(fClob, dbms_lob.substr(aClob, least(8191, fLength), fOffset + 1 + (i - 1) * 8191));
          fLength := fLength - least(8191, fLength);
        end loop;
        exit when fOldOffset = 0;
        dbms_lob.append(fClob, aNew);
        fOffset := fOldOffset + length(aOld) - 1;
      end loop;
      aClob := fClob;
    end if;
  end ReplaceClob;
begin
  if aMacros is not null then
    for i in 1..trunc(aMacros.count / 2) loop
      ReplaceClob(aStr, aMacros(i * 2 - 1), nvl(aMacros(i * 2), empty_clob()));
    end loop;
  end if;
end ReplaceMacros;

----------
function ReplaceMacros(aStr clob, aMacros tp_clob_table) return clob
is
  fResult clob := aStr;
begin
  ReplaceMacros(fResult, aMacros);
  return fResult;
end ReplaceMacros;


/*--------- 9i
function BitAnd(aValue1 int, aValue2 int) return int
is
  fValue1 int := aValue1 - 2**31;
  fValue2 int := aValue2 - 2**31;
begin
  if aValue1 = 0 or aValue2 = 0 then
    return 0;
  else
    return Standard.BitAnd(fValue1, fValue2) + 2**31 * (1 - abs(sign(sign(fValue1) - sign(fValue2))));
  end if;
end BitAnd;
*/
---------
function BitAnd(aValue1 int, aValue2 int) return int
is
begin
  return Standard.bitand(aValue1, aValue2);
end BitAnd;

---------
procedure BitAnd(aValue1 in out nocopy int, aValue2 int)
is
begin
  aValue1 := BitAnd(nvl(aValue1, 0), aValue2);
end BitAnd;

---------
function BitOr(aValue1 int, aValue2 int) return int
is
begin
  return aValue1 + aValue2 - bitand(aValue1, aValue2);
end BitOr;

---------
procedure BitOr(aValue1 in out nocopy int, aValue2 int)
is
begin
  aValue1 := BitOr(nvl(aValue1, 0), aValue2);
end BitOr;

---------
function BitXor(aValue1 int, aValue2 int) return int
is
begin
  return aValue1 + aValue2 - bitand(aValue1, aValue2) * 2;
end BitXor;

---------
procedure BitXor(aValue1 in out nocopy int, aValue2 int)
is
begin
  aValue1 := BitXor(nvl(aValue1, 0), aValue2);
end BitXor;

---------
function BitClear(aValue int, aBits int) return int
is
begin
  return Util.BitAnd(aValue, 2**63 - aBits - 1);
end BitClear;

---------
procedure BitClear(aValue in out nocopy int, aBits int)
is
begin
  aValue := BitClear(nvl(aValue, 0), aBits);
end BitClear;

---------
function BitSetOrClear(aValue int, aBits int, aIsSet boolean) return int
is
begin
  return case when aIsSet then BitOr(aValue, aBits) else BitClear(aValue, aBits) end;
end BitSetOrClear;

---------
procedure BitSetOrClear(aValue in out nocopy int, aBits int, aIsSet boolean)
is
begin
  aValue := BitSetOrClear(nvl(aValue, 0), aBits, aIsSet);
end BitSetOrClear;


---------
function BitReverse(aValue int, aBitCount int) return int
is
  fValue int := 0;
begin
  if aBitCount between 2 and 64 then
    for i in 0 .. aBitCount - 1 loop
      fValue := fValue + sign(bitand(aValue, 2**i)) * 2**(aBitCount-i-1);
    end loop;
  else
    RaiseErr('Bad bit count');
  end if;
  return fValue;
end BitReverse;

---------
procedure BitReverse(aValue in out nocopy int, aBitCount int)
is
begin
  aValue := BitReverse(nvl(aValue, 0), aBitCount);
end BitReverse;

---------
function IsBitSet(aValue1 int, aValue2 int) return boolean
is
begin
  return nvl(Standard.bitand(aValue1, aValue2) > 0, false);
end IsBitSet;

---------
function IsBitNotSet(aValue1 int, aValue2 int) return boolean
is
begin
  return not IsBitSet(aValue1, aValue2);
end IsBitNotSet;

---------
function IsBitSetN(aValue int, aBitNo int) return int
is
begin
  return case when IsBitSet(aValue, 2 ** (aBitNo - 1)) then 1 else 0 end;
end IsBitSetN;

---------
function Bool2Bit(aBoolean boolean, aBits int := 1) return int
is
begin
  return case aBoolean when true then aBits when false then 0 end;
end Bool2Bit;



---------
function Cutoff(aStr varchar2, aLength pls_integer, aEllipsicChar char := 'Е') return varchar2
is
begin
  return case when nvl(length(aStr), 0) <= aLength then aStr else substr(aStr, 1, aLength - 1) || aEllipsicChar end;
end Cutoff;


---------
function Trim(aStr varchar2, aTrimChars varchar2 := ' ') return varchar2
is
begin
  return ltrim(rtrim(aStr, aTrimChars), aTrimChars);
end Trim;

---------
function UpperFirst(aStr varchar2) return varchar2
is
begin
  return upper(substr(aStr, 1, 1)) || substr(aStr, 2);
end UpperFirst;

---------
function GetCountNounForm_(aValue int) return pls_integer
is
  N int := round(abs(aValue));
begin
  return
    case when mod(N, 100) between 5 and 20 then 3
         when mod(N, 10)  between 2 and 4  then 2
         when mod(N, 10)  =       1        then 1
         else                                   3
    end;
end GetCountNounForm_;

---------
function SelectCountNounForm(aValue int, aCountNounForm varchar2) return varchar2
is
begin
  return SubName(aCountNounForm, GetCountNounForm_(aValue));
end SelectCountNounForm;

---------
function FormatIntIntoPhrase(aInt int, aPhraseForms TStrs, Args TStrs := null) return varchar2
is
begin
  return Format(replace(aPhraseForms(GetCountNounForm_(aInt)), '^', round(aInt)), Args);
end FormatIntIntoPhrase;

---------
function SpelledTriada(aTriada pls_integer, aGender char := 'м') return varchar2
is
  fResult varchar2(100);
  fGender pls_integer;
  N pls_integer;
begin
  if aTriada <> 0 then
    N := mod(trunc(aTriada / 100), 10); -- сотни
    if N between 1 and 9 then
      fResult := SubName('сто|двести|триста|четыреста|п€тьсот|шестьсот|семьсот|восемьсот|дев€тьсот',
                              N) || ' ';
    end if;
    N := mod(aTriada, 100); -- дес€тки и единицы
    if N between 10 and 19 then
      fResult := fResult || SubName('дес€ть|одиннадцать|двенадцать|тринадцать|четырнадцать|п€тнадцать|шестнадцать|семнадцать|восемнадцать|дев€тнадцать',
                                         N - 9) || ' ';
    else
      N := mod(trunc(aTriada / 10), 10); -- дес€тки
      if N between 2 and 9 then
        fResult := fResult || SubName('двадцать|тридцать|сорок|п€тьдес€т|шестьдес€т|семьдес€т|восемьдес€т|дев€носто',
                                           N - 1) || ' ';
      end if;
      N := mod(aTriada, 10); -- единицы
      if N between 3 and 9 then
        fResult := fResult || SubName('три|четыре|п€ть|шесть|семь|восемь|дев€ть',
                                           N - 2) || ' ';
      elsif N between 1 and 2 then
        fGender := case lower(aGender) when 'ж' then 2 when 'с' then 3 else 1 end;
        if N = 1 then
          fResult := fResult || SubName('один|одна|одно', fGender);
        else
          fResult := fResult || SubName('два|две|два', fGender);
        end if;
      end if;
    end if;
  end if;
  return rtrim(fResult);
end SpelledTriada;

---------
function SpelledInt
( aValue int,
  aCountNounForm varchar2 := null,
  aGender char := 'м',
  aFirstUpper boolean := true
) return varchar2
is
  sTriadaGenders constant varchar2(10) := translate(aGender, '_|', '_') || '|ж|м|м|м';
  fValue int := abs(aValue);
  fTriada pls_integer;
  fSpelledTriada varchar2(100);
  fResult varchar2(2000);
begin
  if fValue = 0 then
    fResult := 'ноль ' || SelectCountNounForm(0, aCountNounForm);
  elsif fValue >= 1e15 then
    fResult := 'больше ' || 1e15;
  else
    if aValue < 0 then
      fResult := 'минус ';
    end if;
    for I in reverse 0 .. 4 loop
      fTriada := mod(trunc(fValue / (10 ** (3 * I))), 1000);
      if fTriada <> 0 then
        fSpelledTriada := SpelledTriada(fTriada, SubName(sTriadaGenders, I + 1));
        if fSpelledTriada is not null then
          fResult := fResult || fSpelledTriada || ' ';
          if I > 0 then
            fResult := fResult
            || SelectCountNounForm(fTriada, replace(SubName('тыс€ча^тыс€чи^тыс€ч|миллион^миллиона^миллионов|миллиард^миллиарда^миллиардов|триллион^триллиона^триллионов',
                                                                 I), '^', '|')) || ' ';
          end if;
        end if;
      end if;
    end loop;
    fResult := fResult || SelectCountNounForm(fValue, aCountNounForm);
  end if;
  if aFirstUpper then
    fResult := UpperFirst(fResult);
  end if;
  return rtrim(fResult);
end SpelledInt;

---------
function NormalizeFIO(aSurname varchar2, aName varchar2, aPatronymic varchar2) return varchar2
is
  pragma inline (NormalizeSecondaryFioPart, 'YES');
  function NormalizeSecondaryFioPart(aPart varchar2) return varchar2
  is
  begin
    return
      case nvl(length(aPart), 0)
        when 0 then ''
        when 1 then ' ' || upper(aPart) || '.'
               else ' ' || UpperFirst(aPart)
      end;
  end NormalizeSecondaryFioPart;
begin
  return ltrim(UpperFirst(aSurname) || NormalizeSecondaryFioPart(aName) || NormalizeSecondaryFioPart(aPatronymic));
end NormalizeFIO;

---------
function NormalizeAddress(
  aRegion     varchar2 := null,
  aDistrict   varchar2 := null,
  aCityType   varchar2 := null,
  aCity       varchar2 := null,
  aStreetType varchar2 := null,
  aStreet     varchar2 := null,
  aHouse      varchar2 := null,
  aBuilding   varchar2 := null,
  aApartment  varchar2 := null
) return varchar2
is
  function RegionAndDistrictTrim(aValue varchar2) return varchar2
  is
  begin
    return initcap(regexp_replace(lower(aValue), '(обл|область|р|р-н|район)(\s|\.|$)\s?'));
  end RegionAndDistrictTrim;
begin
  return
    rtrim
    (  case    when aRegion     is not null then  RegionAndDistrictTrim(aRegion)  || ' обл, ' end
    || case    when aDistrict   is not null then  RegionAndDistrictTrim(aDistrict)|| ' р-н, ' end
    || case    when aCity       is not null then
         case  when aCityType   is not null then    lower(aCityType)   || ' '     end
         ||                                    UpperFirst(aCity)       || ', '    end
    || case    when aStreet     is not null then
         case  when aStreetType is not null then    lower(aStreetType) || ' '     end
         ||                                    UpperFirst(aStreet)     || ', '    end
    || case    when aHouse      is not null then  'д.' || aHouse
       || case when aBuilding   is not null then   '/' || aBuilding               end
                                                                       || ' '     end
    || case    when aApartment  is not null then 'кв.' || aApartment              end
    , ', '
    );
end NormalizeAddress;

---------
function ShortenFIO(aFIO varchar2, aMaxLen int) return varchar2
is
  fPos pls_integer;
  fFioFull  varchar2(2000) := trim(aFIO);
  fFioShort varchar2(2000);
begin
  if fFioFull is not null then
    loop
      exit when length(fFioFull) + nvl(length(fFioShort), 0) <= aMaxLen;
      fPos := instr(fFioFull, ' ', -1, 1);
      exit when fPos = 0;
      fFioShort := ' ' || substr(fFioFull, fPos + 1, 1) || '.' || fFioShort;
      fFioFull := rtrim(substr(fFioFull, 1, fPos - 1));
    end loop;
    fFioFull := fFioFull || fFioShort;
    if length(fFioFull) > aMaxLen then
      fFioFull := replace(fFioFull, '. ', '.');
    end if;
    if length(fFioFull) > aMaxLen + 1 then
      fFioFull := replace(fFioFull, '.');
    end if;
  end if;
  return rtrim(substr(fFioFull, 1, aMaxLen));
end ShortenFIO;

-- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

---------
procedure RaiseErr(ErrText varchar2, Args TStrs := null, aErrorClass pls_integer := null, aKeepErrorStack boolean := false)
is
  fErrorCode pls_integer := case when aErrorClass between -20999 and -20001 then aErrorClass else -20000 end;
begin
  raise_application_error
  ( fErrorCode
  , Format(ErrText, Args) || case when aErrorClass is not null and fErrorCode = -20000 then ' {=' || aErrorClass || '=}' end
  , keeperrorstack=>aKeepErrorStack
  );
end RaiseErr;

---------
procedure RaiseErr
( ErrText varchar2,
  S1 varchar2      , S2 varchar2 := '', S3 varchar2 := '', S4 varchar2 := '',
  S5 varchar2 := '', S6 varchar2 := '', S7 varchar2 := '',
  S8 varchar2 := '', S9 varchar2 := '', S10 varchar2 := ''
)
is
begin
  RaiseErr(ErrText, TStrs(S1,S2,S3,S4,S5,S6,S7,S8,S9,S10));
end RaiseErr;

---------
function RaiseErr
( ErrText varchar2,
  S1 varchar2      , S2 varchar2 := '', S3 varchar2 := '', S4 varchar2 := '',
  S5 varchar2 := '', S6 varchar2 := '', S7 varchar2 := '',
  S8 varchar2 := '', S9 varchar2 := '', S10 varchar2 := ''
) return varchar2
is
begin
  RaiseErr(ErrText, TStrs(S1,S2,S3,S4,S5,S6,S7,S8,S9,S10));
end RaiseErr;

---------
procedure CheckErr(ErrCondition boolean, ErrText varchar2, Args TStrs := null, aErrorClass pls_integer := null)
is
begin
  if ErrCondition then
    RaiseErr(ErrText, Args, aErrorClass);
  end if;
end CheckErr;

---------
procedure CheckErr
( ErrCondition boolean,
  ErrText varchar2,
  S1 varchar2      , S2 varchar2 := '', S3 varchar2 := '', S4 varchar2 := '',
  S5 varchar2 := '', S6 varchar2 := '', S7 varchar2 := '',
  S8 varchar2 := '', S9 varchar2 := '', S10 varchar2 := ''
)
is
begin
  CheckErr(ErrCondition, ErrText, TStrs(S1,S2,S3,S4,S5,S6,S7,S8,S9,S10));
end CheckErr;

---------
procedure CheckErrText(aErrText varchar2, aErrorClass pls_integer := null)
is
begin
  CheckErr(aErrText is not null, aErrText, aErrorClass=>aErrorClass);
end CheckErrText;

---------
procedure Abort(aMessage varchar2 := '')
is
begin
  Util.RaiseErr(aMessage, aErrorClass=>Util.ERROR_CLASS_ABORT);
end Abort;

---------
procedure AbortIf(aAbortCondition boolean, aMessage varchar2 := '')
is
begin
  Util.CheckErr(aAbortCondition, aMessage, aErrorClass=>Util.ERROR_CLASS_ABORT);
end AbortIf;

---------
function NormalizeSqlErrMGetErrorClass
( aErrorClass              out pls_integer
, aMaxErrLen                   pls_integer := null
, aShortTextForSystemError     boolean := false
) return varchar2
is
  fErrLen pls_integer;
  fErrText varchar2(4000);
  sErrorClassRE varchar2(20) := ' {=(-?\d+)=}';
begin
  if not aShortTextForSystemError or sqlcode between -20999 and -20000 then
    fErrText := substr(sqlerrm, case when sqlcode between -20999 and -20000 then 12
                                        when sqlcode = -06550                  then instr(sqlerrm, chr(10)) + 1
                                        when sqlcode = -28003                  then instr(sqlerrm, chr(10), 2) + 12
                                                                               else 1
                                   end, 4000);
  end if;
  fErrLen := instr(fErrText, chr(10)) - 1;
  if fErrLen = -1 then
    fErrLen := length(fErrText);
  end if;
  fErrText :=
    substr
    ( nvl(fErrText, case when aShortTextForSystemError then 'ќшибка сервера (' || -sqlcode || ')' end)
    , 1
    , least(nvl(fErrLen, 4000), nvl(aMaxErrLen, 4000))
    );
  aErrorClass := regexp_substr(fErrText, sErrorClassRE, 1, 1, '', 1);
  if aErrorClass is not null then
    fErrText := regexp_replace(fErrText, sErrorClassRE);
  end if;
  return fErrText;
end NormalizeSqlErrMGetErrorClass;

---------
function NormalizeSqlErrM
( aMaxErrLen                   pls_integer := null
, aShortTextForSystemError     boolean := false
) return varchar2
is
  fErrorClass pls_integer;
begin
  return NormalizeSqlErrMGetErrorClass(fErrorClass, aMaxErrLen, aShortTextForSystemError);
end NormalizeSqlErrM;

---------
function GetErrorClass return pls_integer
is
  fErrorClass pls_integer;
  fErrText varchar2(4000) := NormalizeSqlErrMGetErrorClass(fErrorClass);
begin
  return fErrorClass;
end GetErrorClass;

---------
function ConstraintName return varchar2
is
  fConstraint varchar2(4000);
  sConstraintNameRE varchar2(99) := '\([a-zA-Z0-9_#$]+\.([a-zA-Z0-9_#$]+)\)';
begin
  if sqlcode in (-1/*unique*/, -2290/*check*/, -2291/*no parent*/, -2292/*has child*/) then
    fConstraint := regexp_substr(sqlerrm, sConstraintNameRE, 1, 1, '', 1);
  end if;
  return fConstraint;
end ConstraintName;

-- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

---------
function Translit(aValue varchar2) return varchar2
is
  c_Rus constant varchar2(48) := q'{јЅ¬√ƒ≈®«»… ЋћЌќѕ–—“”‘џЁ№Џ}';
  c_Lat constant varchar2(48) := q'{ABVGDEEZIYKLMNOPRSTUFYE''}';
  c_ExtRus constant varchar2(30) := '∆’÷„Ўёяў';
  c_ExtLat constant TStrs := TStrs('Zh', 'Kh', 'Ts', 'Ch', 'Sh', 'Yu', 'Ya', 'Shch');
  fResult varchar2(2000);
  ch_rus varchar2(1);
  ch_lat varchar2(4);
begin
  fResult := '';
  fResult := translate(aValue, c_Rus||nls_lower(c_Rus), c_Lat||lower(c_Lat));
  for i in 1..c_ExtLat.count loop
    ch_rus := substr(c_ExtRus, i, 1);
    ch_lat := c_ExtLat(i);
    fResult := replace(fResult, ch_rus, ch_lat);
    fResult := replace(fResult, nls_lower(ch_rus), lower(ch_lat));
  end loop;
  return fResult;
end Translit;

---------
function HomographTo_(aValue varchar2, aToLatin boolean) return varchar2
is
  cCyrillicSet constant varchar2(33) := '” ≈’ј–ќ—ћЌ¬“'
                                     || 'укехаросм';
  cLatinSet    constant varchar2(33) := 'YKEXAPOCMHBT'
                                     || 'ykexapocm';
begin
  return case when aToLatin then translate(aValue, cCyrillicSet, cLatinSet   )
                            else translate(aValue, cLatinSet   , cCyrillicSet)
         end;
end HomographTo_;

---------
procedure HomographToLatin(aValue in out nocopy varchar2)
is
begin
  aValue := HomographTo_(aValue, aToLatin=>true);
end HomographToLatin;

---------
function HomographToLatin(aValue varchar2) return varchar2
is
begin
  return HomographTo_(aValue, aToLatin=>true);
end HomographToLatin;

---------
procedure HomographToCyrillic(aValue in out nocopy varchar2)
is
begin
  aValue := HomographTo_(aValue, aToLatin=>false);
end HomographToCyrillic;

---------
function HomographToCyrillic(aValue varchar2) return varchar2
is
begin
  return HomographTo_(aValue, aToLatin=>false);
end HomographToCyrillic;

---------
function IntToAlphabet(aValue int, aAlphabet varchar2, aMinLength pls_integer := null) return varchar2
is
  fRadix pls_integer := length(aAlphabet);
  fDigit pls_integer;
  fValue int := abs(aValue);
  fResult varchar2(100) := '';
begin
  if aValue < 0 and instr(aAlphabet, '-') > 0 then
    raise value_error;
  end if;
  if aValue is not null then
    loop
      fDigit := mod(fValue, fRadix);
      fResult := substr(aAlphabet, fDigit + 1, 1) || fResult;
      exit when fValue < fRadix;
      fValue := (fValue - fDigit) / fRadix;
    end loop;
  end if;
  if length(fResult) < aMinLength then
    fResult := lpad(fResult, aMinLength, substr(aAlphabet, 1, 1));
  end if;
  return case when aValue < 0 then '-' end || fResult;
end IntToAlphabet;

---------
function AlphabetToInt(aValue varchar2, aAlphabet varchar2) return int
is
  fRadix pls_integer := length(aAlphabet);
  fDigit pls_integer;
  fResult int;
  fSign int := +1;
begin
  if aValue is not null then
    if substr(aValue, 1, 1) = '-' and instr(aAlphabet, '-') = 0 then
      if length(aValue) = 1 then
        raise value_error;
      end if;
      fSign := -1;
    end if;
    fResult := 0;
    for i in reverse 1 .. length(aValue) - case fSign when -1 then 1 else 0 end loop
      fDigit := instr(aAlphabet, substr(aValue, -i, 1)) - 1;
      if fDigit = -1 then
        raise value_error;
      end if;
      fResult := fResult + fDigit * power(fRadix, i - 1);
    end loop;
  end if;
  return fSign * fResult;
end AlphabetToInt;

---------
function IntToAlphaNumeric(aValue int, aMinLength pls_integer := null) return varchar2
is
begin
  return IntToAlphabet(aValue, gcRadix36Alphabet, aMinLength);
end IntToAlphaNumeric;

---------
function AlphaNumericToInt(aValue varchar2) return int
is
begin
  return AlphabetToInt(aValue, gcRadix36Alphabet);
end AlphaNumericToInt;

---------
function IntToAlpha(aValue int, aMinLength pls_integer := null) return varchar2
is
begin
  return IntToAlphabet(aValue, gcRadix26Alphabet, aMinLength);
end IntToAlpha;

---------
function AlphaToInt(aValue varchar2) return int
is
begin
  return AlphabetToInt(aValue, gcRadix26Alphabet);
end AlphaToInt;


---------
function GCD(aValue1 number, aValue2 number) return number
is
  fBig   number;
  fSmall number;
  fRest  number;
begin
  fBig   := greatest(aValue1, aValue2);
  fSmall := least   (aValue1, aValue2);
  loop
     fRest  := mod(fBig, fSmall);
     exit when fRest = 0 or fRest is null;
     fBig   := fSmall;
     fSmall := fRest;
  end loop;
  return fSmall;
end GCD;

---------
function LCM(aValue1 number, aValue2 number) return number
is
begin
  return aValue1 * aValue2 / GCD(aValue1, aValue2);
end LCM;

---------
function RoundSignificantDigits(aValue number, aSignificantDigits pls_integer) return number
is
begin
  return round(aValue, aSignificantDigits - ceil(log(10, aValue)));
end RoundSignificantDigits;




---------
function IsValidEMailAddress(aAddr varchar2) return boolean
is
  fResult boolean := true;
  fAddr varchar2(2000);
begin
  for i in 1..SubNameCount(aAddr, ';') loop
    fAddr := trim(SubName(aAddr, i, ';'));
    fResult := owa_pattern.match(fAddr, '^[._a-zA-Z0-9\-]+@[_a-zA-Z0-9\-]+\.[._a-zA-Z0-9\-]+[^.]$')
       and not owa_pattern.match(fAddr, '^.+@.+[.]{2}.*$')
    ;
    exit when not fResult;
  end loop;
  return fResult;
end IsValidEMailAddress;

---------
procedure CheckEMailAddress(aAddr varchar2)
is
begin
  CheckErr(not IsValidEMailAddress(aAddr), 'Ќекорректный e-mail адрес "%s"', aAddr);
end CheckEMailAddress;


---------
function MaskValue(aValue varchar2, aMaskingAlgorithm varchar2, aMaskChar varchar2 := '*') return varchar2
is
  fResult varchar2(200);
  fLens TStrArr;
  fVaryingIndex pls_integer;
  fFixedLen pls_integer := 0;
  fPos pls_integer := 1;
begin
  for i in 1 .. SubnameCount(aMaskingAlgorithm) loop
    fLens(i) := Subname(aMaskingAlgorithm, i);
    if fLens(i) is null then
      if fVaryingIndex is null then
        fVaryingIndex := i;
      else
        fLens(i) := 0;
      end if;
    else
      fFixedLen := fFixedLen + fLens(i);
    end if;
  end loop;
  if length(aValue) < fFixedLen then
    fResult := aValue;
  else
    if fVaryingIndex is not null then
      fLens(fVaryingIndex) := length(aValue) - fFixedLen;
    end if;
    for i in 1 .. fLens.count loop
      fResult := fResult
      || case mod(i, 2) when 1 -- нечЄтные части оставить без изменений
                        then substr(aValue, fPos, fLens(i))
                        else rpad(aMaskChar, fLens(i), aMaskChar)
         end;
      fPos := fPos + fLens(i);
    end loop;
  end if;
  return fResult;
exception
  when value_error then
    return aValue;
end MaskValue;

--------
function Pivot(aTo int, aFrom int := 1) return tp_int_table pipelined
is
begin
  for i IN aFrom .. aTo loop
    pipe row (i);
  end loop;
  return;
end Pivot;

---------
function ListAgg(aTable tp_varchar2_4000_table, aSeparator varchar2 := '|') return varchar2
is
  fRes varchar2(4000);
begin
  if aTable is not null then
    for i in 1 .. aTable.count loop
      fRes := fRes || case when i > 1 then aSeparator end || aTable(i);
    end loop;
  end if;
  return fRes;
exception
  when value_error then
    return fRes;
end ListAgg;

-- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

---------
function GetLuhnDigit(aCardNo varchar2) return int
is
  fCardNoLength pls_integer;

  fLuhnDigit pls_integer;
  twoByte pls_integer;
  k1 pls_integer;
  k2 pls_integer;
begin
  if aCardNo is not null and rtrim(aCardNo, '1234567890') is null then
    fLuhnDigit := 0;
    fCardNoLength := length(aCardNo);
    for i in reverse 1..fCardNoLength loop
      if mod(fCardNoLength - i, 2) = 0 then
        twoByte := 2 * to_number(substr(aCardNo, i, 1));
        k1 := mod(twoByte, 10);
        k2 := trunc(twoByte / 10);
      else
        k1 := to_number(substr(aCardNo, i, 1));
        k2 := 0;
      end if;
      fLuhnDigit := fLuhnDigit + k1 + k2;
    end loop;
    fLuhnDigit := mod(10 - mod(fLuhnDigit, 10), 10);
  end if;
  return fLuhnDigit;
end GetLuhnDigit;

-- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

---------
function Dos2Date(aDosDate int, aDosTime int) return date
is
begin
  return
    to_date
    (    case
           when Util.BitAnd(aDosDate, 2**5-1) = 0 then
             1
           else Util.BitAnd(aDosDate, 2**5-1)
         end                                       || '.'
      || case
           when Util.BitAnd(trunc(aDosDate/2**5), 2**4-1) = 0 then
             1
           else Util.BitAnd(trunc(aDosDate/2**5), 2**4-1)
         end                                       || '.'
      || to_char(trunc(aDosDate/2**9) + 1980)      || ' '
      || trunc(aDosTime/2**11)                     || ':'
      || Util.BitAnd(trunc(aDosTime/2**5), 2**6-1) || ':'
      || Util.BitAnd(aDosTime, 2**5-1) * 2
    , 'dd.mm.yyyy hh24:mi:ss'
    );
exception
  when others then
    RaiseErr('ќшибка в формате даты');
end Dos2Date;

---------
procedure Dos2Date(aDosDate int, aDosTime int, aDate out date)
is
begin
  aDate := Dos2Date(aDosDate, aDosTime);
end Dos2Date;

---------
procedure Date2Dos(aDate date, aDosDate out int, aDosTime out int)
is
begin
  aDosDate :=   Util.BitAnd(to_number(to_char(aDate, 'yyyy')) - 1980, 2**8-1) * 2**9
              + to_char(aDate, 'mm') * 2**5
              + to_char(aDate, 'dd')
              ;
  aDosTime :=   trunc(to_char(aDate, 'ss') / 2)
              + to_char(aDate, 'mi')   * 2**5
              + to_char(aDate, 'hh24') * 2**11;
end Date2Dos;

---------
function Unix2Date(aUnixTimestamp int, aNoUTC boolean := false) return date
is
  fResult date;
begin
  fResult := date '1970-01-01' + aUnixTimestamp / 86400;
  return case when aNoUTC then fResult else from_tz(fResult, 'UTC') at time zone dbtimezone end;
end Unix2Date;

---------
function Date2Unix(aDate date, aNoUTC boolean := false) return int
is
begin
  return (case when aNoUTC then aDate else cast(sys_extract_utc(from_tz(aDate, dbtimezone)) as date) end - date '1970-01-01') * 86400;
end Date2Unix;

---------
function Delphi2Date(aDate number) return date
is
begin
  return to_date('30121899', 'ddmmyyyy') + aDate;
end Delphi2Date;

---------
function Date2Delphi(aDate date) return number
is
begin
  return aDate - to_date('30121899', 'ddmmyyyy');
end Date2Delphi;




---------
function CS(aConstantName varchar2) return varchar2 result_cache
is
  fResult varchar2(4000);
begin
  if not regexp_like(aConstantName, '^[A-Za-z_$#0-9.]+$') then
    Util.RaiseErr('Invalid constant name "%s"', Util.TStrs(aConstantName));
  end if;
  if sys_context('userenv', 'current_user') <> sys_context('userenv', 'session_user') then -- Called not by owner
    begin
      execute immediate 'declare x varchar2(32767); begin return; x := '|| aConstantName || '(); end;';
      Util.RaiseErr('"%s" is a function not a constant', Util.TStrs(aConstantName));
    exception
      when Util.ePlSqlCompilationError then
        null; -- not a function - OK
    end;
  end if;
  execute immediate 'begin :1 := '|| aConstantName || '; end;' using out fResult;
  return fResult;
exception
  when Util.ePlSqlCompilationError then
    Util.RaiseErr('Unknown constant "%s"', Util.TStrs(aConstantName));
end CS;

---------
function CN(aConstantName varchar2) return number
is
begin
  return CS(aConstantName);
end CN;


---------
function Color(aColorName varchar2) return varchar2 result_cache
is
begin
  return case when aColorName is not null then CS('Util.COLOR_' || aColorName) end;
end Color;

---------
function ReplaceC(aSrcStr clob, aOldSub varchar2, aNewSub clob := null) return clob
is
  fStartIndex   pls_integer := 1;
  fCurrentIndex pls_integer;
  fResult       clob;
  fFound        boolean := false;
begin
  fCurrentIndex := instr(aSrcStr, aOldSub);
  while fCurrentIndex > 0 loop
    fResult       := fResult || substr(aSrcStr, fStartIndex, fCurrentIndex - fStartIndex) || aNewSub;
    fStartIndex   := fCurrentIndex + length(aOldSub);
    fCurrentIndex := instr(aSrcStr, aOldSub, fStartIndex);
    fFound        := true;
  end loop;
  if fFound then
    return fResult || substr(aSrcStr, fStartIndex, length(aSrcStr) - fStartIndex + 1);
  end if;
  return aSrcStr;
end ReplaceC;

-- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
end Util;
/
show err

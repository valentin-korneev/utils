prompt create or replace package body xml_Util

create or replace package body xml_Util
as

---------
function EncodeXML(aValue varchar2) return varchar2
is
  eEncodeBufferTooSmall exception;
  pragma exception_init(eEncodeBufferTooSmall, -19011);
begin
  return dbms_xmlgen.convert(aValue, dbms_xmlgen.ENTITY_ENCODE);
exception
  when eEncodeBufferTooSmall then
    return dbms_xmlgen.convert(cast(aValue as clob), dbms_xmlgen.ENTITY_ENCODE);
end EncodeXML;

---------
function DecodeXML(aValue varchar2) return varchar2
is
begin
  return dbms_xmlgen.convert(aValue, dbms_xmlgen.ENTITY_DECODE);
end DecodeXML;


---------
function SerializeXML(aXML xmltype) return clob
is
  fClob clob;
begin
  --return aXML.extract('/').getClobVal(); -- in 11g PL/SQL extract('/') still produces pretty output (while SQL doesn't)
  select xmlserialize(content aXML indent) into fClob from dual;
  return fClob;
end SerializeXML;


---------
function CreateAttr(aAttrName varchar2, aAttrVal varchar2, aDefVal varchar2 := null, aEncoding boolean := true, aMandatory boolean := false) return varchar2
is
begin
  if (aAttrVal is null or aAttrVal = aDefVal) and not aMandatory then
    return null;
  else
    return ' ' || aAttrName || '="' || case when aEncoding then EncodeXML(aAttrVal) else aAttrVal end || '"';
  end if;
end CreateAttr;

---------
function CreateAttr(aAttrName varchar2, aAttrVal boolean, aDefVal boolean := null) return varchar2
is
begin
  return CreateAttr(aAttrName, case aAttrVal when true then 'Y' when false then 'N' end,
                               case aDefVal  when true then 'Y' when false then 'N' end, false);
end CreateAttr;

---------
function CreateAttr(aAttrName varchar2, aAttrVal date, aFormat varchar2) return varchar2
is
begin
  return CreateAttr(aAttrName, to_char(aAttrVal, aFormat), aEncoding=>false);
end CreateAttr;

---------
function CreateAttr(aAttrName varchar2, aAttrVal number, aDefVal number := null) return varchar2
is
begin
  return CreateAttr(aAttrName, Util.Num2Str(aAttrVal), aDefVal=>Util.Num2Str(aDefVal));
end CreateAttr;

---------
function OpenElement
( aElementName varchar2
, aElementAttr varchar2 := null
, aIndentCount int := 0
, aLeftBR boolean := true
, aPreserveWhitespaces boolean := false
, aClose boolean := false
) return varchar2
is
begin
  return case when aLeftBR then EndLine end
      || rpad(' ', aIndentCount * 2)
      || '<' || aElementName
      || aElementAttr
      || case when aPreserveWhitespaces then ' xml:space="preserve"' end
      || case when aClose then '/' end || '>';
end OpenElement;

---------
function CloseElement
( aElementName varchar2
, aIndentCount int := 0
, aLeftBR boolean := true
) return varchar2
is
begin
  return case when aLeftBR then EndLine end || rpad(' ', aIndentCount * 2) || '</' || aElementName || '>';
end CloseElement;

---------
procedure AddElementToBuff
( aBuff in out nocopy varchar2
, aElementName varchar2
, aElementVal varchar2 := null
, aElementAttr varchar2 := null
, aIndentCount int := 0
, aLeftBR boolean := true
, aEncoding boolean := true
, aPreserveWhitespaces boolean := false
)
is
begin
  aBuff := aBuff || Element(aElementName, aElementVal, aElementAttr, aIndentCount, aLeftBR, aEncoding, aPreserveWhitespaces);
end AddElementToBuff;

---------
function Element
( aElementName varchar2
, aElementVal varchar2 := null
, aElementAttr varchar2 := null
, aIndentCount int := 0
, aLeftBR boolean := true
, aEncoding boolean := true
, aPreserveWhitespaces boolean := false
, aMandatory boolean := true
, aCloseOnNewLine boolean := false
) return varchar2
is
begin
  if aElementName is null then
    Util.RaiseErr('No XML tag name!');
  end if;
  if aElementVal is null then
    if aMandatory or aElementAttr is not null then
      return OpenElement(aElementName, aElementAttr, aIndentCount, aLeftBR, aPreserveWhitespaces, aClose=>true);
    else
      return null;
    end if;
  else
    return OpenElement(aElementName, aElementAttr, aIndentCount, aLeftBR, aPreserveWhitespaces)
        || case when aEncoding then EncodeXML(aElementVal) else aElementVal end
        || case when aCloseOnNewLine then CloseElement(aElementName, aIndentCount) else '</' || aElementName || '>' end;
  end if;
end Element;

---------
function Element
( aElementName varchar2
, aElementVal date
, aFormat varchar2
, aElementAttr varchar2 := null
, aIndentCount int := 0
, aLeftBR boolean := true
, aMandatory boolean := true
) return varchar2
is
begin
  return Element(aElementName, to_char(aElementVal, aFormat), aElementAttr, aIndentCount, aLeftBR, aEncoding=>false, aMandatory=>aMandatory);
end Element;

---------
function Element
( aElementName          varchar2
, aElementVal           boolean
, aElementAttr          varchar2 := null
, aIndentCount          int := 0
, aLeftBR               boolean := true
, aMandatory            boolean := true
, aDefault              boolean := null
) return varchar2
is
begin
  if aDefault is null or aDefault <> aElementVal or aMandatory then
    return Element(aElementName, case when aElementVal then 'Y' when not aElementVal then 'N' end
           , aElementAttr, aIndentCount, aLeftBR, aEncoding=>false, aMandatory=>aMandatory);
  else
    return null;
  end if;
end Element;


--========================================================================================

---------
function GetValueS
( aValue varchar2
, aValueName varchar2
, aMaxLen int := 100
, aMinLen int := 0
, aConst varchar2 := null
, aMandatory boolean := true
, aConstList tp_varchar2_100_table := null
, aDefault varchar2 := null
, aValidChars varchar2 := null
, aHomographToLatin boolean := false
, aTrim boolean := true
) return varchar2
is
  fValueS varchar2(32767) := Util.Trim(aValue, chr(9)||chr(10)||chr(13)||case when aTrim then ' ' end);
begin
  if fValueS is null then
    if aDefault is not null then
      fValueS := aDefault;
    elsif aMandatory then
      Util.RaiseErr('%s - должен быть задан', aValueName);
    end if;
  else
    if length(fValueS) not between aMinLen and aMaxLen then
      Util.RaiseErr('%s - неверная длина (%d). Допустимая длина [%d..%d]', aValueName, length(fValueS), aMinLen, aMaxLen);
    end if;
    fValueS := case when aHomographToLatin then Util.HomographToLatin(fValueS) else fValueS end;
    if aValidChars is not null and ltrim(fValueS, aValidChars) is not null then
      Util.RaiseErr('%s - недопустимые символы "%s"', aValueName, translate(fValueS, chr(9) || aValidChars, chr(9)));
    end if;
    if aConst     is not null and fValueS <>            aConst
       or
       aConstList is not null and fValueS not member of aConstList
    then
      Util.RaiseErr('%s - недопустимое значение "%s"', aValueName, fValueS);
    end if;
  end if;
  return fValueS;
end GetValueS;

---------
function GetValueN
( aValue        varchar2
, aValueName    varchar2
, aMaxLen       int := 38
, aMinLen       int := 0
, aConst        number := null
, aMandatory    boolean := true
, aMinNumValue  number := null
, aMaxNumValue  number := null
, aPositive     boolean := true
, aFormat       varchar2 := null
, aConstList    tp_num_table := null
, aDefault      number := null
) return number
is
  fValueS varchar2(32767) := Util.Trim(aValue, chr(9)||chr(10)||chr(13)||' ');
  fMinNumValue number := coalesce
                         ( aMinNumValue
                         , case
                             when aPositive then
                               case when aMinLen > 0
                                 then 10 ** (aMinLen - 1)
                                 else 0
                               end
                             else
                               -(10 ** aMaxLen - 1)
                           end
                         );
  fMaxNumValue number := coalesce(aMaxNumValue,  10 ** aMaxLen - 1);
  fValueN number;
begin
  if fValueS is null then
    if aDefault is not null then
      fValueN := aDefault;
    elsif aMandatory then
      Util.RaiseErr('%s - должен быть задан', aValueName);
    end if;
  else
    fValueN := StrToNum(trim(fValueS), aFormat, aValueName);
    if aPositive and fValueN < 0 then
      Util.RaiseErr('%s - отрицательное значение недопустимо (%d)', aValueName, fValueN);
    end if;
    if fValueN < fMinNumValue or fValueN > fMaxNumValue then
      Util.RaiseErr('%s - допустимый диапазон значений [%d .. %d]', aValueName, fMinNumValue, fMaxNumValue);
    end if;
    if aConst     is not null and fValueN <>            aConst
       or
       aConstList is not null and fValueN not member of aConstList
    then
      Util.RaiseErr('%s - недопустимое значение "%d"', aValueName, fValueN);
    end if;
  end if;
  return fValueN;
end GetValueN;

---------
function GetValueD
( aValue        varchar2
, aValueName    varchar2
, aMaxLen       int           := 30
, aMinLen       int           := 0
, aConst        date          := null
, aMandatory    boolean       := true
, aFormat       varchar2      := FMT_DATE
, aConstList    tp_date_table := null
, aDefault      date          := null
, aMinDateValue date          := null
, aMaxDateValue date          := null
) return date
is
  fValueS varchar2(32767) := Util.Trim(aValue, chr(9)||chr(10)||chr(13)||' ');
  fValueD date;
begin
  if fValueS is null then
    if aDefault is not null then
      fValueD := aDefault;
    elsif aMandatory then
      Util.RaiseErr('%s - должен быть задан', aValueName);
    end if;
  else
    if length(fValueS) not between aMinLen and aMaxLen then
      Util.RaiseErr('%s - неверная длина (%d). Допустимая длина [%d..%d]', aValueName, length(fValueS), aMinLen, aMaxLen);
    end if;
    fValueD := StrToDate(fValueS, aFormat, aValueName);
    if fValueD < aMinDateValue or fValueD > aMaxDateValue then
      Util.RaiseErr('%s - допустимый диапазон значений [%D .. %D]', aValueName, aMinDateValue, aMaxDateValue);
    end if;
    if aConst     is not null and fValueD <>            aConst
       or
       aConstList is not null and fValueD not member of aConstList
    then
      Util.RaiseErr('%s - недопустимое значение "%s"', aValueName, fValueS);
    end if;
  end if;
  return fValueD;
end GetValueD;

---------
function GetValueT
( aValue            varchar2
, aValueName        varchar2
, aMandatory        boolean       := true
, aDefault          timestamp     := null
) return timestamp
is
  fValueS varchar2(32767) := Util.Trim(aValue, chr(9)||chr(10)||chr(13)||' ');
  fValueT timestamp;
begin
  if fValueS is null then
    if aDefault is not null then
      fValueT := aDefault;
    elsif aMandatory then
      Util.RaiseErr('%s - должен быть задан', aValueName);
    end if;
  else
    fValueT :=  to_timestamp_tz(fValueS, FMT_DATE_ISO8601) at time zone dbtimezone;
  end if;
  return fValueT;
exception
  when others then
    if sqlcode between -1899 and -1800 then
      Util.RaiseErr('%s - недопустимые дата/время (%s)', aValueName, aValue);
    else
      raise;
    end if;
end GetValueT;

---------
function GetValueB
( aValue varchar2
, aValueName varchar2
, aMandatory boolean := true
, aDefault boolean := null
) return boolean
is
  fValueS varchar2(32767) := Util.Trim(aValue, chr(9)||chr(10)||chr(13)||' ');
  fValueB boolean;
begin
  if fValueS is null then
    if aDefault is not null then
      fValueB := aDefault;
    elsif aMandatory then
      Util.RaiseErr('%s - должен быть задан', aValueName);
    end if;
  else
    if upper(fValueS) not in ('Y', 'N', 'TRUE', 'FALSE', 'YES', 'NO') then
      Util.RaiseErr('%s - недопустимое значение "%s"', aValueName, fValueS);
    end if;
    fValueB := upper(fValueS) in ('Y', 'TRUE', 'YES');
  end if;
  return fValueB;
end GetValueB;


---------
procedure GetValueFromXml
( aValue     out nocopy varchar2
, aValueName out nocopy varchar2
, aXML XMLType
, aElementPath varchar2
, aAttrName varchar2
, aIndexOrPredicate varchar2
, aNamespace varchar2
, aDecoding boolean := false
)
is
  fXML XMLType;
begin
  aValueName := aElementPath
             || case when aIndexOrPredicate is not null then '[' || aIndexOrPredicate || ']' end
             || case when aAttrName is not null then '/@' || aAttrName end;
  if aXML is not null then
    fXML := aXML.extract(aValueName || case when aAttrName is null then '/text()' end, aNamespace);
    if fXML is not null then
      aValue := case when aDecoding then DecodeXML(fXML.getstringval()) else fXML.getstringval() end;
    end if;
  end if;
end GetValueFromXml;

---------
function GetValueS
( aXML XMLType
, aElementPath varchar2
, aAttrName varchar2 := ''
, aMaxLen int := 100
, aIndexOrPredicate varchar2 := '1'
, aMinLen int := 0
, aConst varchar2 := null
, aMandatory boolean := true
, aDecoding boolean := true
, aConstList tp_varchar2_100_table := null
, aNamespace varchar2 := null
, aDefault varchar2 := null
, aValidChars varchar2 := null
, aHomographToLatin boolean := false
, aTrim boolean := null
) return varchar2
is
  fValue     varchar2(32767);
  fValueName varchar2(4000);
begin
  GetValueFromXml(fValue, fValueName, aXML, aElementPath, aAttrName, aIndexOrPredicate, aNamespace, aDecoding);
  if fValue like '<![CDATA[%]]>' then
    fValue := substr(fValue, 10, length(fValue) - 12);
  end if;
  return
    GetValueS
    ( fValue, fValueName, aMaxLen, aMinLen, aConst, aMandatory
    , aConstList, aDefault, aValidChars, aHomographToLatin
    , aTrim=>coalesce
             ( aTrim
             , case when aXML is not null then
                 aXML.existsNode
                 ( aElementPath
                   || case when aIndexOrPredicate is not null then '[' || aIndexOrPredicate || ']' end
                   || '/ancestor-or-self::*[@xml:space="preserve"]'
                 , aNamespace
                 ) = 0
               end
             )
    );
end GetValueS;

---------
function GetValueN
( aXML XMLType
, aElementPath      varchar2
, aAttrName         varchar2 := ''
, aMaxLen           int := 38
, aIndexOrPredicate varchar2 := '1'
, aMinLen           int := 0
, aConst            number := null
, aMandatory        boolean := true
, aMinNumValue      number := null
, aMaxNumValue      number := null
, aPositive         boolean := true
, aFormat           varchar2 := null
, aConstList        tp_num_table := null
, aNamespace        varchar2 := null
, aDefault          number := null
) return number
is
  fValue     varchar2(32767);
  fValueName varchar2(4000);
begin
  GetValueFromXml(fValue, fValueName, aXML, aElementPath, aAttrName, aIndexOrPredicate, aNamespace);
  return
    GetValueN
    ( fValue, fValueName, aMaxLen, aMinLen, aConst, aMandatory
    , aMinNumValue, aMaxNumValue, aPositive, aFormat, aConstList, aDefault
    );
end GetValueN;

---------
function GetValueD
( aXML              XMLType
, aElementPath      varchar2
, aAttrName         varchar2      := ''
, aMaxLen           int           := 30
, aIndexOrPredicate varchar2      := '1'
, aMinLen           int           := 0
, aConst            date          := null
, aMandatory        boolean       := true
, aFormat           varchar2      := FMT_DATE
, aDecoding         boolean       := false
, aConstList        tp_date_table := null
, aNamespace        varchar2      := null
, aDefault          date          := null
, aMinDateValue     date          := null
, aMaxDateValue     date          := null
) return date
is
  fValue     varchar2(32767);
  fValueName varchar2(4000);
begin
  GetValueFromXml(fValue, fValueName, aXML, aElementPath, aAttrName, aIndexOrPredicate, aNamespace, aDecoding);
  return
    GetValueD
    ( fValue, fValueName, aMaxLen, aMinLen, aConst, aMandatory
    , aFormat, aConstList, aDefault, aMinDateValue, aMaxDateValue
    );
end GetValueD;

---------
function GetValueT
( aXML              XMLType
, aElementPath      varchar2
, aAttrName         varchar2      := ''
, aIndexOrPredicate varchar2      := '1'
, aMandatory        boolean       := true
, aNamespace        varchar2      := null
, aDefault          timestamp     := null
) return timestamp
is
  fValue     varchar2(32767);
  fValueName varchar2(4000);
begin
  GetValueFromXml(fValue, fValueName, aXML, aElementPath, aAttrName, aIndexOrPredicate, aNamespace, false);
  return GetValueT(fValue, fValueName, aMandatory, aDefault);
end GetValueT;

---------
function GetValueB
( aXML XMLType
, aElementPath varchar2
, aAttrName varchar2 := ''
, aIndexOrPredicate varchar2 := '1'
, aMandatory boolean := true
, aNamespace varchar2 := null
, aDefault boolean := null
) return boolean
is
  fValue     varchar2(32767);
  fValueName varchar2(4000);
begin
  GetValueFromXml(fValue, fValueName, aXML, aElementPath, aAttrName, aIndexOrPredicate, aNamespace);
  return GetValueB(fValue, fValueName, aMandatory, aDefault);
end GetValueB;

---------
function GetValueF
( aValue            varchar2
, aValueName        varchar2
, aMandatory        boolean := true
, aDefault          number := null
, aMinNumValue      number := null
, aMaxNumValue      number := null
, aPositive         boolean := false
) return number
is
  cDecimalSep varchar2(1) := to_char(.1, 'fmd');
  fValueS varchar2(32767) := Util.Trim(aValue, chr(9)||chr(10)||chr(13)||' ');
  fValueF number;
begin
  if fValueS is null then
    if aDefault is not null then
      fValueF := aDefault;
    elsif aMandatory then
      Util.RaiseErr('%s - должен быть задан', aValueName);
    end if;
  else
    fValueS := translate(fValueS, ',.', cDecimalSep||cDecimalSep);
    fValueF := to_number(fValueS);
    if aPositive and fValueF < 0 then
      Util.RaiseErr('%s - отрицательное значение недопустимо (%d)', aValueName, fValueF);
    end if;
    if fValueF < aMinNumValue or fValueF > aMaxNumValue then
      Util.RaiseErr('%s - допустимый диапазон значений [%d .. %d]', aValueName, aMinNumValue, aMaxNumValue);
    end if;
  end if;
  return fValueF;
exception
  when invalid_number or value_error then
    Util.RaiseErr('%s - недопустимое число (%s)', aValueName, aValue);
end GetValueF;

---------
function GetValueF
( aXML              XMLType
, aElementPath      varchar2
, aAttrName         varchar2 := ''
, aIndexOrPredicate varchar2 := '1'
, aMandatory        boolean := true
, aNamespace        varchar2 := null
, aDefault          number := null
, aMinNumValue      number := null
, aMaxNumValue      number := null
, aPositive         boolean := false
) return number
is
  fValue     varchar2(32767);
  fValueName varchar2(4000);
begin
  GetValueFromXml(fValue, fValueName, aXML, aElementPath, aAttrName, aIndexOrPredicate, aNamespace);
  return GetValueF(fValue, fValueName, aMandatory, aDefault, aMinNumValue, aMaxNumValue, aPositive);
end GetValueF;

---------
function GetValueC
( aXML              XMLType
, aElementPath      varchar2
, aIndexOrPredicate varchar2 := '1'
, aMandatory        boolean := true
, aNamespace        varchar2 := null
) return clob
is
begin
  return case when aXML is not null then
           regexp_replace(aXML.extract(aElementPath || '[' || nvl(aIndexOrPredicate, '1') || ']' || '/text()', aNamespace).getclobval(), '^[[:space:]]*\<\!\[CDATA\[(.*)\]\]\>$', '\1')
         end;
end GetValueC;

--========================================================================================

---------
procedure TestParam
( aValue in out varchar2
, aType varchar2 := 'S'
, aValueName varchar2
, aMaxLen int := gMaxXmlValueLength
, aMinLen int := 0
, aConst varchar2 := null
, aMandatory boolean := true
, aMinNumValue int := null
, aMaxNumValue int := null
, aPositive boolean := true
, aFormat varchar2 := null
, aConstList tp_varchar2_100_table := null
, aDefault varchar2 := null
, aValidChars varchar2 := null
, aHomographToLatin boolean := false
)
is
begin
  case aType
    when 'S' then
      aValue :=
        GetValueS
        ( aValue, aValueName, aMaxLen, aMinLen, aConst, aMandatory
        , aConstList, aDefault, aValidChars, aHomographToLatin
        );
    when 'N' then
      aValue :=
        GetValueN
        ( aValue, aValueName, least(aMaxLen, 38), aMinLen, aConst, aMandatory
        , aMinNumValue, aMaxNumValue, aPositive, aFormat, /*aConstList*/null, aDefault
        );
    when 'D' then
      aValue :=
        to_char
        ( GetValueD
          ( aValue, aValueName, aMaxLen, aMinLen, aConst, aMandatory
          , aFormat, /*aConstList*/null, aDefault
          )
        , FMT_DATE
        );
    when 'B' then
      aValue :=
        case GetValueB(aValue, aValueName, aMandatory, aDefault = 'Y')
          when true  then 'Y'
          when false then 'N'
        end;
    else
      Util.RaiseErr('Неизвестный тип "%s"', aType);
  end case;
  if aConstList is not null and aType <> 'S' then
    aValue := GetValueS(aValue, aValueName, aConstList=>aConstList);
  end if;
end TestParam;

---------
function StrToNum(aValue varchar2, aFormat in varchar2, aValueName varchar2 := null) return number
is
begin
  if aFormat is null then
    return to_number(ltrim(trim(aValue), '+'), '99999999999999999999999999999999999999', NLS_NUM_CHAR);
  else
    return to_number(ltrim(trim(aValue), '+'), aFormat, NLS_NUM_CHAR);
  end if;
exception
  when invalid_number or value_error then
    Util.RaiseErr('%s - недопустимое число (%s)', aValueName, aValue);
end StrToNum;

---------
function StrToDate(aValue varchar2, aFormat in varchar2, aValueName varchar2 := null) return date
is
begin
  return to_date(trim(aValue), nvl(aFormat, 'fx'||FMT_DATE));
exception
  when others then
    if sqlcode between -1899 and -1800 then
      Util.RaiseErr('%s - недопустимая дата (%s)', aValueName, aValue);
    else
      raise;
    end if;
end StrToDate;

---------
procedure FirstLevelSignature
( aMsg in out nocopy XMLType
, aSignatureTagName varchar2 := 'Signature'
, aSalt varchar2 := null
, aCheck boolean := true
, aSeparator varchar2 := '^'
)
is
  fBuff varchar2(32767);
  fSign raw(16);
begin
  Util.CheckErr(aMsg is null, 'aMsg is null');
  Util.CheckErr(aSignatureTagName is null, 'aSignatureTagName is null');

  for cVal in
  ( select extractvalue(column_value, '*') as val
      from table(xmlSequence(aMsg.extract('/*/*[string-length(text())>0 and name()!='''||aSignatureTagName||''' and count(*/node())=0]')))
  ) loop
    fBuff := fBuff || case when fBuff is not null then aSeparator end || cVal.val;
  end loop;
  if aSalt is not null then
    fBuff := fBuff || aSeparator || aSalt;
  end if;

  fSign := dbms_obfuscation_toolkit.md5(input=>utl_raw.cast_to_raw(fBuff));

  if aCheck then
    Util.CheckErr('$'||fSign <> '$'||GetElementValue(aMsg, '/*/'||aSignatureTagName, aDecoding=>false),
      'Неверная подпись сообщения');
  else
    select updatexml(aMsg, '/*/'||aSignatureTagName, '<'||aSignatureTagName||'>'||fSign|| '</'||aSignatureTagName||'>')
      into aMsg from dual;
  end if;
end FirstLevelSignature;

--!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
--!!  Устаревшие

---------
function GetElementAttrValue
( aXML XMLType
, aElementPath varchar2
, aAttrName varchar2
, aMaxLen int := 100
, aIdx varchar2 := '1'
, aType varchar2 := 'S'
, aMinLen int := 0
, aConst varchar2 := null
, aMandatory boolean := true
, aMinNumValue int := null
, aMaxNumValue int := null
, aPositive boolean := true
, aFormat varchar2 := null
, aDecoding boolean := true
, aConstList tp_varchar2_100_table := null
, aNamespace varchar2 := null
, aDefault varchar2 := null
, aValidChars varchar2 := null
, aHomographToLatin boolean := false
) return varchar2
is
  fValue     varchar2(32767);
  fValueName varchar2(4000);
begin
  GetValueFromXml(fValue, fValueName, aXML, aElementPath, aAttrName, aIdx, aNamespace, aDecoding);
  TestParam(fValue, aType, fValueName, aMaxLen, aMinLen, aConst, aMandatory
  , aMinNumValue, aMaxNumValue, aPositive, aFormat, aConstList
  , aDefault, aValidChars, aHomographToLatin
  );
  return fValue;
end GetElementAttrValue;

---------
function GetElementValue
( aXML XMLType
, aElementPath varchar2
, aMaxLen int := gMaxXmlValueLength
, aIdx varchar2 := '1'
, aType varchar2 := 'S'
, aMinLen int := 0
, aConst varchar2 := null
, aMandatory boolean := true
, aMinNumValue int := null
, aMaxNumValue int := null
, aPositive boolean := true
, aFormat varchar2 := null
, aDecoding boolean := true
, aConstList tp_varchar2_100_table := null
, aNamespace varchar2 := null
, aDefault varchar2 := null
, aValidChars varchar2 := null
, aHomographToLatin boolean := false
) return varchar2
is
  fValue     varchar2(32767);
  fValueName varchar2(4000);
begin
  GetValueFromXml(fValue, fValueName, aXML, aElementPath, '', aIdx, aNamespace, aDecoding);
  TestParam(fValue, aType, fValueName, aMaxLen, aMinLen, aConst, aMandatory
  , aMinNumValue, aMaxNumValue, aPositive, aFormat, aConstList
  , aDefault, aValidChars, aHomographToLatin
  );
  return fValue;
end GetElementValue;

---------
function GetElementValueD
( aXML XMLType
, aElementPath varchar2
, aMaxLen int := gMaxXmlValueLength
, aIdx varchar2 := '1'
, aMinLen int := 0
, aConst varchar2 := null
, aMandatory boolean := true
, aFormat varchar2 := null
, aDecoding boolean := false
, aNamespace varchar2 := null
) return date
is
begin
  return GetValueD(aXML, aElementPath, '', aMaxLen, aIdx, aMinLen, aConst, aMandatory,
    aFormat=>aFormat, aDecoding=>aDecoding, aNamespace=>aNamespace);
end GetElementValueD;

---------
end xml_Util;
/
show error

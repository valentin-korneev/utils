prompt create or replace package body UtilLob

create or replace package body UtilLob
is

Pn1$ constant varchar2(30) := 'UtilLob';

--------
type TCRCTable                  is varray(256) of integer not null;
gCRC8_Polynom                   int;
gCRC8_Table                     TCRCTable;
gCRC16_Polynom                  int;
gCRC16_Table                    TCRCTable;

--------
type TBlobCache is record ( data_blob       blob
                          , charset         varchar2(255)
                          , nls_charset_id  int
                          , data_length     int
                          , data_raw        raw(32767)
                          , cache_from      int
                          , cache_to        int
                          , endian          int
                          );
--------
gNlsCharSet   varchar2(100);
gData         blob;
gTmpRaw       raw(32767);
gTmpRawLenth  int;
gReadData     TBlobCache;

--------
function ZLibDecompress(aBlob blob) return blob
is
  fOut     blob;
  fTmp     blob;
  fTmpRaw  raw(32767);
  fBuffer  raw(1);
  fHdl     binary_integer;
  fS1      pls_integer;
  fLastChr pls_integer;
  --
  procedure OutBlobAppend(aBuffer raw, aLast boolean := false)
  is
  begin
    if aLast or nvl(utl_raw.length(fTmpRaw), 0) + nvl(utl_raw.length(aBuffer), 0) > 32767 then
      dbms_lob.append(fOut, fTmpRaw);
      if aLast then
        dbms_lob.append(fOut, aBuffer);
      else
        fTmpRaw := aBuffer;
      end if;
    else
      fTmpRaw := utl_raw.concat(fTmpRaw, aBuffer);
    end if;
  end OutBlobAppend;
begin
  dbms_lob.createtemporary(fOut , false);
  dbms_lob.createtemporary(fTmp, false);
  fTmp := hextoraw('1F8B0800000000000003');
  dbms_lob.copy(fTmp, aBlob, dbms_lob.getlength(aBlob) - 2 - 4, 11, 3);
  dbms_lob.append(fTmp, hextoraw('0000000000000000'));
  fHdl := utl_compress.lz_uncompress_open(fTmp);
  fS1  := 1;
  loop
    begin
      utl_compress.lz_uncompress_extract(fHdl, fBuffer);
    exception
      when others then
        exit;
    end;
    OutBlobAppend(fBuffer);
    fS1 := mod(fS1 + to_number(rawtohex(fBuffer), 'xx'), 65521);
  end loop;
  fLastChr := to_number(dbms_lob.substr(aBlob, 2, dbms_lob.getlength(aBlob) - 1 ), '0XXX') - fS1;
  if fLastChr < 0 then
    fLastChr := fLastChr + 65521;
  end if;
  OutBlobAppend(hextoraw(to_char(fLastChr, 'fm0X')), aLast => true);
  if utl_compress.isopen(fHdl) then
    utl_compress.lz_uncompress_close(fHdl);
  end if;
  dbms_lob.freetemporary(fTmp);
  return fOut;
end ZLibDecompress;

--------
function Base64Encode(aBlob blob) return clob
is
  fClob    clob;
  fResult  clob;
  fOffset  int := 1;
  fBufferS binary_integer := (48 / 4) * 3;
  fBufferV varchar2(48);
  fBufferR raw(48);
begin
  dbms_lob.createtemporary(fClob, true);
  for i in 1..ceil(dbms_lob.getlength(aBlob) / fBufferS) loop
    dbms_lob.read(aBlob, fBufferS, fOffset, fBufferR);
    fBufferV := utl_raw.cast_to_varchar2(utl_encode.base64_encode(fBufferR));
    dbms_lob.writeappend(fClob, length(fBufferV), fBufferV);
    fOffset := fOffset + fBufferS;
  end loop;
  fResult := fClob;
  dbms_lob.freetemporary(fClob);
  return fResult;
end Base64Encode;

--------
function Base64Decode(aClob clob) return blob
is
  fBlob    blob;
  fResult  blob;
  fOffset  int := 1;
  fBufferS binary_integer := 48;
  fBufferV varchar2(48);
  fBufferR raw(48);
begin
  dbms_lob.createtemporary(fBlob, true);
  for i in 1..ceil(dbms_lob.getlength(aClob) / fBufferS) loop
    dbms_lob.read(aClob, fBufferS, fOffset, fBufferV);
    fBufferR := utl_encode.base64_decode(utl_raw.cast_to_raw(fBufferV));
    dbms_lob.writeappend(fBlob, utl_raw.length(fBufferR), fBufferR);
    fOffset := fOffset + fBufferS;
  end loop;
  fResult := fBlob;
  dbms_lob.freetemporary(fBlob);
  return fResult;
end Base64Decode;

--------
procedure WriteBlobInit(aCharSet varchar2 := null)
is
begin
  if gData is null then
    dbms_lob.createtemporary(gData, true);
  else
    dbms_lob.trim(gData, 0);
  end if;
  gNlsCharSet  := nvl(aCharSet, Util.DBCharset);
  gTmpRawLenth := 0;
end WriteBlobInit;

--------
procedure CheckBin(aIsNull boolean)
is
begin
  Util.CheckErr(gData is null, 'Run only after "Init"');
  Util.CheckErr(aIsNull      , 'value must be set');
end CheckBin;

--------
procedure FlushRaw
is
begin
  if gTmpRawLenth > 0 then
    dbms_lob.writeappend(gData, gTmpRawLenth, gTmpRaw);
    gTmpRaw      := null;
    gTmpRawLenth := 0;
  end if;
end FlushRaw;

--------
procedure WriteBlobBlob(aBlob blob, aFrom int := null)
is
  fBytes int := nvl(dbms_lob.getlength(aBlob), 0);
  fFrom int;
begin
  if fBytes > 0 then
    FlushRaw;
    fFrom := nvl(aFrom, dbms_lob.getlength(gData) + 1);
    dbms_lob.copy(gData, aBlob, fBytes, fFrom, 1);
  end if;
end WriteBlobBlob;

--------
procedure WriteBlob(aRaw raw, aFrom int := null)
is
  fBytes int := nvl(utl_raw.length(aRaw), 0);
begin
  if fBytes > 0 then
    if aFrom is not null then
      FlushRaw;
      if aFrom < dbms_lob.getlength(gData) then
        dbms_lob.write(gData, fBytes, aFrom, aRaw);
        return;
      end if;
    end if;
    if fBytes + gTmpRawLenth > 32767 then
      FlushRaw;
      gTmpRaw      := aRaw;
      gTmpRawLenth := fBytes;
    else
      gTmpRaw      := utl_raw.concat(gTmpRaw, aRaw);
      gTmpRawLenth := gTmpRawLenth + fBytes;
    end if;
  end if;
end WriteBlob;

--------
procedure WriteBlobR(aValue raw, aFrom int := null)
is
begin
  CheckBin(aValue is null);
  WriteBlob(aValue, aFrom);
end WriteBlobR;


----
procedure WriteBlobI(aValue int, aBytes int, aFrom int := null, aSigned boolean := false)
is
  fValue   varchar2(40);
  fReverse varchar2(40);
begin
  CheckBin(aValue is null);
  Util.CheckErr(aValue < 0 and not aSigned, 'value must be greater than zero');
  fValue := to_char( case
                       when aValue < 0
                         then aValue + 256 ** aBytes
                       else aValue
                     end
                   , 'fm' || lpad('X', aBytes * 2, '0')
                   );
  for i in reverse 0 .. trunc(length(fValue) / 2) - 1 loop
    fReverse := fReverse || substr(fValue, 1 + 2 * i, 2);
  end loop;
  WriteBlob(hextoraw(fReverse), aFrom);
end WriteBlobI;

----
procedure WriteBlobF(aValue number, aFrom int := null)
is
begin
  CheckBin(aValue is null);
  WriteBlob(utl_raw.cast_from_binary_float(aValue, utl_raw.little_endian), aFrom);
end WriteBlobF;

----
procedure WriteBlobD(aValue number, aFrom int := null)
is
begin
  CheckBin(aValue is null);
  WriteBlob(utl_raw.cast_from_binary_double(aValue, utl_raw.little_endian), aFrom);
end WriteBlobD;

----
procedure WriteBlobS(aValue varchar2, aBytes int, aFrom int := null, aCharSet varchar2 := null, aFillChar varchar2 := ' ')
is
begin
  CheckBin(false);
  Util.CheckErr(aBytes > 32767, 'Big length');
  WriteBlob
  ( utl_i18n.string_to_raw(rpad(nvl(aValue, aFillChar), aBytes, nvl(aFillChar, chr(0))), dst_charset=>coalesce(aCharSet, gNlsCharSet, Util.DBCharset))
  , aFrom
  );
end WriteBlobS;

----
procedure WriteBlobDDos(aValue date, aFrom int := null)
is
  fDosDate int;
  fDosTime int;
begin
  CheckBin(false);
  Util.Date2Dos(aValue, fDosDate, fDosTime);
  WriteBlobI(fDosTime, 2, aFrom);
  WriteBlobI(fDosDate, 2, aFrom + 2);
end WriteBlobDDos;

----
procedure WriteBlobDDelphi(aValue date)
is
begin
  CheckBin(aValue is null);
  WriteBlobR(utl_raw.cast_from_binary_double(Util.Date2Delphi(aValue), utl_raw.little_endian));
end WriteBlobDDelphi;

---------
function WriteBlobGet(aFlush boolean := true) return blob
is
  fResult blob;
begin
  FlushRaw;
  fResult := gData;
  if aFlush then
    gData := null;
  end if;
  return fResult;
end WriteBlobGet;

---------
function WriteBlobGet(aFrom int, aTo int := null) return blob
is
begin
  FlushRaw;
  return dbms_lob.substr(gData, nvl(aTo, dbms_lob.getlength(gData)) - aFrom + 1, aFrom);
end WriteBlobGet;

---------
function WriteBlobCRC(aFrom int := null, aTo int := null) return int
is
  fCRCData      blob;
begin
  CheckBin(false);
  FlushRaw;
  dbms_lob.createtemporary(fCRCData, true);
  dbms_lob.copy(fCRCData, gData, nvl(aTo, dbms_lob.getlength(gData)), 1, nvl(aFrom, 1));
  return CRC32(fCRCData, aWithoutEndXor=>true);
end WriteBlobCRC;

---------
function WriteBlobLength return int
is

begin
  FlushRaw;
  return case when gData is not null then dbms_lob.getlength(gData) else 0 end;
end WriteBlobLength;

---------
procedure Clob2Blob(aClob clob, aBlob out nocopy blob, aCharSet varchar2 := 'CL8MSWIN1251')
is
  fDstOffset    int := 1;
  fSrcOffset    int := 1;
  fLangContext  int := dbms_lob.DEFAULT_LANG_CTX;
  fWarning      int;
  fNlsCharsetId int := gReadData.nls_charset_id;
begin
  if aCharSet <> nvl(gReadData.charset, '$') then
    fNlsCharsetId := nls_charset_id(aCharSet);
  end if;
  dbms_lob.createtemporary(aBlob, true);
  if aClob is not null then
    dbms_lob.converttoblob
    ( dest_lob     => aBlob
    , src_clob     => aClob
    , amount       => dbms_lob.LOBMAXSIZE
    , dest_offset  => fDstOffset
    , src_offset   => fSrcOffset
    , blob_csid    => fNlsCharsetId
    , lang_context => fLangContext
    , warning      => fWarning
    );
  end if;
end Clob2Blob;

---------
function Clob2Blob(aClob clob, aCharSet varchar2 := 'CL8MSWIN1251') return blob
is
  fBlob blob;
begin
  Clob2Blob(aClob, fBlob, aCharSet);
  return fBlob;
end Clob2Blob;

---------
procedure Blob2Clob(aBlob blob, aClob out nocopy clob, aCharSet varchar2 := 'CL8MSWIN1251')
is
  fDstOffset    int := 1;
  fSrcOffset    int := 1;
  fLangContext  int := dbms_lob.DEFAULT_LANG_CTX;
  fWarning      int;
  fNlsCharsetId int := gReadData.nls_charset_id;
begin
  if aCharSet <> nvl(gReadData.charset, '$') then
    fNlsCharsetId := nls_charset_id(aCharSet);
  end if;
  dbms_lob.createtemporary(aClob, true);
  if aCharSet = 'AL32UTF8' then
    if dbms_lob.getlength(aBlob) > 2 then
      if utl_raw.compare(dbms_lob.substr(aBlob, 3), hextoraw('EFBBBF') /*B(yte) O(rder) M(ark)*/) = 0 then
        fSrcOffset := fSrcOffset + 3;
      end if;
    end if;
  end if;
  if aBlob is not null then
    dbms_lob.converttoclob
    ( dest_lob     => aClob
    , src_blob     => aBlob
    , amount       => dbms_lob.LOBMAXSIZE
    , dest_offset  => fDstOffset
    , src_offset   => fSrcOffset
    , blob_csid    => fNlsCharsetId
    , lang_context => fLangContext
    , warning      => fWarning
    );
  end if;
end Blob2Clob;

---------
function Blob2Clob(aBlob blob, aCharSet varchar2 := 'CL8MSWIN1251') return clob
is
  fClob clob;
begin
  Blob2Clob(aBlob, fClob, aCharSet);
  return fClob;
end Blob2Clob;

---------
procedure ReadBlobInit(aData blob, aCharSet varchar2 := null, aEndian int := utl_raw.little_endian)
is
begin
  if gReadData.data_blob is null then
    dbms_lob.createtemporary(gReadData.data_blob, true);
  end if;

  gReadData.data_length    := dbms_lob.getlength(aData);
  dbms_lob.copy(gReadData.data_blob, aData, gReadData.data_length);

  gReadData.cache_from     := 0;
  gReadData.cache_to       := 0;
  gReadData.data_raw       := null;

  gReadData.charset        := nvl(aCharSet, Util.DBCharset);
  gReadData.nls_charset_id := nls_charset_id(gReadData.charset);
  gReadData.endian         := aEndian;
end ReadBlobInit;

function ReadBlobBlob(aOffSet int, aBytes int) return blob
is
  Pn2$    varchar2(30) := 'ReadBlobBlob';
  fData   blob;
  fBytes  int;
begin
  Util.CheckErr(gReadData.data_blob is null, 'Run only after "Init"');
  dbms_lob.createtemporary(fData, true);
  if aOffSet <= gReadData.data_length then
    gReadData.cache_from     := 0;
    gReadData.cache_to       := 0;
    gReadData.data_raw       := null;
    fBytes := least(gReadData.data_length - aOffSet + 1, aBytes);
    dbms_lob.copy(fData, gReadData.data_blob, fBytes, 1, aOffSet);
  end if;
  return fData;
exception
  when others then
    LogWork.NotifyException(Pn1$, Pn2$);
    raise;
end ReadBlobBlob;

function ReadBlobR(aOffSet int, aBytes int) return raw
is
  Pn2$    varchar2(30) := 'BinR';
  fData   raw(32767);
  fEndPos int := aOffSet + aBytes - 1;
  fBytes  int;
begin
  Util.CheckErr(gReadData.data_blob is null, 'Run only after "Init"');
  Util.CheckErr(aBytes > 32767             , 'Big length');

  if aOffSet <= gReadData.data_length then
    if    aOffSet not between gReadData.cache_from and gReadData.cache_to
       or (     fEndPos not between gReadData.cache_from and gReadData.cache_to
            and fEndPos <= gReadData.data_length
          )
    then
      fBytes := least(gReadData.data_length - aOffSet + 1, 32767);
      gReadData.data_raw   := dbms_lob.substr(gReadData.data_blob, fBytes, aOffSet);
      gReadData.cache_from := aOffSet;
      gReadData.cache_to   := aOffSet + fBytes - 1;
    end if;

    fData := utl_raw.substr(gReadData.data_raw, aOffSet - gReadData.cache_from + 1, aBytes);
  end if;
  return fData;
exception
  when others then
    LogWork.NotifyException(Pn1$, Pn2$);
    raise;
end ReadBlobR;

---------
function ReadBlobI(aOffSet int, aBytes int, aSigned boolean := false, aEndian int := null) return int
is
  Pn2$ varchar2(30) := 'BinI';
  fResult  int;
begin
  Util.CheckErr(aBytes not between 1 and 4, 'Bad "aBytes"');

  fResult := utl_raw.cast_to_binary_integer(ReadBlobR(aOffSet, aBytes), nvl(aEndian, gReadData.endian));

  if aBytes = 4 then
     if not aSigned and fResult < 0 then
       fResult := fResult + 256 ** aBytes;
     end if;
  else
    if aSigned and fResult >= 256 ** aBytes / 2 then
      fResult := fResult - 256 ** aBytes;
    end if;
  end if;
  return fResult;
exception
  when others then
    LogWork.NotifyException(Pn1$, Pn2$);
    raise;
end ReadBlobI;

---------
function ReadBlobS(aOffSet int, aBytes int, aCharSet varchar2 := null) return varchar2
is
  fDst       clob;
  fSrcOffset int := 1;
begin
  fDst := Blob2Clob( ReadBlobR(aOffSet, aBytes)
                   , coalesce(aCharSet, gReadData.charset, Util.DBCharset)
                   );

  fSrcOffset := dbms_lob.instr(fDst, chr(0));
  if fSrcOffset > 0 then
    fDst := dbms_lob.substr(fDst, fSrcOffset - 1);
  end if;

  return trim(fDst);
end ReadBlobS;

---------
function ReadBlobD(aOffSet int) return number
is
begin
  return utl_raw.cast_to_binary_double(ReadBlobR(aOffSet, 8), gReadData.endian);
end ReadBlobD;

---------
function ReadBlobDDos(aOffSet int, aZeroAsNull boolean := false) return date
is
  fTimeInt int;
  fDateInt int;
begin
  if gReadData.endian = utl_raw.little_endian then
    fTimeInt := ReadBlobI(aOffSet,     2);
    fDateInt := ReadBlobI(aOffSet + 2, 2);
  else
    fDateInt := ReadBlobI(aOffSet,     2);
    fTimeInt := ReadBlobI(aOffSet + 2, 2);
  end if;
  if aZeroAsNull and fDateInt = 0 and fTimeInt = 0 then
    return null;
  else
    return Util.Dos2Date(fDateInt, fTimeInt);
  end if;
end ReadBlobDDos;

---------
function ReadBlobDDelphi(aOffSet int) return date
is
begin
  return Util.Delphi2Date(ReadBlobD(aOffSet));
end ReadBlobDDelphi;

---------
function ReadBlobRDelphi(aOffSet int) return number
is
begin
  return DelphiReal2Number(ReadBlobR(aOffSet, 6), aNeedReverse=>true);
end ReadBlobRDelphi;

---------
function ReadBlobGet(aOffSet int, aBytes int) return blob
is
  fResult blob;
begin
  Util.CheckErr(gReadData.data_blob is null, 'Run only after "Init"');
  dbms_lob.createtemporary(fResult, true);
  dbms_lob.copy(fResult, gReadData.data_blob, aBytes, 1, aOffSet);
  return fResult;
end ReadBlobGet;

---------
function ReadBlobLength return int
is
begin
  return gReadData.data_length;
end ReadBlobLength;

--------
function ReadBlobCRC8
( aOffSet     int
, aBytes      int
, aPolynom    int     := 49
, aInitVector integer := 255
, aRefIn      boolean := false
) return int
is
begin
  return
    CRC8
    ( ReadBlobGet(aOffSet, aBytes)
    , aPolynom    => aPolynom
    , aInitVector => aInitVector
    , aRefIn      => aRefIn
    );
end ReadBlobCRC8;

---------
function ReadBlobCRC16
( aOffSet     int
, aBytes      int
, aPolynom    int     := 4129
, aInitVector integer := 65535
, aRefIn      boolean := false
, aRefOut     boolean := false
) return int
is
begin
  return
    CRC16
    ( ReadBlobGet(aOffSet, aBytes)
    , aPolynom    => aPolynom
    , aInitVector => aInitVector
    , aRefIn      => aRefIn
    , aRefOut     => aRefOut
    );
end ReadBlobCRC16;

---------
function ReadBlobCRC32
( aOffSet         int
, aBytes          int
, aInitVector     integer := null
, aWithoutEndXor  boolean := false
) return int
is
begin
  return
    CRC32
    ( ReadBlobGet(aOffSet, aBytes)
    , aInitVector    => aInitVector
    , aWithoutEndXor => aWithoutEndXor
    );
end ReadBlobCRC32;


-------
procedure Blob2TRawArr(aBlob blob, aRawArr in out nocopy TRawArr)
is
  fStr          raw(32767);
  fPartLength   int := 32767;
  fClobLength   int;
begin
  fClobLength := nvl(dbms_lob.getlength(aBlob), 0);
  fPartLength := trunc((fPartLength / 2) / dbms_lob.getchunksize(aBlob)) * dbms_lob.getchunksize(aBlob);
  Util.CheckErr(fClobLength > 1073741824, 'Ôאיכ םו למזוע בûעü במכüרו 1Gb');
  if fClobLength > 0 then
    for i in 1 .. ceil(fClobLength / fPartLength) loop
      fStr := dbms_lob.substr(aBlob, fPartLength, (i - 1) * fPartLength + 1);
      aRawArr(aRawArr.count + 1) := fStr;
    end loop;
    if aRawArr(aRawArr.last) is null then
      aRawArr.delete(aRawArr.last);
    end if;
  end if;
end Blob2TRawArr;

-------
function Blob2TRawArr(aBlob blob) return TRawArr
is
  fResult TRawArr;
begin
  Blob2TRawArr(aBlob, fResult);
  return fResult;
end Blob2TRawArr;

---------
procedure TRawArr2Blob(aRawArr TRawArr, aBlob in out nocopy blob)
is
  fLen int;
  fIdx int;
begin
  if aBlob is null then
    dbms_lob.createtemporary(aBlob, true);
  end if;
  fIdx := aRawArr.first;
  while fIdx is not null loop
    fLen :=  dbms_lob.getlength(aRawArr(fIdx));
    dbms_lob.append(aBlob, aRawArr(fIdx));
    fIdx := aRawArr.next(fIdx);
  end loop;
end TRawArr2Blob;

---------
function TRawArr2Blob(aRawArr TRawArr) return blob
is
  fResult blob;
begin
  TRawArr2Blob(aRawArr, fResult);
  return fResult;
end TRawArr2Blob;

---------
function DelphiReal2Number(aReal raw, aNeedReverse boolean := false) return number
is
  fData raw(6);
  fResult number;
  fExponent int;
begin
  if aReal is null or utl_raw.length(aReal) <> 6 then
    Util.RaiseErr('Bad real');
  end if;
  fData := aReal;
  if aNeedReverse then
    fData := utl_raw.reverse(aReal);
  end if;

  fExponent := utl_raw.cast_to_binary_integer(utl_raw.substr(fData, 6, 1));
  if fExponent <> 0 then
    fExponent := fExponent - 129;
    fResult := 1
             + 2 * ( bitand(utl_raw.cast_to_binary_integer(utl_raw.substr(fData, 1, 1)), 127)
                   + ( utl_raw.cast_to_binary_integer(utl_raw.substr(fData, 2, 1))
                     + ( utl_raw.cast_to_binary_integer(utl_raw.substr(fData, 3, 1))
                       + ( utl_raw.cast_to_binary_integer(utl_raw.substr(fData, 4, 1))
                         + utl_raw.cast_to_binary_integer(utl_raw.substr(fData, 5, 1)) / 256
                         ) / 256
                       ) / 256
                     ) / 256
                   ) / 256;

    if bitand(utl_raw.cast_to_binary_integer(utl_raw.substr(fData, 1, 1)), 128) > 0 then
      fResult := -1 * fResult;
    end if;
    return 2**fExponent * fResult;
  else
    return 0;
  end if;
end DelphiReal2Number;

---------
function CRC8(aData blob, aPolynom int := 49, aInitVector integer := 255, aRefIn boolean := false) return integer
is
  fCRC    integer;
  fAmt    number := 32767;
  fOffset number := 1;
  fRaw    raw(32767);
  fLength int;
begin
  if aData is not null then
    if gCRC8_Polynom is null or gCRC8_Polynom <> aPolynom * case when aRefIn then 1 else -1 end then
      if aPolynom not between 1 and 255 then
        Util.RaiseErr('Bad polynom');
      end if;
      if gCRC8_Table is null then
        gCRC8_Table := TCRCTable();
        gCRC8_Table.extend(256);
      end if;

      for i in 0 .. 255 loop
        gCRC8_Table(i+1) := i;
        for j in 1..8 loop
          if aRefIn then
            if bitand(gCRC8_Table(i+1), 1) = 0 then
              gCRC8_Table(i+1) := trunc(gCRC8_Table(i+1)/2);
            else
              gCRC8_Table(i+1) := Util.BitXor(trunc(gCRC8_Table(i+1)/2), aPolynom);
            end if;
          else
            if bitand(gCRC8_Table(i+1), 128) = 0 then
              gCRC8_Table(i+1) := bitand(gCRC8_Table(i+1), 127) * 2;
            else
              gCRC8_Table(i+1) := Util.BitXor(bitand(gCRC8_Table(i+1), 127) * 2, aPolynom);
            end if;
          end if;
        end loop;
      end loop;
      gCRC8_Polynom := aPolynom * case when aRefIn then 1 else -1 end;
    end if;

    fLength := dbms_lob.getlength(aData);
    fCRC := aInitVector;
    while fOffset <= fLength loop
      dbms_lob.read(aData, fAmt, fOffset, fRaw);
      fOffset := fOffset + fAmt;
      for i in 1..fAmt loop
        fCRC := gCRC8_Table(Util.BitXor(fCRC, utl_raw.cast_to_binary_integer(utl_raw.substr(fRaw, i, 1))) + 1);
      end loop;
    end loop;
  end if;
  return fCRC;
end CRC8;

---------
function CRC16(aData blob, aPolynom int := 4129, aInitVector integer := 65535, aRefIn boolean := false, aRefOut boolean := false) return integer
is
  fPolynom int := aPolynom;
  fCRC    integer;
  fAmt    number := 32767;
  fOffset number := 1;
  fRaw    raw(32767);
  fLength int;
begin
  if aData is not null then
    if gCRC16_Polynom is null or gCRC16_Polynom <> aPolynom * case when aRefIn then 1 else -1 end then
      Util.CheckErr(aPolynom not between 1 and 65535, 'Bad polynom');
      if gCRC16_Table is null then
        gCRC16_Table := TCRCTable();
        gCRC16_Table.extend(256);
      end if;

      if aRefOut then
        fPolynom := Util.BitReverse(fPolynom, 16);
      end if;

      for i in 0 .. 255 loop
        if aRefIn then
          gCRC16_Table(i+1) := i;
        else
          gCRC16_Table(i+1) := i * 256;
        end if;

        for j in 1..8 loop
          if aRefIn then
            if bitand(gCRC16_Table(i+1), 1) = 0 then
              gCRC16_Table(i+1) := trunc(gCRC16_Table(i+1)/2);
            else
              gCRC16_Table(i+1) := Util.BitXor(trunc(gCRC16_Table(i+1)/2), fPolynom);
            end if;
          else
            if bitand(gCRC16_Table(i+1), 32768) = 0 then
              gCRC16_Table(i+1) := bitand(gCRC16_Table(i+1), 32767) * 2;
            else
              gCRC16_Table(i+1) := Util.BitXor(bitand(gCRC16_Table(i+1), 32767) * 2, fPolynom);
            end if;
          end if;
        end loop;
      end loop;
      gCRC16_Polynom := aPolynom * case when aRefIn then 1 else -1 end;
    end if;

    fLength := dbms_lob.getlength(aData);
    fCRC :=  aInitVector;
    while fOffset <= fLength loop
      dbms_lob.read(aData, fAmt, fOffset, fRaw);
      fOffset := fOffset + fAmt;
      for i in 1..fAmt loop
        if aRefIn then
          fCRC :=
            Util.BitXor
            ( trunc(fCRC/256)
            , gCRC16_Table(bitand(Util.BitXor(fCRC, utl_raw.cast_to_binary_integer(utl_raw.substr(fRaw, i, 1))), 255) + 1)
            );
        else
          fCRC :=
            Util.BitXor
            ( bitand(fCRC, 255) * 256
            , gCRC16_Table(Util.BitXor(trunc(fCRC/256), utl_raw.cast_to_binary_integer(utl_raw.substr(fRaw, i, 1))) + 1)
            );
        end if;
      end loop;
    end loop;
  end if;
  return fCRC;
end CRC16;

---------
function CRC32(aData blob, aInitVector integer := null, aWithoutEndXor boolean := false) return integer
is
  CRC32_Table constant TCRCTable := TCRCTable
  ( 0000000000, 1996959894, 3993919788, 2567524794, 0124634137, 1886057615, 3915621685, 2657392035
  , 0249268274, 2044508324, 3772115230, 2547177864, 0162941995, 2125561021, 3887607047, 2428444049
  , 0498536548, 1789927666, 4089016648, 2227061214, 0450548861, 1843258603, 4107580753, 2211677639
  , 0325883990, 1684777152, 4251122042, 2321926636, 0335633487, 1661365465, 4195302755, 2366115317
  , 0997073096, 1281953886, 3579855332, 2724688242, 1006888145, 1258607687, 3524101629, 2768942443
  , 0901097722, 1119000684, 3686517206, 2898065728, 0853044451, 1172266101, 3705015759, 2882616665
  , 0651767980, 1373503546, 3369554304, 3218104598, 0565507253, 1454621731, 3485111705, 3099436303
  , 0671266974, 1594198024, 3322730930, 2970347812, 0795835527, 1483230225, 3244367275, 3060149565
  , 1994146192, 0031158534, 2563907772, 4023717930, 1907459465, 0112637215, 2680153253, 3904427059
  , 2013776290, 0251722036, 2517215374, 3775830040, 2137656763, 0141376813, 2439277719, 3865271297
  , 1802195444, 0476864866, 2238001368, 4066508878, 1812370925, 0453092731, 2181625025, 4111451223
  , 1706088902, 0314042704, 2344532202, 4240017532, 1658658271, 0366619977, 2362670323, 4224994405
  , 1303535960, 0984961486, 2747007092, 3569037538, 1256170817, 1037604311, 2765210733, 3554079995
  , 1131014506, 0879679996, 2909243462, 3663771856, 1141124467, 0855842277, 2852801631, 3708648649
  , 1342533948, 0654459306, 3188396048, 3373015174, 1466479909, 0544179635, 3110523913, 3462522015
  , 1591671054, 0702138776, 2966460450, 3352799412, 1504918807, 0783551873, 3082640443, 3233442989
  , 3988292384, 2596254646, 0062317068, 1957810842, 3939845945, 2647816111, 0081470997, 1943803523
  , 3814918930, 2489596804, 0225274430, 2053790376, 3826175755, 2466906013, 0167816743, 2097651377
  , 4027552580, 2265490386, 0503444072, 1762050814, 4150417245, 2154129355, 0426522225, 1852507879
  , 4275313526, 2312317920, 0282753626, 1742555852, 4189708143, 2394877945, 0397917763, 1622183637
  , 3604390888, 2714866558, 0953729732, 1340076626, 3518719985, 2797360999, 1068828381, 1219638859
  , 3624741850, 2936675148, 0906185462, 1090812512, 3747672003, 2825379669, 0829329135, 1181335161
  , 3412177804, 3160834842, 0628085408, 1382605366, 3423369109, 3138078467, 0570562233, 1426400815
  , 3317316542, 2998733608, 0733239954, 1555261956, 3268935591, 3050360625, 0752459403, 1541320221
  , 2607071920, 3965973030, 1969922972, 0040735498, 2617837225, 3943577151, 1913087877, 0083908371
  , 2512341634, 3803740692, 2075208622, 0213261112, 2463272603, 3855990285, 2094854071, 0198958881
  , 2262029012, 4057260610, 1759359992, 0534414190, 2176718541, 4139329115, 1873836001, 0414664567
  , 2282248934, 4279200368, 1711684554, 0285281116, 2405801727, 4167216745, 1634467795, 0376229701
  , 2685067896, 3608007406, 1308918612, 0956543938, 2808555105, 3495958263, 1231636301, 1047427035
  , 2932959818, 3654703836, 1088359270, 0936918000, 2847714899, 3736837829, 1202900863, 0817233897
  , 3183342108, 3401237130, 1404277552, 0615818150, 3134207493, 3453421203, 1423857449, 0601450431
  , 3009837614, 3294710456, 1567103746, 0711928724, 3020668471, 3272380065, 1510334235, 0755167117
  );

  fCRC    integer;
  fAmt    number := 32767;
  fOffset number := 1;
  fRaw    raw(32767);
  fLength int;
begin
  if aData is not null then
    fLength := dbms_lob.getlength(aData);
    fCRC := 4294967295 /*xFFFFFFFF*/;
    Util.BitClear(fCRC, nvl(aInitVector, 0));
    while fOffset <= fLength loop
      dbms_lob.read(aData, fAmt, fOffset, fRaw);
      fOffset := fOffset + fAmt;
      for i in 1..fAmt loop
        fCRC :=
          Util.BitXor
          ( trunc(fCRC/256)
          , CRC32_Table(bitand(Util.BitXor(fCRC, utl_raw.cast_to_binary_integer(utl_raw.substr(fRaw, i, 1))), 255) + 1)
          );
      end loop;
    end loop;
  end if;
  return case when aWithoutEndXor then fCRC else Util.BitXor(4294967295, fCRC) end;
end CRC32;

--------
end UtilLob;
/
show error

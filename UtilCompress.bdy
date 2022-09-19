prompt create or replace package body UtilCompress

create or replace package body UtilCompress
as

Pn1$ constant varchar2(30) := 'UtilCompress';

---------
procedure Unzip(aCompressedFile TFile, aDecompressedFile out TFile)
is
  Pn2$                          constant varchar2(30) := 'Unzip';
  ---
  fEOCDPosition                          int;
  fSOCDPosition                          int;
  fSOLFPosition                          int;
  ---
  COMPRESSION_METHOD$COMPRESSED constant raw(4) := '0800';
  COMPRESSION_METHOD$AS_IS      constant raw(4) := '0000';
  GZIP_HEADER                   constant raw(20) := '1F8B0800000000000003';
  ---
  fCDCount                               int;
  fFileNameLength                        int;
  fExtractedFile                         blob;
  fCompressionMethod                     raw(4);
  ---
  function GetEOCDPosition return int
  is
    EOCD_SIGNATURE constant raw(8) := '504B0506'; -- End of central directory signature = 0x06054b50
  begin
    for i in reverse 1 .. UtilLob.ReadBlobLength - (20 + 1) loop
      if UtilLob.ReadBlobR(i, 4) = EOCD_SIGNATURE then
        return i;
      end if;
    end loop;
    Util.RaiseErr('Файл не является ZIP архивом');
  end GetEOCDPosition;
begin
  LogWork.Notify(Pn1$, Pn2$, '-=>');
  UtilLob.ReadBlobInit(aCompressedFile.content);
  fEOCDPosition := GetEOCDPosition;
  fSOCDPosition := UtilLob.ReadBlobI(fEOCDPosition + 16, 4) + 1;
  fCDCount := UtilLob.ReadBlobI(fEOCDPosition + 8, 2);
  Util.CheckErr
    ( fCDCount > 1
    , 'Архив содержит более одного файла'
    );
  Util.CheckErr
    ( fCDCount = 0
    , 'Архив не содержит файлов'
    );
  fSOLFPosition := UtilLob.ReadBlobI(fSOCDPosition + 42, 4) + 1;
  fFileNameLength := UtilLob.ReadBlobI(fSOLFPosition + 26, 2);
  aDecompressedFile.filename := UtilLob.ReadBlobS(fSOLFPosition + 30, fFileNameLength);
  UtilLob.WriteBlobInit;
  UtilLob.WriteBlobBlob
    ( UtilLob.ReadBlobBlob
        ( fSOLFPosition 
        + 30 -- Before file name 
        + fFileNameLength
        + UtilLob.ReadBlobI(fSOLFPosition + 28, 2) -- Extra field length
        , UtilLob.ReadBlobI(fSOLFPosition + 18, 4) -- Compressed file size
        )
    , UtilLob.WriteBlobLength + 1
    );
  fExtractedFile := UtilLob.WriteBlobGet;
  fCompressionMethod := UtilLob.ReadBlobR(fSOCDPosition + 10, 2);
  if fCompressionMethod = COMPRESSION_METHOD$COMPRESSED then    
    UtilLob.WriteBlobInit;
    UtilLob.WriteBlobR(GZIP_HEADER, 1);
    UtilLob.WriteBlobBlob(fExtractedFile, UtilLob.WriteBlobLength + 1);
    UtilLob.WriteBlobR(UtilLob.ReadBlobR(fSOLFPosition + 14, 4), UtilLob.WriteBlobLength + 1); -- CRC
    UtilLob.WriteBlobR(UtilLob.ReadBlobR(fSOLFPosition + 22, 4), UtilLob.WriteBlobLength + 1); -- Uncompressed size
    aDecompressedFile.content := utl_compress.lz_uncompress(UtilLob.WriteBlobGet);
    return;
  elsif fCompressionMethod = COMPRESSION_METHOD$AS_IS then
    aDecompressedFile.content := fExtractedFile;
    return;
  else
    Util.RaiseErr('Неизвестный метод архивации');
  end if;
exception
  when Util.eStandardException then
    LogWork.NotifyException(Pn1$, Pn2$);
    Util.RaiseErr(Util.NormalizeSQLErrM);
  when others then
    LogWork.NotifyException(Pn1$, Pn2$);
    Util.RaiseErr('Непредвиденная ошибка');
end Unzip;
---------
end UtilCompress;
/
show err

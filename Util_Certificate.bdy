prompt create or replace package body Util_Certificate

create or replace package body Util_Certificate
as

Pn1$ constant varchar2(30) := 'Util_Certificate';

---------
function GetServerUrl(aServerId int) return varchar2
is
begin
  Util.CheckErr(aServerId is null, 'Сервер ЭЦП не задан');
  for cSrv in (select * from adm_certificate_server where id = aServerId) loop
    return rtrim(cSrv.url, '/');
  end loop;
  Util.RaiseErr('Сервер ЭЦП %d не найден', aServerId);
end GetServerUrl;

---------
function GetServerName(aServerId int) return varchar2
is
begin
  for cSrv in (select * from adm_certificate_server where id = aServerId) loop
    return cSrv.name;
  end loop;
  Util.RaiseErr('Сервер ЭЦП %d не найден', aServerId);
end GetServerName;

---------
procedure SendCmd(aCmd varchar2, aServerId int, aFileReq TFile, aFileResp out TFile, aDocType int := null, aDocId int := null)
is
  Pn2$ constant varchar2(30) := 'SendCmd';
  fPrm          Op_Online.THTTPParameter;
  fFileName     varchar2(200) := aFileReq.filename;
  fResponse     clob;
  fEmulatorMode boolean;
begin
  LogWork.NotifyFmt(Pn1$, Pn2$, '-=> srv=%d, cmd=%s, filename=%s', aServerId, aCmd, aFileReq.filename);
  fPrm.doc_type        := aDocType;
  fPrm.doc_id          := aDocId;
  fPrm.server_name     := GetServerName(aServerId);
  fPrm.request_name    := 'PKI Server:' || aCmd;
  fPrm.url             := GetServerUrl(aServerId) || '/' || aCmd;
  fPrm.chunked         := false;
  fEmulatorMode := lower(fPrm.url) like 'emulator%';
  if lower(aCmd) like '%by_ftp' then
    if fEmulatorMode then
      fResponse := 'OK';
      dbms_lock.sleep(0.02);
    else
      Op_Online.HTTP_Post
      ( fPrm
      , null
      , fResponse
      );
    end if;
    aFileResp.content := UtilLob.Clob2Blob(fResponse);
  else
    if fEmulatorMode then
      aFileResp.content := aFileReq.content;
      fFileName :=
        case aCmd when 'sign_data'   then fFileName || '.p7s'
                  when 'verify_data' then replace(fFileName, '.p7s')
                                     else fFileName
        end;
      dbms_lock.sleep(0.02);
    else
      fPrm.form_param_name := 'filename';
      for i in 1 .. 2 loop -- попробовать второй раз, если ничего не вернулось
        Op_Online.HTTP_Post_File
        ( fPrm
        , aFileReq.content
        , aFileResp.content
        , fFileName
        );
        exit when nvl(dbms_lob.getlength(aFileResp.content), 0) > 0;
      end loop;
      Util.CheckErr
      ( nvl(dbms_lob.getlength(aFileResp.content), 0) = 0
      , 'Ошибка установки/снятия подписи. Файл ' || fFileName || ' пуст.'
      );
    end if;
    aFileResp.filename := fFileName;
  end if;
  LogWork.NotifyFmt(Pn1$, Pn2$, '<=- filename=%s',  aFileResp.filename);
exception
  when others then
    LogWork.NotifyException(Pn1$, Pn2$);
    raise;
end SendCmd;

---------
procedure UpdateCertificate(aServerId int, aType varchar2)
is
  Pn2$ constant varchar2(30) := 'UpdateCertificate';
  aDummyReq  TFile;
  aDummyResp TFile;
begin
  SendCMD(aType, aServerId, aDummyReq, aDummyResp, aDocType=>Docs.DOC_ADM_CERTIFICATE_SERVER, aDocId=>aServerId);
  WorkLog.RegMessageFmt
  ( 'Обновление "%s": %s'
  , nvl(Lookup.GetLookupValueName(CertificateTypes, aType), aType)
  , UtilLob.Blob2Clob(aDummyResp.content)
  , aDocType=>Docs.DOC_ADM_CERTIFICATE_SERVER, aDocId=>aServerId
  );
exception
  when others then
    LogWork.NotifyException(Pn1$, Pn2$);
    raise;
end UpdateCertificate;

---------
procedure UpdateCertByFtp(aServerId int)
is
begin
  UpdateCertificate(aServerId, 'update_cert_by_ftp');
end UpdateCertByFtp;

---------
procedure UpdateCrlByFtp(aServerId int)
is
begin
  UpdateCertificate(aServerId, 'update_crl_by_ftp');
end UpdateCrlByFtp;

---------
procedure UpdateCertCrlByFtp(aServerId int)
is
begin
  UpdateCertificate(aServerId, 'update_cert_crl_by_ftp');
end UpdateCertCrlByFtp;

---------
procedure SignData(aServerId int, aFileReq TFile, aFileResp out TFile, aDocType int := null, aDocId int := null)
is
  Pn2$ constant varchar2(30) := 'sign_data';
begin
  SendCMD(Pn2$, aServerId, aFileReq, aFileResp, aDocType, aDocId);
end SignData;

---------
procedure VerifyData(aServerId int, aFileReq TFile, aFileResp out TFile, aDocType int := null, aDocId int := null)
is
  Pn2$ constant varchar2(30) := 'verify_data'; 
begin
  SendCMD(Pn2$, aServerId, aFileReq, aFileResp, aDocType, aDocId);
end VerifyData;

---------
function CertificateTypes return Util.RefCursor
is
begin
  return Lookup.CreateLookupS
         ( tp_varchar2_100_table
           ( 'update_cert_by_ftp'    , 'Сертификаты'
           , 'update_crl_by_ftp'     , 'СОС'
           , 'update_cert_crl_by_ftp', 'Сертификаты + СОС'  
           )
         );
end CertificateTypes;

---------
function UseSignCmds return Util.RefCursor
is
begin
  return Lookup.CreateLookupN
         ( tp_varchar2_100_table
           ( null, 'Нет'
           , 1   , 'Вручную'
           , 2   , 'Автоматически'  
           )
         );
end UseSignCmds;

---------
function Certificates return Util.RefCursor
is
  fCursor Util.RefCursor;
begin
  open fCursor for
    select id, name
      from adm_certificate_server
      where url is not null
      order by name;
  return fCursor;
end Certificates;

---------
end Util_Certificate;
/
show err

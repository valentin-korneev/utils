prompt create package body xml_OnLine

create or replace package body xml_OnLine
as

Pn1$                            constant varchar2(30) := 'xml_OnLine';

ROOTELEMENT_REQUEST             constant varchar2(16) := 'BS_Request';
ROOTELEMENT_RESPONSE            constant varchar2(16) := 'BS_Response';

STP_ID                          constant varchar2(20) := 'Id';
STP_NO                          constant varchar2(20) := 'ServiceNo';
STP_MNEMONIC                    constant varchar2(20) := 'MnemonicName';
STP_TRANSACTION_ID              constant varchar2(20) := 'TransactionId';
STP_SERVICE_ID                  constant varchar2(20) := 'ServiceId';

CGI_PARAM_TERMINAL              constant varchar2(40) := 'SOU-Terminal';
CGI_PARAM_SIGNATURE             constant varchar2(15) := 'Data-Signature';
SIGNATURE_ALGORITHM_MD5         constant varchar2(15) := 'MD5';

PACK_LENGTH                     constant int          := 15000;

gDocType                        int;
gDocId                          int;
gContextDocType                 int;
gContextDocId                   int;

-- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

ERR$JSON$SCANNER_EXCEPTION      exception; pragma exception_init(ERR$JSON$SCANNER_EXCEPTION, -20100); -- lexing fails

-- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

subtype TServiceList            is OpPayment.TServiceList;
subtype TExtraInfo              is OpPayment.TExtraInfo;
subtype TAnswer                 is OpPayment.TAnswer;
subtype TDialogAmount           is OpPayment.TDialogAmount;
subtype TParameters             is OpPayment.TParameters;
subtype TAuthParameters         is OpPayment.TAuthParameters;
subtype TTerminalInfo           is OpPayment.TTerminalInfo;
--subtype TFIO                    is OpPayment.TFIO;
--subtype TAddress                is OpPayment.TAddress;
--subtype TFoundAccounts          is OpPayment.TFoundAccounts;
subtype TPaidOperInfo           is OpPayment.TPaidOperInfo;
subtype TFilterList             is ServiceSupport.TFilterList;
subtype TStartTrxes             is OpPayment.TStartTrxes;
subtype TResultTrxes            is OpPayment.TResultTrxes;

---  = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = =

cReqMaskingRules Util.TStrs2D := Util.TStrs2D(Util.TStrs('(\D\d{6})\d{6}(\d{4}\D)', '\1******\2'));

---  = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = =


---------
procedure WorkaroundForModPlSqlBug(Pn1$ varchar2, Pn2$ varchar2)
is
begin
  if htp.HTBUF_LEN < 63 then
    /* !! Processing MODPLSQL Application Crashes Database with ORA-04030 / ORA-04031 Out of Process Memory Errors (Doc ID 1532032.1) */
    LogWork.NotifyFmt(Pn1$, Pn2$, 'Encountered bug 1532032.1 (htp.HTBUF_LEN=%d)! Fixed.', htp.HTBUF_LEN);
    htp.HTBUF_LEN := case when lengthb('Ю') = 1 then 255 else 63 end;
  end if;
end WorkaroundForModPlSqlBug;


---  = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = =

procedure HideAuthParams(aIdentType varchar2, aXML in out XMLType)
is
begin
  if aIdentType is not null and aXML.existsNode('//AuthorizationDetails') > 0 then
    declare
      procedure MaskParamValue(aParamName varchar2)
      is
      begin
        select updatexml(aXML, '//AuthorizationDetails/Parameter[@Name="'||aParamName||'"]/text()', '***')
          into aXML
          from dual;
      end;
    begin
      for cAPrm in
      ( select * from ref_client_id_auth_param
         where auth_ident_type = aIdentType
           and bitand(options,  Refs.AUTH_PRM_OPT_NOT_SAVE) <> 0
      ) loop
        MaskParamValue(Refs.GetRefAuthParamName(cAPrm.auth_param_id));
      end loop;
    end;
  end if;
end HideAuthParams;

---------
function GetIpAddress(aIsHttp boolean := true, aOnlyFirst boolean := false) return varchar2
is
begin
  return case when aIsHttp then Util_IP.GetOwaIpAddress(aOnlyFirst=>aOnlyFirst)
                           else '127.0.0.1'
         end;
end GetIpAddress;

---------
procedure CrAccessIsDenied( aTerminal     varchar2 := null
                          , aTerminalType int      := null
                          , aSubsystem    varchar2 := null
                          , aExtension    varchar2 := null
                          , aRequest      varchar2 := null
                          )
is
begin
  cr_Processing.Init(CR_ACCESS_IS_DENIED);
  cr_SOU       .Prepare$IpAddress(               GetIpAddress     );
  cr_SOU       .Prepare$TerminalType(            aTerminalType    );
  cr_SOU       .Prepare$Terminal(                aTerminal        );
  cr_Processing.Prepare('Подсистема'           , upper(aSubsystem));
  cr_Processing.Prepare('Расширение подсистемы', upper(aSubsystem) || ':' || upper(aExtension));
  cr_Processing.Prepare('Запрос'               , aRequest         );
  Util.CheckErrText(cr_Processing.ExecS(true));
end CrAccessIsDenied;

---------
function GetSingleIpAddress(aIsHttp boolean := true) return varchar2
is
begin
  return GetIpAddress(aIsHttp, aOnlyFirst=>true);
end GetSingleIpAddress;

---------
procedure CheckTerminal(aIsHttp boolean, aTerminal in out varchar2, aTerminalType out int, aSignSalt out varchar2, aCashWorkPlaceId varchar2 := null)
is
  Pn2$ constant varchar2(30) := 'CheckTerminal';
  fTermMask varchar2(2000) := case when owa.num_cgi_vars is not null then owa_util.get_cgi_env(CGI_PARAM_TERMINAL) end;
begin
  for cAbn in (select * from obj_abonent where abonent = aTerminal) loop
    Util.CheckErr(cAbn.disabled is not null, 'Доступ терминалу запрещён');

    if fTermMask is not null or not RefParam.IsProdDB then
      LogWork.Notify(Pn1$, Pn2$, 'CGI_PARAM_TERMINAL='||fTermMask);
      Util.CheckErr(not regexp_like(aTerminal, fTermMask), 'Доступ терминалу к %s не разрешён', owa_util.get_cgi_env('SCRIPT_NAME'));
    end if;

    Objects.CheckTerminalIpAddress(aTerminal, GetSingleIpAddress(aIsHttp));

    if cAbn.abonent_type = Refs.ABN_TYPE_CASH and aCashWorkPlaceId is not null then
      aTerminal := nvl(Objects.GetCashAbonentByWorkplace(aCashWorkPlaceId), aTerminal);
    end if;

    aTerminalType  := cAbn.abonent_type;
    aSignSalt     := cAbn.signature_salt;
    return;
  end loop;
  Util.CheckErr(aIsHttp or fTermMask is not null, 'Терминал не зарегистрирован в БД');
exception
  when others then
    LogWork.NotifyException(Pn1$, Pn2$, aTerminal||'/mask='||fTermMask);
    raise;
end CheckTerminal;

---------
function Terminal$GetKey_3DS(aTerminal varchar2) return raw
is
  Pn2$ constant varchar2(30) := 'Terminal$GetKey_3DS';
begin
  for cAbn in (select disabled, adm_3des_key_id from obj_abonent where abonent = aTerminal) loop
    Util.CheckErr(cAbn.disabled is not null, 'Доступ терминалу запрещён');
    for cK in (select zmk from adm_3des_key where id = cAbn.adm_3des_key_id) loop
      return hextoraw(cK.zmk);
    end loop;
    Util.RaiseErr('Ключ шифрования сообщений не найден');
  end loop;
  Util.RaiseErr('Терминал не зарегистрирован в БД');
exception
  when others then
    LogWork.NotifyException(Pn1$, Pn2$, 'aTerminal='||aTerminal);
    raise;
end Terminal$GetKey_3DS;

---------
function GetMsgSignature(aSalt varchar2, aData clob) return varchar2
is
begin
  return SIGNATURE_ALGORITHM_MD5 ||':'|| dbms_crypto.hash(UtilLob.Clob2Blob(aSalt||aData, aCharSet => 'CL8MSWIN1251'), dbms_crypto.HASH_MD5);
end GetMsgSignature;

---------
procedure TestSignature(aSalt varchar2, aData clob)
is
  Pn2$ constant varchar2(30) := 'TestSignature';
  fInSignature varchar2(2000);
  fCalcSignature varchar2(40);
begin
  if aSalt is not null then
    fInSignature := upper(substr(owa_util.get_cgi_env(CGI_PARAM_SIGNATURE), 1, 2000));
    Util.CheckErr(fInSignature is null, 'Подпись сообщения отсутствует');
    LogWork.NotifyFmt(Pn1$, Pn2$, 'In signature "%s"', fInSignature);
    Util.CheckErr(substr(fInSignature, 1, 3) <> SIGNATURE_ALGORITHM_MD5, 'Неверный алгоритм подписи');
    fCalcSignature := upper(GetMsgSignature(aSalt, aData));
    if fInSignature <> fCalcSignature then
      if RefParam.IsDevDB then
        LogWork.Notify(Pn1$, Pn2$, substr(aData, 1, 32000));
      end if;
      LogWork.NotifyFmt(Pn1$, Pn2$, 'Calc signature "%s"', fCalcSignature);
      Util.RaiseErr('Неверная подпись сообщения');
    end if;
  end if;
end TestSignature;

---------
function GetServiceIdType(aXML xmltype, aServiceIdPath varchar2) return varchar2
is
begin
  return xml_Util.GetValueS(aXML, aServiceIdPath, 'ServiceIdType', 20, aMandatory=>false
                          , aConstList=>tp_varchar2_100_table(STP_ID, STP_NO, STP_MNEMONIC, STP_TRANSACTION_ID, STP_SERVICE_ID));
end GetServiceIdType;

---------
function GetServiceIdHash
( aServiceNo      int,
  aServiceNoExtra int,
  aTerminal       varchar2,
  aClientIdType   varchar2,
  aClientId       varchar2
) return varchar2
is
begin
  return
    to_char
     ( dbms_utility.get_hash_value
      ( Util.Format('%d-%d-%s-%s-%s', aServiceNo, aServiceNoExtra, aTerminal, aClientIdType, aClientId),
        0, 2**24
      ),
      'fm0xxxxx'
    );
end GetServiceIdHash;

---------
procedure EncodeServiceId
( aServiceId      out varchar2,
  aServiceNo      in  int,
  aServiceNoExtra in  int,
  aTerminal           varchar2,
  aClientIdType       varchar2,
  aClientId           varchar2
)
is
begin
  if aServiceNoExtra is null then
    aServiceId := aServiceNo;
  else
    aServiceId := aServiceNo || '-' || aServiceNoExtra || '-'
      || GetServiceIdHash(aServiceNo, aServiceNoExtra, aTerminal, aClientIdType, aClientId);
  end if;
end EncodeServiceId;

---------
procedure DecodeServiceId
( aServiceIdType      varchar2
, aServiceId          varchar2
, aServiceNo      out int
, aServiceNoExtra out int
, aTerminal           varchar2 := null
, aClientIdType       varchar2 := null
, aClientId           varchar2 := null
)
is
  fParts owa_text.vc_arr;
begin
  if aServiceId is null then
    aServiceNo := null;
    aServiceNoExtra := null;
    return;
  elsif aServiceIdType = STP_SERVICE_ID then
    aServiceNo := aServiceId + case when aServiceId > 0 then ServiceSupport.ERIP_SERVICE_ID_OFFSET else 0 end;
    return;
  elsif aServiceIdType = STP_TRANSACTION_ID and regexp_like(aServiceId, '^\d+$') then
    aServiceNoExtra := aServiceId;
    begin
      select nvl(-service_id, erip_service_id + ServiceSupport.ERIP_SERVICE_ID_OFFSET)
        into aServiceNo
        from op_oper_successful
        where id = aServiceNoExtra;
      if aServiceNo > 0 then
        aServiceNoExtra := -aServiceNoExtra;
      end if;
      return;
    exception
      when no_data_found then
        null; -- i.e. error
    end;
  elsif (nvl(aServiceIdType, STP_NO) in (STP_NO, STP_ID) and owa_pattern.match(aServiceId, '^(\d+)$',            fParts))
     or (nvl(aServiceIdType, STP_ID)           = STP_ID  and owa_pattern.match(aServiceId, '^(\d+)-(\d+)-(.+)$', fParts))
  then
    aServiceNo := fParts(1);
    if not fParts.exists(2) or aClientIdType is null then
      aServiceNoExtra := null;
      return;
    else
      aServiceNoExtra := fParts(2);
      if fParts(3) = GetServiceIdHash(aServiceNo, aServiceNoExtra, aTerminal, aClientIdType, aClientId) then
        return;
      end if;
    end if;
  end if;
  Util.RaiseErr('"%s" неверный идентификатор услуги/узла', aServiceId);
end DecodeServiceId;

---------
procedure DecodeNodeId(aNodeId in out varchar2, aPrefix out varchar2)
is
  fPos int;
begin
  fPos := instr(aNodeId, '~');
  if fPos > 0 then
    aPrefix := substr(aNodeId, 1, fPos - 1);
    aNodeId := nullif(substr(aNodeId, fPos + 1), '0');
  end if;
  aNodeId := nullif(aNodeId, '0');
end DecodeNodeId;

---------
function FormatExtraClientId(aExtraClientId ServiceSupport.TExtraClientId, aIndentCount int) return varchar2
is
begin
  return xml_Util.Element('ExtraClientId', aExtraClientId.Id,
             xml_Util.CreateAttr('IdType', aExtraClientId.IdType)
           ||xml_Util.CreateAttr('Name', aExtraClientId.Name)
           ||xml_Util.CreateAttr('DataType', aExtraClientId.DataType, aEncoding=>false)
           ||xml_Util.CreateAttr('MinLength', aExtraClientId.MinLength, aEncoding=>false)
           ||xml_Util.CreateAttr('MaxLength', aExtraClientId.MaxLength, aEncoding=>false),
           aIndentCount, aLeftBR=>false, aEncoding=>false
         );
end FormatExtraClientId;


---------
function GetFilterList(aXML XMLType, aRootNodeName varchar2) return TFilterList
is
  fResult TFilterList;
  fId varchar2(20);
begin
  for cFlt in (select value(tbl) as flt from table(xmlSequence(aXML.extract(aRootNodeName || '/FilterList/Filter'))) tbl) loop
    fId := xml_Util.GetValueS(cFlt.flt, 'Filter', 'Id', aMaxLen=>20, aMandatory=>false, aDefault=>ServiceSupport.FLT_SIMPLE);
    if not fResult.exists(fId) then
      fResult(fId) := xml_Util.GetValueS(cFlt.flt, 'Filter', aMaxLen=>50);
    end if;
  end loop;
  ServiceSupport.TestFilter(fResult);
  return fResult;
end GetFilterList;

---------
procedure ServiceList(aXML XMLType, aArrResponse out nocopy Util.TStrArr, aTermInfo TTerminalInfo)
is
  Pn2$ constant varchar2(30) := 'ServiceList';
  fLocExcept varchar2(99);
  --
  fNodeId varchar2(30);
  fNodePrefix varchar2(30);
  fServiceList TServiceList;
  fServiceId varchar2(99);
  fServiceExtraNo int;
  fExtraClientIdExists boolean;
  fFilterList TFilterList;
begin
  fNodeId := xml_Util.GetValueS(aXML, 'ServiceList/NodeId', aMaxLen=>30, aMandatory=>false);
  DecodeNodeId(fNodeId, fNodePrefix);
  if fNodePrefix is null then
    DecodeServiceId(null, fNodeId, fNodeId, fServiceExtraNo, aTermInfo.terminal, aTermInfo.client_ident_type, aTermInfo.client_ident);
  end if;
  --
  fFilterList := GetFilterList(aXML, Pn2$);
  if fFilterList.count > 0 then
    LogWork.NotifyFmt(Pn1$, Pn2$, 'fFilterListCount=%d', fFilterList.count);
  end if;
  fLocExcept := 'GetServiceList';
  ServiceSupport.GetServiceList(aTermInfo, fFilterList, fNodeId, fServiceExtraNo, fServiceList, aGroupIdPrefix=>fNodePrefix);
  aArrResponse(aArrResponse.count + 1) := xml_Util.OpenElement('ServiceList', xml_Util.CreateAttr('Count', fServiceList.Count, aEncoding=>false));
  for i in 1 .. fServiceList.count loop
    begin
      EncodeServiceId(fServiceId, fServiceList(i).No, fServiceList(i).ExtraNo, aTermInfo.terminal, aTermInfo.client_ident_type, aTermInfo.client_ident);
      case fServiceList(i).RecType
        when ServiceSupport.LIST_ITEM_TYPE_NODE then
          fExtraClientIdExists := fServiceList(i).ExtraClientId.IdType is not null;
          aArrResponse(aArrResponse.count + 1) :=
            xml_Util.OpenElement('ServiceTree'
            ,    xml_Util.CreateAttr('Idx', i, aEncoding=>false)
              || xml_Util.CreateAttr('Id', fServiceId, aEncoding=>false)
              || xml_Util.CreateAttr('Name', fServiceList(i).Name)
            , aIndentCount=>1
            , aClose=>(not fExtraClientIdExists)
            , aLeftBR=>false
            );
          if fExtraClientIdExists then
            aArrResponse(aArrResponse.count + 1) := FormatExtraClientId(fServiceList(i).ExtraClientId, 2);
            aArrResponse(aArrResponse.count + 1) := xml_Util.CloseElement('ServiceTree', 1, aLeftBR=>false);
          end if;
        when ServiceSupport.LIST_ITEM_TYPE_SERVICE then
          aArrResponse(aArrResponse.count + 1) :=
            xml_Util.Element( 'Service', fServiceList(i).Name,
               xml_Util.CreateAttr('Idx', i, aEncoding=>false)
            || xml_Util.CreateAttr('Id', fServiceId, aEncoding=>false)
            || xml_Util.CreateAttr('ServiceNo', nvl(fServiceList(i).No2, fServiceList(i).No), aEncoding=>false)
            || xml_Util.CreateAttr('MnemonicName', fServiceList(i).mnemonic_name)
            || xml_Util.CreateAttr('UserServiceAddEnabled',     case when     fServiceList(i).personal_account is not null then Util.YES end, aEncoding=>false)
            || xml_Util.CreateAttr('ExcludeFromTree',           case when     fServiceList(i).exclude_from_tree            then Util.YES end, aEncoding=>false)
            || xml_Util.CreateAttr('CanBePartOfComplexPayment', case when not fServiceList(i).can_be_part_of_complex       then Util.NO  end, aEncoding=>false)
            || xml_Util.CreateAttr('Storn', fServiceList(i).storn_type, aDefVal=>Refs.STORN_UNTIL_SETTLEMENT, aEncoding=>false)
            , aIndentCount=>1
            , aLeftBR=>false
            );
        else
          null;
      end case;
    exception
      when others then
        fLocExcept := i||' of '||fServiceList.count;
        raise;
    end;
  end loop;
  aArrResponse(aArrResponse.count + 1) := xml_Util.CloseElement('ServiceList', aLeftBR=>false);
exception
  when others then
    LogWork.NotifyException(Pn1$, Pn2$, fLocExcept);
    raise;
end ServiceList;

---------
procedure ServiceTree(aXML XMLType, aArrResponse out nocopy Util.TStrArr, aTermInfo TTerminalInfo, aIsSoftClubCashWorkPlace boolean)
is
  Pn2$ constant varchar2(30) := 'ServiceTree';
  fIndentCount int := 1;
  fTree ServiceSupport.TServiceTree;
  fServiceId varchar2(99);
  fNodeId varchar2(30);
  fNodePrefix varchar2(30);
  fServiceNo int;
  fServiceExtraNo int;
  fFilterList TFilterList;
  fGetExtraData boolean;
begin
  fNodeId := xml_Util.GetValueS(aXML, 'ServiceTree/NodeId', aMaxLen=>30, aMandatory=>false);
  DecodeNodeId(fNodeId, fNodePrefix);
  fFilterList := GetFilterList(aXML, Pn2$);
  fGetExtraData := xml_Util.GetValueB(aXML, 'ServiceTree', 'GetExtraServiceData', aMandatory=>false, aDefault=>false);

  if fNodeId = to_char(ServiceSupport.SRV_GRP_ID_ERIP) and fNodePrefix is null and aIsSoftClubCashWorkPlace
    and  RefParam.GetParamValueAsBooleanDef(Refs.SYS_PRM_SC_CASH_FULL_TREE, false, Refs.SUBSYSTEM_CASH)
  then
    fNodeId := null;
  end if;
  if fNodeId is null or fNodePrefix is not null then
    ServiceSupport.GetServiceTree(fTree, aTermInfo, fFilterList, fNodePrefix, fNodeId, aGetExtraInfo=>fGetExtraData);
  else
    DecodeServiceId(null, fNodeId, fServiceNo, fServiceExtraNo, aTermInfo.terminal, aTermInfo.client_ident_type, aTermInfo.client_ident);
    ServiceSupport.GetServiceTree(fTree, aTermInfo, fFilterList, aNodeId=>fServiceNo, aNodeIdExtra=>fServiceExtraNo, aGetExtraInfo=>fGetExtraData);
  end if;
  aArrResponse(aArrResponse.count + 1) :=
    xml_Util.OpenElement
    ( 'ServiceTree',
        xml_Util.CreateAttr('Name', fTree(0).SrvItem.Name)
      ||xml_Util.CreateAttr('Count', fTree(0).NextLevelElementCnt, aEncoding=>false)
      ||xml_Util.CreateAttr('Id', 0, aEncoding=>false)
    , 0
    , false
    );
  LogWork.NotifyFmt(Pn1$, Pn2$, '- Format(%d) ...', fTree.count-1);
  for i in nvl(fTree.next(0), 1) .. fTree.last loop
    for j in fTree(i).lvl .. fIndentCount - 1 loop
      fIndentCount := fIndentCount - 1;
      aArrResponse(aArrResponse.count + 1) := xml_Util.CloseElement('ServiceTree', fIndentCount, false);
    end loop;
    EncodeServiceId(fServiceId, fTree(i).SrvItem.No, fTree(i).SrvItem.ExtraNo, aTermInfo.terminal, aTermInfo.client_ident_type, aTermInfo.client_ident);

    if fTree(i).SrvItem.RecType = ServiceSupport.LIST_ITEM_TYPE_NODE then
      aArrResponse(aArrResponse.count + 1) := xml_Util.OpenElement('ServiceTree',
           xml_Util.CreateAttr('Idx',  fTree(i).Idx, aEncoding=>false)
        || xml_Util.CreateAttr('Name', fTree(i).SrvItem.name)
        || xml_Util.CreateAttr('Id', fServiceId, aEncoding=>false)
        || xml_Util.CreateAttr('Count', fTree(i).NextLevelElementCnt, aEncoding=>false),
        fIndentCount, false
      );
      fIndentCount := fIndentCount + 1;
      if fTree(i).SrvItem.ExtraClientId.IdType is not null then
        aArrResponse(aArrResponse.count + 1) := FormatExtraClientId(fTree(i).SrvItem.ExtraClientId, fIndentCount);
      end if;
    else
      aArrResponse(aArrResponse.count + 1) := xml_Util.Element('Service', fTree(i).SrvItem.Name,
           xml_Util.CreateAttr('Idx', fTree(i).Idx, aEncoding=>false)
        || xml_Util.CreateAttr('Id', fServiceId, aEncoding=>false)
        || xml_Util.CreateAttr('ServiceNo', fTree(i).SrvItem.No, aEncoding=>false)
        || xml_Util.CreateAttr('MnemonicName', fTree(i).SrvItem.mnemonic_name)
        || xml_Util.CreateAttr('UserServiceAddEnabled',     case when     fTree(i).SrvItem.personal_account is not null then Util.YES end, aEncoding=>false)
        || xml_Util.CreateAttr('ExcludeFromTree',           case when     fTree(i).SrvItem.exclude_from_tree            then Util.YES end, aEncoding=>false)
        || xml_Util.CreateAttr('CanBePartOfComplexPayment', case when not fTree(i).SrvItem.can_be_part_of_complex       then Util.NO  end, aEncoding=>false)
        || case when fGetExtraData then
             xml_Util.CreateAttr('SpId',        fTree(i).extra_info.id,          aEncoding=>false) ||
             xml_Util.CreateAttr('SpName',      fTree(i).extra_info.name                         ) ||
             xml_Util.CreateAttr('SpUNP',       fTree(i).extra_info.unp,         aEncoding=>false) ||
             xml_Util.CreateAttr('SpAccount',   fTree(i).extra_info.account,     aEncoding=>false) ||
             xml_Util.CreateAttr('SpBank',      fTree(i).extra_info.bank,        aEncoding=>false) ||
             xml_Util.CreateAttr('Currency',    fTree(i).extra_info.currency,    aEncoding=>false) ||
             xml_Util.CreateAttr('CashSymbol',  fTree(i).extra_info.cash_symbol, aEncoding=>false) ||
             xml_Util.CreateAttr('Storn',       fTree(i).extra_info.storn_type,  aEncoding=>false)
           end,
        fIndentCount, false
      );
    end if;
  end loop;
  for j in reverse 0 .. fIndentCount - 1 loop
    aArrResponse(aArrResponse.count + 1) := xml_Util.CloseElement('ServiceTree', j, false);
  end loop;
  LogWork.Notify(Pn1$, Pn2$, '<=-');
end ServiceTree;

---------
procedure GetAnswers(aXML XMLType, aRootNodeName varchar2, aAnswer out TAnswer)
is
  fNode varchar2(2000) := case when aRootNodeName is not null then aRootNodeName || '/' end || 'ParameterList';
  fCount int;
  fParamIdx int;
begin
  fCount := xml_Util.GetValueN(aXML, fNode, 'Count', aFormat=>'99999990', aMandatory=>false);
  if fCount is null or fCount > 0 then
    fNode := fNode || '[1]/Parameter';
    for cP in (select value(prm) as val from table(xmlSequence(aXML.extract(fNode))) prm where fCount is null or rownum <= fCount) loop
      fParamIdx := xml_Util.GetValueN(cP.val, 'Parameter', 'Idx', aFormat=>'99999990');
      Util.CheckErr(aAnswer.exists(fParamIdx), 'Дублирование параметра "%s=%d"', 'ParameterList/Parameter/@Idx', fParamIdx);
      aAnswer(fParamIdx) := xml_Util.GetValueS(cP.val, 'Parameter', aMaxLen=>255, aMandatory=>false);
    end loop;
  end if;
end GetAnswers;

---------
procedure ServiceInfo(aXML XMLType, aResponse out varchar2, aTermInfo in out nocopy TTerminalInfo)
is
  Pn2$ constant varchar2(30) := 'ServiceInfo';
  --
  fServiceId varchar2(30);
  fServIdType varchar2(20);
  fServiceNo int;
  fServiceExtraNo int;
  fServiceInfoId varchar2(30);
  fPersonalAccount varchar2(30);
  fServiceName varchar2(255);
  --
  fExtraInfo TExtraInfo;
  fAnswer TAnswer;
  fDialogAmount TDialogAmount;
  fParameters TParameters;
  --
  fNeedNextIteration boolean;
  fXML varchar2(32000);
  fLookups varchar2(30000);
  --
  procedure CheckServiceInfoId
  is
  begin
    Util.CheckErr(fServiceInfoId is null, 'Не задан "ServiceInfoId"');
  end;
  --
begin
  gDocType := Docs.DOC_OPER;
  fServiceId      := xml_Util.GetValueS(aXML, 'ServiceInfo/ServiceId', aMaxLen=>30);
  fServIdType     := GetServiceIdType(aXML, 'ServiceInfo/ServiceId');
  DecodeServiceId(fServIdType, fServiceId, fServiceNo, fServiceExtraNo, aTermInfo.terminal, aTermInfo.client_ident_type, aTermInfo.client_ident);
  fServiceInfoId  := xml_Util.GetValueS(aXML, 'ServiceInfo/ServiceInfoId', aMaxLen=>30, aMandatory=>false);
  fPersonalAccount := xml_Util.GetValueS(aXML, 'ServiceInfo/PersonalAccount', aMaxLen=>30, aMandatory=>false);
  --
  fDialogAmount.Amount := xml_Util.GetValueN(aXML, 'ServiceInfo/Amount', aFormat=>'999999999990D99', aMandatory=>false);
  if fDialogAmount.Amount is not null then /*?? WTF ??*/
    CheckServiceInfoId;
  end if;
  --
  if aXML.extract('ServiceInfo/ParameterList[1][@Count>0 or string-length(@Count)=0]') is not null then
    CheckServiceInfoId;
    GetAnswers(aXML, Pn2$, fAnswer);
  end if;
  --
  Util.CheckErrText
  ( OpPayment.ServiceInfo
    ( aTermInfo, fServiceNo, fServiceExtraNo, fServiceInfoId, fAnswer
    , fDialogAmount, fExtraInfo, fParameters, fNeedNextIteration
    , gDocId
    , fPersonalAccount
    , fServiceName
    )
  );

  fXML :=
       xml_Util.Element('ServiceInfoId', fServiceInfoId, aEncoding=>false)
    || xml_Util.Element('ServiceName', fServiceName, aMandatory=>false)
    || xml_Util.OpenElement('ParameterList', xml_Util.CreateAttr('Count', fParameters.Count, aEncoding=>false), aIndentCount=>2);
  for i in 1..fParameters.Count loop
    declare
      function CreateAttrInpDataSrc return varchar2
      is
      begin
        if fParameters(i).input_data_sources is not null and Util.BitClear(fParameters(i).input_data_sources, ServiceSupport.INPUT_DATA_SRC_KEYBOARD) <> 0 then
          return xml_Util.CreateAttr('InputDataSources'
                 , ltrim(
                     case when bitand(fParameters(i).input_data_sources, ServiceSupport.INPUT_DATA_SRC_KEYBOARD) <> 0 then
                       ServiceSupport.INPUT_DATA_SRC_NAME_KEYBOARD
                     end ||
                     case when bitand(fParameters(i).input_data_sources, ServiceSupport.INPUT_DATA_SRC_LOOKUP)   <> 0 then
                       ';' || ServiceSupport.INPUT_DATA_SRC_NAME_LOOKUP
                     end ||
                     case when bitand(fParameters(i).input_data_sources, ServiceSupport.INPUT_DATA_SRC_CARD)     <> 0 then
                       ';' || ServiceSupport.INPUT_DATA_SRC_NAME_CARD
                     end
                   , ';')
                 , aEncoding=>false
                 )
          ;
        else
          return null;
        end if;
      end CreateAttrInpDataSrc;
      --
      function CreateAttrLookup return varchar2
      is
        fLookup varchar2(16384);
        fLookupName varchar2(99);
      begin
        if fParameters(i).lookup is not null and fParameters(i).lookup.hidden = Util.NO then
          fLookupName := fParameters(i).type || '$' || fParameters(i).name;
          for j in 1..fParameters(i).lookup.ItemCount loop
            fLookup := fLookup
                    || xml_Util.Element
                       ( 'Item'
                       , fParameters(i).lookup.items(j).code
                       , xml_Util.CreateAttr('Name', fParameters(i).lookup.items(j).name)
                       ||xml_Util.CreateAttr('Icon', fParameters(i).lookup.items(j).icon)
                       );
            exit when length(fLookup) > 16000;
          end loop;
          fLookups := fLookups
                      || xml_Util.Element('Lookup', fLookup
                         , xml_Util.CreateAttr('Name', fLookupName)
                         , aIndentCount=>3, aEncoding=>false, aCloseOnNewLine=>true);
          return xml_Util.CreateAttr('Lookup', fLookupName);
        else
          return null;
        end if;
      end CreateAttrLookup;
    begin
      xml_Util.AddElementToBuff(fXML, 'Parameter', fParameters(i).value,
         xml_Util.CreateAttr('Idx', i, aEncoding=>false)
      || xml_Util.CreateAttr('Name', fParameters(i).name)
      || xml_Util.CreateAttr('Editable', fParameters(i).editable, false)
      || xml_Util.CreateAttr('DataType', fParameters(i).data_type, ServiceSupport.SDT_STRING, aEncoding=>false)
      || case when fParameters(i).editable then
              xml_Util.CreateAttr('DataFormat', fParameters(i).data_format, aEncoding=>false)
           || xml_Util.CreateAttr('MinLength', fParameters(i).min_length, 0, aEncoding=>false)
           || xml_Util.CreateAttr('MaxLength', fParameters(i).max_length, 0, aEncoding=>false)
           || xml_Util.CreateAttr('Hint', fParameters(i).hint)
           || xml_Util.CreateAttr('SearchRequest', fParameters(i).search_request)
           || xml_Util.CreateAttr('PassChar', fParameters(i).used_pass_char_input, false)
           || CreateAttrInpDataSrc
           || case when bitand(fParameters(i).input_data_sources, ServiceSupport.INPUT_DATA_SRC_CARD) <> 0
                     or fParameters(i).type in (ServiceSupport.QT_PAN)
              then
                xml_Util.CreateAttr('Type', fParameters(i).type)
              end
           || CreateAttrLookup
         end
        , aIndentCount=>3
      );
    end;
  end loop;
  fXML := fXML || xml_Util.CloseElement('ParameterList', aIndentCount=>2);
  --
  xml_Util.AddElementToBuff(fXML, 'Amount', RCore.FmtAmount(nvl(fDialogAmount.amount, 0), fDialogAmount.currency, Fmt=>Rcore.fSimple),
       xml_Util.CreateAttr('Currency', fDialogAmount.currency, aEncoding=>false)
    || xml_Util.CreateAttr('Visible', fDialogAmount.visible, false)
    || xml_Util.CreateAttr('Editable', fDialogAmount.editable, false)
    || case
         when fDialogAmount.editable then
              xml_Util.CreateAttr('MinAmount', RCore.FmtAmount(fDialogAmount.min_amount, fDialogAmount.currency, Fmt=>Rcore.fSimple), aEncoding=>false)
           || xml_Util.CreateAttr('MaxAmount', RCore.FmtAmount(fDialogAmount.max_amount, fDialogAmount.currency, Fmt=>Rcore.fSimple), aEncoding=>false)
           || xml_Util.CreateAttr('AmountPrecision', RCore.FmtAmount(fDialogAmount.precision, fDialogAmount.currency, Fmt=>Rcore.fSimple), aEncoding=>false)
       end
  );
  --
  if fExtraInfo.Count > 0 then
    fXML := fXML || xml_Util.OpenElement('ExtraInfo', xml_Util.CreateAttr('Count', fExtraInfo.count, aEncoding=>false), aPreserveWhitespaces=>true);
    for i in 1..fExtraInfo.Count loop
      xml_Util.AddElementToBuff
      ( fXML, 'ExtraInfoText'
      , nvl(rtrim(fExtraInfo(i).StrInfo), ' ')
      , xml_Util.CreateAttr('Idx', i)
      ||xml_Util.CreateAttr('Important', nvl(fExtraInfo(i).important, false), aDefVal=>false)
      );
    end loop;
    fXML := fXML || xml_Util.CloseElement('ExtraInfo', aIndentCount=>2);
  end if;
  --
  xml_Util.AddElementToBuff(fXML, 'NextRequestType',
    case when fNeedNextIteration then 'ServiceInfo' else 'TransactionStart' end, aIndentCount=>2, aEncoding=>false);
  --
  fXML := fXML || xml_Util.Element('Lookups', fLookups, aIndentCount=>2, aEncoding=>false, aCloseOnNewLine=>true, aMandatory=>false);
  --
  aResponse := xml_Util.Element('ServiceInfo', fXML, aIndentCount=>1, aEncoding=>false, aCloseOnNewLine=>true);
end ServiceInfo;

---------
procedure AddCheckInfo(aXML in out varchar2, aElementName varchar2, aInfo TExtraInfo, aMandatory boolean := false, aIndentCount int := 2)
is
begin
  if aMandatory or aInfo.Count > 0 then
    aXML :=    aXML
            || xml_Util.OpenElement
               ( aElementName, xml_Util.CreateAttr('Count', aInfo.Count)
               , aIndentCount=>aIndentCount, aPreserveWhitespaces=>true
               );
    for i in 1..aInfo.Count loop
      xml_Util.AddElementToBuff(aXML, 'CheckLine', nvl(rtrim(aInfo(i).StrInfo), ' '), xml_Util.CreateAttr('Idx', i, aEncoding=>false));
    end loop;
    aXML := aXML || xml_Util.CloseElement(aElementName, aIndentCount=>aIndentCount);
  end if;
end AddCheckInfo;

---------
procedure ReadAuthParam(aXML XMLType, aRootNodeName varchar2, aMandatory boolean, aAuthParam out TAuthParameters, aTermInfo TTerminalInfo := null)
is
  fXML XMLType;
  fCount int;
begin
  fXML := aXML.extract(aRootNodeName||'/AuthorizationDetails');
  if fXML is not null then
    fCount := xml_Util.GetValueN(fXML, '/AuthorizationDetails', 'Count', aMandatory=>false, aFormat=>'99999990');
    for cAP in
    ( select *
         from XMLTable
              ( '/AuthorizationDetails/Parameter' passing fXML
                columns
                  val   clob           path 'text()'
                , name  varchar2(1000) path '@Name'
              )
         where fCount is null or rownum <= fCount
    ) loop
      aAuthParam(aAuthParam.count + 1).name  := xml_Util.GetValueS(cAP.name, 'Parameter[@Name]', 99);
      aAuthParam(aAuthParam.last     ).value := xml_Util.GetValueS(cAP.val,  'Parameter', aMaxLen=>10000, aMandatory=>false);
    end loop;
  else
    Util.CheckErr(aMandatory, 'Не найден элемент "%s/AuthorizationDetails"', aRootNodeName);
  end if;

  if aTermInfo.actual_ident_id is not null and aAuthParam.count = 0 and aTermInfo.actual_auth_ident_type = Refs.CLIENT_ID_TYPE_MS then
    aAuthParam(aAuthParam.count + 1).name  := Refs.AUTH_PARAM_CARD_EXPIRED;
    aAuthParam(aAuthParam.last     ).value := to_char(ClClient.GetIdentExpiredDate(aTermInfo.actual_ident_id), 'mm.yyyy');
  end if;
end ReadAuthParam;

---------
procedure ReadAuthParam(aXML XMLType, aRootNodeName varchar2, aMandatory boolean, aAuthParams out tp_auth_parameters, aTermInfo TTerminalInfo := null)
is
  fAuthParameters TAuthParameters;
begin
  ReadAuthParam(aXML, aRootNodeName, aMandatory, fAuthParameters, aTermInfo);
  aAuthParams := tp_auth_parameters();

  for i in 1..fAuthParameters.count loop
    aAuthParams.extend;
    aAuthParams(aAuthParams.last) := tp_auth_parameter(fAuthParameters(i).name, fAuthParameters(i).value);
  end loop;
end ReadAuthParam;

---------
function AddTransactionStartAnswer
( aTermInfo    TTerminalInfo
, aOperInfo    TPaidOperInfo
, aAmount      TDialogAmount
, aCheckHeader TExtraInfo
, aIndentCount int
, aExtraXML    varchar2 := null
) return varchar2 is
  Pn2$ constant varchar2(30) := 'AddTransactionStartAnswer';
  --
  fXML varchar2(32767);
  --
  function AddOperParam return varchar2
  is
    fResult varchar2(32000);
    fIdx int;
  begin
    if bitand(aTermInfo.check_option, ServiceSupport.PRN_OPER_PARAM) <> 0 then
      fIdx := aOperInfo.params.first;
      while fIdx is not null loop
        fResult := fResult ||
                   xml_Util.Element('Parameter', aOperInfo.params(fIdx).answer,
                     xml_Util.CreateAttr('Name', aOperInfo.params(fIdx).name) || xml_Util.CreateAttr('Type', aOperInfo.params(fIdx).ptype), aIndentCount+2);
        fIdx := aOperInfo.params.next(fIdx);
      end loop;
    end if;
    if fResult is not null then
      return xml_Util.OpenElement('Parameters', aIndentCount=>aIndentCount+1) ||
             fResult ||
             xml_Util.CloseElement('Parameters', aIndentCount+1);
    else
      return null;
    end if;
  end;
  --
  function AddExtraInfo return varchar2
  is
    fResult varchar2(32000);
    fIdx int;
  begin
    fIdx := aOperInfo.extra_info.first;
    while fIdx is not null loop
      fResult := fResult || xml_Util.Element('ExtraInfoText', aOperInfo.extra_info(fIdx), aIndentCount=>aIndentCount+2);
      fIdx := aOperInfo.extra_info.next(fIdx);
    end loop;

    return xml_Util.Element('ExtraInfo', fResult, aIndentCount=>aIndentCount+1, aEncoding=>false, aMandatory=>false, aCloseOnNewLine=>true);
  end AddExtraInfo;
begin
  xml_Util.AddElementToBuff(fXML, 'TransactionId', aOperInfo.id, aIndentCount=>aIndentCount+1, aEncoding=>false);
  fXML := fXML || xml_Util.Element('AllowedAmountInResult', Util.IsBitSet(aOperInfo.options, Refs.OP$OPT$PARTIAL_ADVICE), aDefault=>false, aMandatory=>false);
  if    RefParam.IsDevDB
     or bitand(aTerminfo.check_option, ServiceSupport.PRN_SERVICE_DETAIL) <> 0
  then
    declare
      fPrm varchar2(2000);
    begin
      if aOperInfo.cash_symbols is not null and aOperInfo.cash_symbols.count > 0 then
        fPrm := fPrm || xml_Util.OpenElement('CashSymbols', aIndentCount=>aIndentCount+2);
        for i in 1 .. aOperInfo.cash_symbols.count loop
          fPrm := fPrm || xml_Util.Element('Amount', RCore.FmtAmount(aOperInfo.cash_symbols(i).amount, aAmount.currency, Fmt=>Rcore.fSimple)
            , xml_Util.CreateAttr('CashSymbol', aOperInfo.cash_symbols(i).cash_symbol)
            ||xml_Util.CreateAttr('Kind',       aOperInfo.cash_symbols(i).amount_kind)
            , aIndentCount=>aIndentCount+3
            );
        end loop;
        fPrm := fPrm || xml_Util.CloseElement('CashSymbols', aIndentCount+2);
      end if;

      fXML :=
          fXML
        ||xml_Util.Element
          ( 'ServiceDetails'
          , fPrm
          ||xml_Util.Element('PersonalAccount',       aOperInfo.personal_account, aMandatory=>false)
          ||xml_Util.Element('PenaltyAmount',         RCore.FmtAmount(aOperInfo.penalty_fee_amount, aAmount.currency, Fmt=>Rcore.fSimple), aMandatory=>false, aEncoding=>false)
          ||xml_Util.Element('FeeAmount',             RCore.FmtAmount(aOperInfo.fee_amount, aAmount.Currency, Fmt=>Rcore.fSimple), aMandatory=>false, aEncoding=>false)
          ||xml_Util.Element('AbonentFIO',            aOperInfo.abonent_fio, aMandatory=>false)
          ||xml_Util.Element('AbonentAddress',        aOperInfo.abonent_address, aMandatory=>false)
          ||xml_Util.Element('AllowedAmountInResult', Util.IsBitSet(aOperInfo.options, Refs.OP$OPT$PARTIAL_ADVICE), aDefault=>false, aMandatory=>false)
          , aEncoding=>false, aMandatory=>false, aCloseOnNewLine=>true);
    end;
  end if;
  AddCheckInfo(fXML, 'CheckHeader', aCheckHeader, aMandatory=>true);
  --
  return
       xml_Util.OpenElement('TransactionStart', aIndentCount=>aIndentCount)
    || fXML
    || AddOperParam
    || AddExtraInfo
    || aExtraXML
    || xml_Util.CloseElement('TransactionStart', aIndentCount);
end AddTransactionStartAnswer;

---------
function TransactionStart(aXML XMLType, aResponse out varchar2, aTermInfo in out nocopy TTerminalInfo, aAuthParameters out TAuthParameters) return varchar2
is
  Pn2$ constant varchar2(30) := 'TransactionStart';
  --
  fServiceId varchar2(30);
  fServIdType varchar2(20);
  fServiceNo int;
  fServiceExtraNo int;
  fServiceInfoId varchar2(30);
  --
  fAnswer         TAnswer;
  fDialogAmount   TDialogAmount;
  fCheckHeader    TExtraInfo;
  fOperInfo       TPaidOperInfo;
  --
  fErrText        varchar2(4000);
  fAuthParameters TAuthParameters;
  fAction         tp_cl_ident_action;
  fActionStr      varchar2(32000);
begin
  gDocType := Docs.DOC_OPER;
  fServiceId  := xml_Util.GetValueS(aXML, 'TransactionStart/ServiceId', aMaxLen=>30);
  fServIdType := GetServiceIdType(aXML, 'TransactionStart/ServiceId');
  DecodeServiceId(fServIdType, fServiceId, fServiceNo, fServiceExtraNo, aTermInfo.terminal, aTermInfo.client_ident_type, aTermInfo.client_ident);
  fServiceInfoId := xml_Util.GetValueS(aXML, 'TransactionStart/ServiceInfoId', aMaxLen=>30);
  --
  fDialogAmount.Amount    := xml_Util.GetValueN(aXML, 'TransactionStart/Amount', aFormat=>'999999999990D99');
  fDialogAmount.currency  := xml_Util.GetValueN(aXML, 'TransactionStart/Amount', 'Currency', 3);
  fDialogAmount.auth_type := xml_Util.GetValueS(aXML, 'TransactionStart/Amount', 'AuthorizationType', 1
                             , aConstList=>tp_varchar2_100_table(Refs.AMOUNT_AUTH_BY_TERMINAL, Refs.AMOUNT_AUTH_BY_SERVER));
  --
  if aXML.extract('TransactionStart/ParameterList[1]') is not null then
    GetAnswers(aXML, Pn2$, fAnswer);
  end if;
  --
  ReadAuthParam(aXML, Pn2$, false, fAuthParameters);
  --
  if not xml_Util.GetValueB(aXML, 'TransactionStart/RequiredData', 'Check', aMandatory=>false, aDefault=>true) then
    Util.BitOr(aTermInfo.check_option, ServiceSupport.PRN_WITHOUT_INFO);
  end if;
  if xml_Util.GetValueB(aXML, 'TransactionStart/RequiredData', 'ServiceDetails', aMandatory=>false
     , aDefault=>nvl(aTermInfo.auth_ident_type, aTermInfo.client_ident_type) = Refs.CLIENT_ID_TYPE_CASH)
  then
    Util.BitOr(aTermInfo.check_option, ServiceSupport.PRN_SERVICE_DETAIL);
  end if;
  if xml_Util.GetValueB(aXML, 'TransactionStart/RequiredData', 'Parameters', aMandatory=>false, aDefault=>false) then
    Util.BitOr(aTermInfo.check_option, ServiceSupport.PRN_OPER_PARAM);
  end if;
  if xml_Util.GetValueB(aXML, 'TransactionStart/RequiredData', 'ExtraInfo', aMandatory=>false, aDefault=>false) then
    Util.BitOr(aTermInfo.check_option, ServiceSupport.PRN_EXTRA_INFO);
  end if;
  --
  fErrText := OpPayment.TransactionStart(aTermInfo, fServiceNo, fServiceInfoId, fAnswer, fDialogAmount, fOperInfo, fCheckHeader, fAuthParameters, aAuthParameters, fAction);
  gDocId := fOperInfo.id;
  if fErrText is null then
    if fAction is not null then
      declare
        fHdr    tp_msg_admin_header := tp_msg_admin_header();
      begin
        fHdr.sid      := ClientAuth_Core.GetClientSID(aTermInfo.cl_client_id);
        fHdr.terminal := aTermInfo.terminal;
        execute immediate 'begin :actstr := ClientAuth_XML_Online.Action$GetXml(:hdr, aProductType=>Refs.CLIENT_ID_TYPE_CLIENT, aProductId=>null, aAction=>:act); end;'
          using out fActionStr, fHdr, fAction;
      end;
    end if;
    aResponse := aResponse || AddTransactionStartAnswer(aTermInfo, fOperInfo, fDialogAmount, fCheckHeader, 1, aExtraXML=>fActionStr);
  end if;
  return fErrText;
end TransactionStart;

---------
procedure TransactionsStart(aXML XMLType, aResponse out varchar2, aTermInfo in out nocopy TTerminalInfo, aAuthParameters out TAuthParameters)
is
  Pn2$ constant varchar2(30) := 'TransactionsStart';
  --
  fComplexTrxId varchar2(30);
  fTrxes TStartTrxes;
  --
  fServiceId varchar2(30);
  fServIdType varchar2(20);
  fServiceNo int;
  fServiceExtraNo int;
  fServiceInfoId varchar2(30);
  --
  fAnswer TAnswer;
  fDialogAmount TDialogAmount;
  fAuthParameters TAuthParameters;
  --
  fXML varchar2(32767);
begin
  gDocType := Docs.DOC_OPER;
  --
  for trx in
  ( select rownum, t.val
      from XMLTable
           ( '/TransactionsStart/Transaction' passing aXML
             columns val xmltype path '/'
           ) t
  ) loop
    fServiceId  := xml_Util.GetValueS(trx.val, 'Transaction/ServiceId', aMaxLen=>30);
    fServIdType := GetServiceIdType(trx.val, 'Transaction/ServiceId');
    DecodeServiceId(fServIdType, fServiceId, fServiceNo, fServiceExtraNo, aTermInfo.terminal, aTermInfo.client_ident_type, aTermInfo.client_ident);
    fServiceInfoId := xml_Util.GetValueS(trx.val, 'Transaction/ServiceInfoId', aMaxLen=>30);
    --
    fDialogAmount.Amount    := xml_Util.GetValueN(trx.val, 'Transaction/Amount', aFormat=>'999999999990D99');
    fDialogAmount.currency  := xml_Util.GetValueN(trx.val, 'Transaction/Amount', 'Currency', 3);
    fDialogAmount.auth_type := xml_Util.GetValueS(trx.val, 'Transaction/Amount', 'AuthorizationType', 1
                               , aConstList=>tp_varchar2_100_table(Refs.AMOUNT_AUTH_BY_TERMINAL, Refs.AMOUNT_AUTH_BY_SERVER));
    --
    if trx.val.extract('Transaction/ParameterList[1]') is not null then
      GetAnswers(trx.val, 'Transaction', fAnswer);
    end if;

    --
    fTrxes(trx.rownum).service_no := fServiceNo;
    fTrxes(trx.rownum).session_id := fServiceInfoId;
    fTrxes(trx.rownum).answers    := fAnswer;
    fTrxes(trx.rownum).amount     := fDialogAmount;
  end loop;

  fDialogAmount.Amount    := xml_Util.GetValueN(aXML, 'TransactionsStart/Amount', aFormat=>'999999999990D99');
  fDialogAmount.currency  := xml_Util.GetValueN(aXML, 'TransactionsStart/Amount', 'Currency', 3);
  fDialogAmount.auth_type := xml_Util.GetValueS(aXML, 'TransactionsStart/Amount', 'AuthorizationType', 1
                             , aConstList=>tp_varchar2_100_table(Refs.AMOUNT_AUTH_BY_TERMINAL, Refs.AMOUNT_AUTH_BY_SERVER));
  --
  ReadAuthParam(aXML, Pn2$, false, fAuthParameters);
  --
  if not xml_Util.GetValueB(aXML, 'TransactionsStart/RequiredData', 'Check', aMandatory=>false, aDefault=>true) then
    Util.BitOr(aTermInfo.check_option, ServiceSupport.PRN_WITHOUT_INFO);
  end if;
  if xml_Util.GetValueB(aXML, 'TransactionStart/RequiredData', 'ServiceDetails', aMandatory=>false
     , aDefault=>nvl(aTermInfo.auth_ident_type, aTermInfo.client_ident_type) = Refs.CLIENT_ID_TYPE_CASH)
  then
    Util.BitOr(aTermInfo.check_option, ServiceSupport.PRN_SERVICE_DETAIL);
  end if;
  if xml_Util.GetValueB(aXML, 'TransactionStart/RequiredData', 'Parameters', aMandatory=>false, aDefault=>false) then
    Util.BitOr(aTermInfo.check_option, ServiceSupport.PRN_OPER_PARAM);
  end if;
  if xml_Util.GetValueB(aXML, 'TransactionStart/RequiredData', 'ExtraInfo', aMandatory=>false, aDefault=>false) then
    Util.BitOr(aTermInfo.check_option, ServiceSupport.PRN_EXTRA_INFO);
  end if;
  --
  OpPayment.TransactionsStart(aTermInfo, fTrxes, fDialogAmount, fAuthParameters, aAuthParameters, fComplexTrxId);

  --
  xml_Util.AddElementToBuff(fXML, 'Id', fComplexTrxId, aIndentCount=>2, aEncoding=>false);
  fXML := fXML ||
    xml_Util.Element(
      aElementName         => 'Amount',
      aElementVal          => RCore.FmtAmount(fDialogAmount.amount, fDialogAmount.currency, Fmt=>Rcore.fSimple),
      aElementAttr         => xml_Util.CreateAttr('Currency', fDialogAmount.currency),
      aIndentCount         => 2,
      aEncoding            => false
    );

  gDocId := fComplexTrxId; --fTrxes(1).oper_info.id;

  --
  for i in 1..fTrxes.count loop
    fXML := fXML || xml_Util.OpenElement('Transaction', aIndentCount=>2);
    xml_Util.AddElementToBuff(fXML, 'ServiceInfoId', fTrxes(i).session_id, aIndentCount=>3, aEncoding=>false);
    fXML := fXML || xml_Util.Element('ErrorText', fTrxes(i).error_text, aIndentCount => 3, aEncoding => false, aMandatory => false);
    if fTrxes(i).error_text is null then
      fXML := fXML || AddTransactionStartAnswer(aTermInfo, fTrxes(i).oper_info, fTrxes(i).amount, fTrxes(i).check_header, 3);
    end if;
    fXML := fXML || xml_Util.CloseElement('Transaction', 2);
  end loop;

  --
  aResponse := aResponse
    || xml_Util.OpenElement('TransactionsStart', aIndentCount=>1)
    || fXML
    || xml_Util.CloseElement('TransactionsStart', 1);
exception
  when others then
    LogWork.NotifyException(Pn1$, Pn2$);
    raise;
end TransactionsStart;

---------
function TransactionResult(aXML XMLType, aResponse out varchar2, aTermInfo TTerminalInfo, aAuthParameters out TAuthParameters) return varchar2
is
  Pn2$ constant varchar2(30) := 'TransactionResult';
  --
  fResultCode int;
  fAuthParameters TAuthParameters;
  fCheckFooter TExtraInfo;
  fXML varchar2(30000);
  --
  fErrText varchar2(2000);
begin
  gDocType    := Docs.DOC_OPER;
  fResultCode := xml_Util.GetValueN(aXML, 'TransactionResult/ResultCode',    aMaxLen=>3);
  gDocId      := xml_Util.GetValueN(aXML, 'TransactionResult/TransactionId', aMaxLen=>10, aMinNumValue=>case fResultCode when OpPayment.actApproved then 1 else 0 end);
  ReadAuthParam(aXML, Pn2$, false, fAuthParameters, aTermInfo);
  --
  fErrText := OpPayment.TransactionResult
              ( aTermInfo
              , xml_Util.GetValueS(aXML, 'TransactionResult/ServiceInfoId', aMaxLen=>30)
              , gDocId
              , fResultCode
              , fAuthParameters
              , fCheckFooter
              , aAuthParameters
              , aAmount=>xml_Util.GetValueF(aXML, 'TransactionResult/Amount', aMandatory=>false, aPositive=>true)
              );

  if fErrText is not null then
    return fErrText;
  end if;

  AddCheckInfo(fXML, 'CheckFooter', fCheckFooter);
  aResponse := xml_Util.Element('TransactionResult', fXML, aEncoding=>false, aCloseOnNewLine=>fXML is not null);

  return null;
end TransactionResult;

---------
function TransactionsResult(aXML XMLType, aResponse out varchar2, aTermInfo TTerminalInfo, aAuthParameters out TAuthParameters) return varchar2
is
  Pn2$ constant varchar2(30) := 'TransactionsResult';
  --
  fResultCode int;
  fTrxes TResultTrxes;
  fAuthParameters TAuthParameters;
  --
  fXML varchar2(32767);
  fErrText varchar2(2000);
begin
  gDocType    := Docs.DOC_OPER;
  gDocId      := xml_Util.GetValueS(aXML, 'TransactionsResult/Id',         aMaxLen=>30);
  fResultCode := xml_Util.GetValueN(aXML, 'TransactionsResult/ResultCode', aMaxLen=>3);
  --
  ReadAuthParam(aXML, Pn2$, false, fAuthParameters, aTermInfo);
  --
  for trx in
  ( select rownum, t.val
      from XMLTable
           ( '/TransactionsResult/Transaction' passing aXML
             columns val xmltype path '/'
           ) t
  ) loop
    fTrxes(trx.rownum).oper_id    := xml_Util.GetValueN(trx.val, 'Transaction/TransactionId', aMaxLen=>10, aMinNumValue=>case fResultCode when OpPayment.actApproved then 1 else 0 end);
    fTrxes(trx.rownum).session_id := xml_Util.GetValueS(trx.val, 'Transaction/ServiceInfoId', aMaxLen=>30);
  end loop;
  --
  fErrText := OpPayment.TransactionsResult(aTermInfo, gDocId, fResultCode, fTrxes, fAuthParameters, aAuthParameters);
  --
  if fErrText is null then
    for i in 1 .. fTrxes.count loop
      fXML := fXML || xml_Util.OpenElement('Transaction', aIndentCount=>2);
      xml_Util.AddElementToBuff(fXML, 'TransactionId', fTrxes(i).oper_id, aIndentCount=>3, aEncoding=>false);
      AddCheckInfo(fXML, 'CheckFooter', fTrxes(i).check_footer, aIndentCount=>3);
      fXML := fXML || xml_Util.CloseElement('Transaction', 2);
    end loop;
    --
    aResponse := aResponse
      || xml_Util.OpenElement('TransactionsResult', aIndentCount=>1)
      || fXML
      || xml_Util.CloseElement('TransactionsResult', 1);
  end if;
  return fErrText;
exception
  when others then
    LogWork.NotifyException(Pn1$, Pn2$);
    raise;
end TransactionsResult;

---------
procedure Balance(aXML XMLType, aResponse out varchar2, aTermInfo TTerminalInfo, aAuthParameters out nocopy TAuthParameters)
is
  Pn2$ constant varchar2(30) := 'Balance';
  --
  fErrText varchar2(2000);
  fAuthParameters tp_auth_parameters;
  fAuthBalanceResp tp_auth_balance_answer;
  fPIdx int;
begin
  ReadAuthParam(aXML, Pn2$, false, fAuthParameters, aTermInfo);

  fErrText := OpPayment.GetBalance(
    tp_auth_balance_request(aTermInfo.terminal, aTermInfo.actual_auth_ident_type, aTermInfo.actual_auth_ident
    , xml_Util.GetValueN(aXML, 'Balance', 'Currency', 3, aMandatory=>false)
    , fAuthParameters
    )
  , fAuthBalanceResp
  );
  --
  if fAuthBalanceResp.auth_parameters is not null then
    fPIdx := fAuthBalanceResp.auth_parameters.first;
    while fPIdx is not null loop
      aAuthParameters(aAuthParameters.count + 1).name  := fAuthBalanceResp.auth_parameters(fPIdx).name;
      aAuthParameters(aAuthParameters.count    ).value := fAuthBalanceResp.auth_parameters(fPIdx).value;
      fPIdx := fAuthBalanceResp.auth_parameters.next(fPIdx);
    end loop;
  end if;
  Util.CheckErrText(fErrText);
  --
  for i in 1..fAuthBalanceResp.balance.count loop
    aResponse :=
        aResponse
      ||xml_Util.Element
        ( 'Amount'
        , RCore.FmtAmount(fAuthBalanceResp.balance(i).amount, fAuthBalanceResp.balance(i).currency, Fmt=>Rcore.fSimple)
        , xml_Util.CreateAttr('Idx',          i, aEncoding=>false)
        ||xml_Util.CreateAttr('Currency',     fAuthBalanceResp.balance(i).currency, aEncoding=>false)
        ||xml_Util.CreateAttr('CurrencyAbbr', Refs.GetCurrencyAbbr(fAuthBalanceResp.balance(i).currency), aEncoding=>false)
        ||xml_Util.CreateAttr('Type',         fAuthBalanceResp.balance(i).amount_type, aEncoding=>false)
        , aEncoding=>false
        );
  end loop;
  --
  if xml_Util.GetValueB(aXML, 'Balance', 'GetCheck', aMandatory=>false, aDefault=>false) then
    if fAuthBalanceResp.balance.count > 0 then
      aResponse := aResponse || xml_Util.OpenElement('Check');
    end if;
    for i in 1..fAuthBalanceResp.balance.count loop
      aResponse :=
        aResponse
      ||xml_Util.Element('Line', ServiceSupport.Num2Amount(fAuthBalanceResp.balance(i).amount, fAuthBalanceResp.balance(i).currency));
    end loop;
    if fAuthBalanceResp.balance.count > 0 then
      aResponse := aResponse || xml_Util.CloseElement('Check');
    end if;
  end if;

  aResponse := xml_Util.Element
               ( 'Balance'
               , aResponse
               , xml_Util.CreateAttr('Count', fAuthBalanceResp.balance.count)
               , aEncoding=>false
               , aCloseOnNewLine=>aResponse is not null
               );
end Balance;

---------
procedure StornStart(aXML XMLType, aResponse out varchar2, aTermInfo TTerminalInfo)
is
  Pn2$ constant varchar2(30) := 'StornStart';
  fAmount TDialogAmount;
  fAuthParameters TAuthParameters;
begin
  gDocType := Docs.DOC_OPER;
  gDocId            := xml_Util.GetValueN(aXML, 'StornStart/TransactionId', aMaxLen=>10);
  fAmount.amount    := xml_Util.GetValueN(aXML, 'StornStart/Amount', aFormat=>'999999999990D99');
  fAmount.currency  := xml_Util.GetValueN(aXML, 'StornStart/Amount', 'Currency', aMaxLen=>3);
  ReadAuthParam(aXML, Pn2$, true, fAuthParameters);

  OpPayment.StornStart(aTermInfo, gDocId, fAmount, fAuthParameters);
end StornStart;

---------
procedure StornResult(aXML XMLType, aResponse out varchar2, aTermInfo TTerminalInfo)
is
  fAmount TDialogAmount;
begin
  gDocType          := Docs.DOC_OPER;
  gDocId            := xml_Util.GetValueN(aXML, 'StornResult/TransactionId', aMaxLen=>10);
  fAmount.amount    := xml_Util.GetValueN(aXML, 'StornResult/Amount', aFormat=>'999999999990D99');
  fAmount.currency  := xml_Util.GetValueN(aXML, 'StornResult/Amount', 'Currency', 3);

  OpPayment.StornResult(aTermInfo, gDocId, fAmount, xml_Util.GetValueB(aXML, 'StornResult/Storned'));
end StornResult;

---------
procedure ParseSearchData(aXML XMLType, aRequestType varchar2, aFIO out nocopy tp_fio, aAddress out nocopy tp_address, aSurnameMandatory boolean := true)
is
  fPrefix varchar2(100) := aRequestType || '/';
begin
  aFIO :=
    tp_fio
    ( surname   =>xml_Util.GetValueS(aXML, fPrefix || 'Name/Surname',       aMaxLen=>30, aMinLen=>2, aMandatory=>aSurnameMandatory)
    , first_name=>xml_Util.GetValueS(aXML, fPrefix || 'Name/FirstName',     aMaxLen=>30, aMandatory=>false)
    , patronymic=>xml_Util.GetValueS(aXML, fPrefix || 'Name/Patronymic',    aMaxLen=>30, aMandatory=>false)
    );
  aAddress :=
    tp_address
    ( city     =>xml_Util.GetValueS(aXML, fPrefix || 'Address/City',       aMaxLen=>30, aMandatory=>false)
    , street   =>xml_Util.GetValueS(aXML, fPrefix || 'Address/Street',     aMaxLen=>30, aMandatory=>false)
    , house    =>xml_Util.GetValueS(aXML, fPrefix || 'Address/House',      aMaxLen=>10, aMandatory=>false)
    , building =>xml_Util.GetValueS(aXML, fPrefix || 'Address/Building',   aMaxLen=>10, aMandatory=>false)
    , apartment=>xml_Util.GetValueS(aXML, fPrefix || 'Address/Apartment',  aMaxLen=>10, aMandatory=>false)
    );
end ParseSearchData;

---------
procedure SearchAccount(aXML XMLType, aResponse out varchar2, aTermInfo TTerminalInfo)
is
  Pn2$ constant varchar2(30) := 'SearchAccount';

  fServiceNo int;
  fServiceExtraNo int;

  fFIO      tp_fio;
  fAddress  tp_address;
  fAccounts tp_sp_found_accounts;
begin
  ParseSearchData(aXML, 'SearchAccount', fFIO, fAddress);
  DecodeServiceId
  ( xml_Util.GetValueS(aXML, 'SearchAccount/ServiceInfoId', 'ServiceIdType', 20, aMandatory=>false)
  , xml_Util.GetValueS(aXML, 'SearchAccount/ServiceId', aMaxLen=>30)
  , fServiceNo, fServiceExtraNo, aTermInfo.terminal, aTermInfo.client_ident_type, aTermInfo.client_ident);

  OpPayment.SearchAccount(aTermInfo, fServiceNo, fFIO, fAddress, fAccounts);

  for i in 1 .. fAccounts.count loop
    aResponse := aResponse ||
      xml_Util.Element('Account', fAccounts(i).account_no
      , xml_Util.CreateAttr('Name', fAccounts(i).fio) || xml_Util.CreateAttr('Address', fAccounts(i).address));
  end loop;
  if fAccounts.count > 0 then
    aResponse :=
       xml_Util.Element
       ( Pn2$
       , xml_Util.Element('AccountList', aResponse, aEncoding=>false, aCloseOnNewLine=>true)
       , aEncoding=>false, aCloseOnNewLine=>true
       );
  end if;
end SearchAccount;

---------
procedure SearchNameAndAddr(aXML XMLType, aResponse out varchar2, aTermInfo TTerminalInfo)
is
  Pn2$ constant varchar2(30) := 'SearchNameAndAddr';

  fFIO      tp_fio;
  fAddress  tp_address;
  fAccounts tp_sp_found_accounts;
begin
  ParseSearchData(aXML, 'SearchNameAndAddr', fFIO, fAddress, false);

  OpPayment.SearchNameAndAddr(aTermInfo, fFIO, fAddress, fAccounts);

  for i in 1 .. fAccounts.count loop
    aResponse := aResponse ||
      xml_Util.Element('NameAndAddrId', fAccounts(i).account_no,
        xml_Util.CreateAttr('Name', fAccounts(i).fio) || xml_Util.CreateAttr('Address', fAccounts(i).address),
        aIndentCount=>3);
  end loop;
  if fAccounts.count > 0 then
    aResponse :=
         xml_Util.OpenElement(Pn2$, aIndentCount=>1)
      || xml_Util.Element('NameAndAddrList', aResponse, aEncoding=>false, aCloseOnNewLine=>true)
      || xml_Util.CloseElement(Pn2$, aIndentCount=>1);
  end if;
end SearchNameAndAddr;

---------
procedure FilterList(aXML XMLType, aResponse out varchar2, aTermInfo TTerminalInfo)
is
  Pn2$ constant varchar2(30) := 'FilterList';
begin
  for cFlt in (select * from ref_service_filter order by seq_no) loop
    xml_Util.AddElementToBuff(aResponse, 'Filter', cFlt.name,
        xml_Util.CreateAttr('Id', cFlt.filter_type, aEncoding=>false)
      ||xml_Util.CreateAttr('DataType', cFlt.value_datatype, ServiceSupport.SDT_STRING, aEncoding=>false)
      ||xml_Util.CreateAttr('DataFormat', cFlt.data_format)
      ||xml_Util.CreateAttr('MinLength', cFlt.min_value_len, aEncoding=>false)
      ||xml_Util.CreateAttr('MaxLength', cFlt.max_value_len, aEncoding=>false)
      , aIndentCount=>2);
  end loop;

  aResponse := xml_Util.Element(Pn2$, aResponse, aEncoding=>false, aCloseOnNewLine=>true, aIndentCount=>1);
end FilterList;

---------
procedure TestSession
( aXml                   XMLType
, aTerminal              varchar2
, aSID               out varchar2
, aSesValidated      out boolean
, aCheckWhenNotFound     boolean := true
, aAllowStaleSession     boolean := false
)
is
  fParams tp_cl_param_values;
begin
  if aXml is not null and aXml.existsNode('Session') = 1 then
    gDocType := Docs.DOC_CLIENT_SESSION;
    aSID := xml_Util.GetValueS(aXML, 'Session', 'SID', aMaxLen=>100);
    ClientAuth_Core.ValidateSession
    ( xml_Util.GetValueS(aXML, 'Session', 'IpAddress', aMaxLen=>15, aMandatory=>false, aDefault=>GetSingleIpAddress)
    , aSID
    , xml_Util.GetValueB(aXML, 'Session', 'Prolong', aMandatory=>false, aDefault=>true)
    , gDocId
    , aTerminal
    , aTerminalVersion=>xml_Util.GetValueS(aXML, 'TerminalId', 'Version', aMaxLen=>30, aMandatory=>false)
    , aAllowStaleSession=>aAllowStaleSession
    );
    gContextDocType := gDocType;
    gContextDocId   := gDocId;

    if Util.IsBitNotSet(ClientAuth_Core.GetLoginTypeOptions(ClientAuth_Core.GetSessionLoginType(aSID)), ClientAuth_Core.LOGIN_TYPE$OPT$NO_SES_PARAMS) then
      fParams := tp_cl_param_values();
      for cP in
      ( select *
          from XMLTable
          ( '/Session/Parameter' passing aXML
            columns
              val varchar2(1000) path 'text()'
            , id  varchar2(1000) path '@Id'
          )
      ) loop
        fParams.extend;
        fParams(fParams.count) := tp_cl_param_value
                                  ( xml_Util.GetValueS(cP.id, 'Session/Parameter@Id', 30)
                                  , xml_Util.GetValueS(cP.val, 'Session/Parameter', 255, aMandatory=>false)
                                  );
      end loop;
      ClientAuth_Core.ValidateSessionParam(aSID, fParams);
      aSesValidated := fParams.count > 0;
    end if;
  else
    Util.CheckErr
    (     aCheckWhenNotFound
      and Refs.IsTerminalInGroup(aTerminal
          , RefParam.GetParamValueAsNumDef(ClientAuth_Core.SYS_PRM_TERMINALS, null, ClientAuth_Core.SUB_SYSTEM)
          , aNullGroupAs=>false
          )
    , 'Tag "Session" not found in request');
  end if;
end TestSession;

---------
function PrintRefresh(aSID varchar2) return varchar2
is
  fRefresh ClientAuth_Core.TRefresh := ClientAuth_Core.GetRefresh(aSID);
  fResult  varchar2(32000);
  fType    varchar2(30) := fRefresh.first;
  fClient  boolean := false;
begin
  while fType is not null loop
    if fType = Refs.CLIENT_ID_TYPE_CLIENT then
      fClient := true;
    else
      if fRefresh(fType).count = 0 then
        fResult := fResult || xml_Util.Element('Product', aElementAttr => xml_Util.CreateAttr('ProductType', fType));
      else
        declare
          fId varchar2(30) := fRefresh(fType).first;
        begin
          while fId is not null loop
            fResult := fResult || xml_Util.Element('Product', aElementAttr => xml_Util.CreateAttr('ProductType', fType) || xml_Util.CreateAttr('Id', fId));
            fId := fRefresh(fType).next(fId);
          end loop;
        end;
      end if;
    end if;
    fType := fRefresh.next(fType);
  end loop;
  return
    xml_Util.Element
    ( 'Refresh'
    , aElementVal     => fResult
    , aElementAttr    => xml_Util.CreateAttr('Client', fClient, aDefVal=>false)
    , aEncoding       => false
    , aCloseOnNewLine => fResult is not null
    , aMandatory      => false
    );
end PrintRefresh;

---------
function PrintSession(aSID varchar2, aTerminal varchar2, aSesParamRequiered boolean := false) return varchar2
is
begin
  return
    case when aSID is not null then
      xml_Util.Element
      ( 'Session'
      , aElementVal  => PrintRefresh(aSID)
      , aElementAttr => xml_Util.CreateAttr('Expired', ClientAuth_Core.GetSessionExpired(aSid, aTerminal))
                     || xml_Util.CreateAttr('ParametersRequired', aSesParamRequiered, aDefVal=>false)
      , aEncoding    => false
      , aMandatory   => false
      , aIndentCount => 1
      )
    end;
end PrintSession;

---------
procedure Request(XML clob, aResponse out nocopy clob, aIsHttp boolean) -- main
is
  Pn2$ constant varchar2(30) := 'Request';

  fReqRecieved timestamp := systimestamp;
  fXML XMLType;
  fXMLToLog XMLType;
  fRequestType varchar2(100);
  fCommonResponse varchar2(32767);
  fStrResponse varchar2(32767);
  fArrResponse Util.TStrArr;
  fSID varchar2(100);

  fRootElement varchar2(100);
  fTermInfo TTerminalInfo;
  fCashWP varchar2(8);

  fFuncErrText varchar2(2000);
  fOutAuthParameters TAuthParameters;
  fSignSalt obj_abonent.signature_salt%type;
  fErrorClass int;
  fReqId int;
  ---------
  procedure PrepareResponse(aErrText varchar2 := null)
  is
    fStarted timestamp with time zone := systimestamp;
    fInfo TExtraInfo;
    fRespLen int := 0;
    --
    procedure Prn(aValue varchar2)
    is
    begin
      aResponse := aResponse || aValue;
    end;
  begin
    Prn(xml_Util.XML_HEADER || xml_Util.OpenElement(ROOTELEMENT_RESPONSE, aLeftBR=>false));
    Prn(xml_Util.Element('ServerTime', to_char(sysdate, 'yyyymmddhh24miss'), aIndentCount=>1, aEncoding=>false));
    Prn(PrintSession(fSID, fTermInfo.terminal, fTermInfo.ses_params_required));
    if fOutAuthParameters.count > 0 then
      fCommonResponse := fCommonResponse || xml_Util.OpenElement('AuthorizationDetails', aIndentCount=>1);
      for i in 1 .. fOutAuthParameters.Count loop
        xml_Util.AddElementToBuff(fCommonResponse, 'Parameter', fOutAuthParameters(i).value, xml_Util.CreateAttr('Name', fOutAuthParameters(i).name), 2);
      end loop;
      fCommonResponse := fCommonResponse || xml_Util.CloseElement('AuthorizationDetails', 1);
    end if;

    if aErrText is not null then
      ServiceSupport.StrToInfo(aErrText, fTermInfo.screen_width, fInfo);
      fCommonResponse :=
           fCommonResponse
        || xml_Util.OpenElement('Error'
           ,    xml_Util.CreateAttr('Count', fInfo.count, aEncoding=>false)
             || xml_Util.CreateAttr('Class', fErrorClass)
           , aLeftBR=>fCommonResponse is not null);
      for i in 1 .. fInfo.Count loop
        xml_Util.AddElementToBuff(fCommonResponse, 'ErrorLine', rtrim(fInfo(i).StrInfo), xml_Util.CreateAttr('Idx', i, aEncoding=>false), 1);
      end loop;
      fCommonResponse := fCommonResponse || xml_Util.CloseElement('Error');
      Prn(fCommonResponse);
    else
      Prn(fCommonResponse);
      if fStrResponse is not null then
        Prn(fStrResponse);
      else
        if fArrResponse is not null and fArrResponse.Count <> 0 then
          for i in fArrResponse.first .. fArrResponse.last loop
            Prn(fArrResponse(i) || chr(10));
          end loop;
        end if;
      end if;
    end if;
    Prn(xml_Util.CloseElement(ROOTELEMENT_RESPONSE));
    if systimestamp - fStarted > interval '1' second then
      LogWork.NotifyFmt(Pn1$, Pn2$, '<=- Prepared in %s: Arr.count=%d, clob.len=%d',  systimestamp - fStarted, fArrResponse.count, length(aResponse));
    end if;
    if aIsHttp then
      owa_util.mime_header(ccontent_type=>'text/xml', bclose_header => false);
      if fSignSalt is not null then
        declare
          fSign varchar2(2000);
        begin
          fSign := CGI_PARAM_SIGNATURE || ': '|| GetMsgSignature(fSignSalt, aResponse);
          LogWork.Notify(Pn1$, Pn2$, fSign);
          htp.p(fSign);
        end;
      end if;
      owa_util.http_header_close;
      for i in 0 .. floor(length(aResponse) / PACK_LENGTH) loop
        htp.prn(substr(aResponse, 1 + i*PACK_LENGTH, PACK_LENGTH));
      end loop;
    end if;
    Op_Online.RegAnswer
    ( fReqId
    , case when fArrResponse.count > 100 then substr(aResponse, 1, 2000) else aResponse end
    , aDataLength=>length(aResponse)
    , aIsError=>aErrText is not null
    , aDocType=>gDocType, aDocId=>gDocId
    , aContextDocType=>gContextDocType, aContextDocId=>gContextDocId
    );
  end PrepareResponse;
begin
  ClientAuth_Core.ClearRefresh;
  gDocType := null;
  gDocId   := null;
  gContextDocType := null;
  gContextDocId   := null;

  Util.CheckErr(XML is null, 'Тело запроса отсутствует');
  fXML := XMLType(XML);
  fXMLToLog := fXML;

  declare
    procedure MaskIdent(aXPath varchar2, aIdentType varchar2, aIdent varchar2)
    is
      fMaskedIdent op_oper.client_ident%type;
    begin
      if aIdent is not null and aIdentType is not null then
        fMaskedIdent := Refs.HideIdent(aIdentType, aIdent, '*');
        if fMaskedIdent <> aIdent then
          select updatexml(fXMLToLog, aXPath || '/text()', fMaskedIdent) into fXMLToLog from dual;
        end if;
      end if;
    end MaskIdent;
  begin
    -- проверка данных запроса
    fRootElement := substr(fXML.getRootElement(), 1, 100);
    Util.CheckErr(fRootElement <> ROOTELEMENT_REQUEST, 'Некорректный корневой элемент "%s!=%s"', fRootElement, ROOTELEMENT_REQUEST);
    fXML := fXML.extract('/' || ROOTELEMENT_REQUEST || '/*');
    --
    fRequestType := xml_Util.GetValueS(fXML, 'RequestType', aMaxLen=>20, aDecoding=>false);
    if fRequestType not in
        ( 'FilterList'
        , 'ServiceList'
        , 'ServiceTree'
        , 'ServiceInfo'
        , 'TransactionStart'
        , 'TransactionsStart'
        , 'TransactionResult'
        , 'TransactionsResult'
        , 'Balance'
        , 'StornStart'
        , 'StornResult'
        , 'SearchAccount'
        , 'SearchNameAndAddr'
        )
    then
      Util.RaiseErr('Неподдерживаемый тип запроса (RequestType:%s) для %s.%s'
      , fRequestType, Pn1$, Pn2$
      );
    end if;
    --
    fTermInfo.client_ident      := xml_Util.GetValueS(fXML, 'ClientId',                      aMaxLen=>30, aMandatory=>false);
    fTermInfo.client_ident_type := xml_Util.GetValueS(fXML, 'ClientId', aAttrName=>'IdType', aMaxLen=>10, aMandatory=>false);
    MaskIdent('/' || fRootElement || '/ClientId', fTermInfo.client_ident_type, fTermInfo.client_ident);

    fTermInfo.auth_ident_type := xml_Util.GetValueS(fXML, 'AuthClientId', aAttrName=>'IdType', aMaxLen=>10, aMandatory=>false);
    if fTermInfo.auth_ident_type is not null then
      fTermInfo.auth_ident := xml_Util.GetValueS(fXML, 'AuthClientId',                      aMaxLen=>30, aMandatory=>false);
    end if;
    MaskIdent('/' || fRootElement || '/AuthClientId', fTermInfo.auth_ident_type, fTermInfo.auth_ident);

    HideAuthParams(nvl(fTermInfo.auth_ident_type, fTermInfo.client_ident_type), fXMLToLog);
    --! - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
    fTermInfo.terminal          := xml_Util.GetValueS(fXML, 'TerminalId',                     aMaxLen=>30);
    fTermInfo.terminal_time     := xml_Util.GetValueD(fXML, 'TerminalTime');
    fTermInfo.cashin_period_no  := xml_Util.GetValueN(fXML, 'TerminalId', 'CashInPeriodNo',   aMaxLen=>8, aMandatory=>false);
    fCashWP                     := xml_Util.GetValueS(fXML, 'TerminalId', 'CashWorkPlaceId',  aMaxLen=>8, aMandatory=>false);
    fTermInfo.interactive       := true;
    --
    fTermInfo.screen_width      := xml_Util.GetValueN(fXML, 'TerminalCapabilities/ScreenWidth', aMaxLen=>2, aMinLen=>2);
    fTermInfo.check_width       := xml_Util.GetValueN(fXML, 'TerminalCapabilities/CheckWidth',  aMaxLen=>2, aMinLen=>2, aDefault=>fTermInfo.screen_width);
    --
    CheckTerminal(aIsHttp, fTermInfo.terminal, fTermInfo.terminal_type, fSignSalt, fCashWP);
    TestSignature(fSignSalt, XML);
  exception
    when others then
      fReqId := Op_Online.RegRequest
                ( null, null, nvl(fRequestType, '?'), xml_util.SerializeXML(fXMLToLog)
                , aAddress=>GetIpAddress, aTerminal=> fTermInfo.terminal, aDirection=>Refs.FILE_DIR_IN, aStartProcessingTime=>fReqRecieved
                , aMaskingRules=>cReqMaskingRules
                );
      raise;
  end;
  fReqId := Op_Online.RegRequest
            ( null, null, fRequestType, xml_util.SerializeXML(fXMLToLog)
            , aAddress=>GetIpAddress, aTerminal=>fTermInfo.terminal, aDirection=>Refs.FILE_DIR_IN, aStartProcessingTime=>fReqRecieved
            , aMaskingRules=>cReqMaskingRules
            );
  --! - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
  declare
    --
    procedure InitClientId(aIdentType varchar2, aIdent varchar2)
    is
    begin
      if    fTermInfo.cl_client_id is null
        and aIdentType is not null
        and aIdent is not null
        and Refs.IdentSupportOption(aIdentType, Refs.CLIENT_ID_OPT_IDENTIFICATION)
      then
        fTermInfo.cl_client_id := ClClient.FindClientIdByIdent(aIdentType, aIdent);
      end if;
    end;
  begin
    declare
      fIsTrxResult boolean := fRequestType = 'TransactionResult';
    begin
      TestSession(fXML.extract('/Session'), fTermInfo.terminal, fSID, fTermInfo.ses_auth_checked, aAllowStaleSession=>fIsTrxResult);
    exception
      when Util.eStandardException then
        if fIsTrxResult then
          -- ugly but works :(
          gDocType := Docs.DOC_OPER;
          gDocId   := xml_Util.GetValueN(fXML, '//TransactionId', aMaxLen=>10, aMinNumValue=>0);
        end if;
        raise;
    end;

    if fSID is not null then
      fTermInfo.cl_client_id := ClientAuth_Core.GetClientId(fSID);

      if    fTermInfo.auth_ident_type is null
        and fTermInfo.client_ident_type <> Refs.CLIENT_ID_TYPE_CLIENT
        and Refs.IdentSupportOption(fTermInfo.client_ident_type, Refs.CLIENT_ID_OPT_PAY_TOOL)
      then
        fTermInfo.auth_ident_type := fTermInfo.client_ident_type;
        fTermInfo.auth_ident   := fTermInfo.client_ident;
      end if;

      if fTermInfo.auth_ident_type is not null then
        -- test valid auth ident
        fTermInfo.actual_ident_id := ClClient.GetClientPayToolId(fTermInfo.cl_client_id, fTermInfo.auth_ident_type, fTermInfo.auth_ident);
        fTermInfo.auth_ident      := ClClient.GetIdent(fTermInfo.actual_ident_id);
      else
        declare
          fIdents tp_cl_idents;
        begin
          fIdents := ClClient.GetIdents(fTermInfo.cl_client_id, Refs.CLIENT_ID_TYPE_PAY_TOOL);
          if fIdents is not null and fIdents.count > 0 then
            fTermInfo.actual_ident_id := fIdents(1).id;
            fTermInfo.auth_ident_type := fIdents(1).ident_type;
            fTermInfo.auth_ident      := ClClient.GetIdent(fIdents(1).id);
          end if;
        end;
      end if;

      if fTermInfo.client_ident_type = Refs.CLIENT_ID_TYPE_CLIENT then
        Util.CheckErr('$'||fTermInfo.client_ident <> '$'||fTermInfo.cl_client_id, 'Неверные идентификационные данные');
      else
        fTermInfo.client_ident_type := Refs.CLIENT_ID_TYPE_CLIENT;
        fTermInfo.client_ident      := fTermInfo.cl_client_id;
      end if;
    else
      fTermInfo.client_ident_type := xml_Util.GetValueS(fTermInfo.client_ident_type, 'ClientId/@IdType', aMaxLen=>10); -- проверяем обязательность
      Util.CheckErr(fTermInfo.client_ident_type = Refs.CLIENT_ID_TYPE_CLIENT, 'Сессия не найдена');

      InitClientId(fTermInfo.client_ident_type, fTermInfo.client_ident);
      InitClientId(fTermInfo.auth_ident_type,   fTermInfo.auth_ident);
    end if;
    OpPayment.NormalizeTerminalInfo(fTermInfo);
  end;
  --
  fTermInfo.any_amount        := xml_Util.GetValueB(fXML, 'TerminalCapabilities/AnyAmount',         aMandatory=>false, aDefault=>true);
  fTermInfo.bool_parameters   := xml_Util.GetValueB(fXML, 'TerminalCapabilities/BooleanParameter',  aMandatory=>false, aDefault=>false);
  declare
    fXmlDS XMLType := fXML.extract('TerminalCapabilities/InputDataSources');
  begin
    fTermInfo.input_data_sources := ServiceSupport.INPUT_DATA_SRC_KEYBOARD;
    if fXmlDS is not null then
      declare
        fDSNames Util.TStrs := Util.TStrs(ServiceSupport.INPUT_DATA_SRC_NAME_LOOKUP, ServiceSupport.INPUT_DATA_SRC_NAME_CARD);
        fDSMasks Util.TInts := Util.TInts(ServiceSupport.INPUT_DATA_SRC_LOOKUP,      ServiceSupport.INPUT_DATA_SRC_CARD);
      begin
        for i in 1 .. fDSNames.count loop
          if fXmlDS.existsNode('/InputDataSources/InputDataSource="'||fDSNames(i)||'"') > 0 then
            Util.BitOr(fTermInfo.input_data_sources, fDSMasks(i));
          end if;
        end loop;
      end;
    end if;
  end;
  --
  if fSID is null then -- В SSO игнорируем присылаемый номер плательщика ЕРИП (ИБ его "слишком" запоминает)
    fTermInfo.extra_ident        := xml_Util.GetValueS(fXML, 'ExtraClientId',                       aMaxLen=>19, aMandatory=>false);
    if fTermInfo.extra_ident is not null then
      fTermInfo.extra_ident_type := xml_Util.GetValueS(fXML, 'ExtraClientId', aAttrName=>'IdType',  aMaxLen=>10, aMandatory=>(fTermInfo.extra_ident is not null)
                                    , aConstList=>tp_varchar2_100_table('ERIP')
                                    );
    end if;
  end if;

  declare
    fXmlCur XMLType := fXML.extract('TerminalCapabilities/Currencies');
  begin
    if fXmlCur is not null then
      for cCur in
      ( select *
          from XMLTable
          ( '/Currencies/Currency' passing fXmlCur
            columns
              currency  varchar2(1000) path 'text()'
            , precision varchar2(1000) path '@AmountPrecision'
          )
      ) loop
        fTermInfo.currencies(xml_Util.GetValueN(cCur.currency, 'Currencies/Currency', 3)).precision :=
          xml_Util.GetValueN(cCur.precision, 'Currencies/Currency/@AmountPrecision', aMandatory=>false, aFormat=>'999999999990D99');
      end loop;
    end if;
  end loop;
  --
  Util.CheckErr(fXML.existsNode(fRequestType) <> 1, 'Не найден элемент "%s/%s"', ROOTELEMENT_REQUEST, fRequestType);

  CrAccessIsDenied(aTerminal => fTermInfo.terminal, aRequest => fRequestType, aTerminalType => fTermInfo.terminal_type);

  fXML := fXML.extract('/' || fRequestType);
  case fRequestType
    when 'FilterList'         then -- Запрос списка фильтров
      FilterList(fXML, fStrResponse, fTermInfo);
    when 'ServiceList'        then -- Запрос списка услуг
      ServiceList(fXML, fArrResponse, fTermInfo);
    when 'ServiceTree'        then -- Запрос дерева услуг
      ServiceTree(fXML, fArrResponse, fTermInfo, aIsSoftClubCashWorkPlace=>fCashWP is not null);
    when 'ServiceInfo'        then -- Запрос параметров услуги
      ServiceInfo(fXML, fStrResponse, fTermInfo);
    when 'TransactionStart'   then -- Запрос на выполнение оплаты
      fFuncErrText := TransactionStart(fXML, fStrResponse, fTermInfo, fOutAuthParameters);
    when 'TransactionsStart'  then -- Запрос на выполнение комплексной оплаты
      TransactionsStart(fXML, fStrResponse, fTermInfo, fOutAuthParameters);
    when 'TransactionResult'  then -- Извещение о результате оплаты
      fFuncErrText := TransactionResult(fXML, fStrResponse, fTermInfo, fOutAuthParameters);
      if fFuncErrText is null and fSID is not null then
        ClientAuth_Core.AddRefresh(fTermInfo.actual_auth_ident_type, fTermInfo.actual_ident_id);
        ClientAuth_Core.AddRefresh(Refs.CLIENT_ID_TYPE_PAY_TOOL);
      end if;
    when 'TransactionsResult'  then -- Извещение о результате комплексной оплаты
      fFuncErrText := TransactionsResult(fXML, fStrResponse, fTermInfo, fOutAuthParameters);
      if fFuncErrText is null and fSID is not null then
        ClientAuth_Core.AddRefresh(fTermInfo.actual_auth_ident_type, fTermInfo.actual_ident_id);
        ClientAuth_Core.AddRefresh(Refs.CLIENT_ID_TYPE_PAY_TOOL);
      end if;
    when 'Balance'            then -- Запрос баланса по идентификатору плательщика
      Balance(fXML, fStrResponse, fTermInfo, fOutAuthParameters);
    when 'StornStart'         then -- Запрос на сторнирование оплаты
      StornStart(fXML, fStrResponse, fTermInfo);
    when 'StornResult'        then -- Подтверждение сторнирования оплаты
      StornResult(fXML, fStrResponse, fTermInfo);
    when 'SearchAccount'      then -- Поиск лицевого счёта
      SearchAccount(fXML, fStrResponse, fTermInfo);
    when 'SearchNameAndAddr'  then -- Поиск плательщика
      SearchNameAndAddr(fXML, fStrResponse, fTermInfo);
    else
      Util.RaiseErr('Неподдерживаемый тип запроса (RequestType:%s) для %s.%s', fRequestType, Pn1$, Pn2$);
  end case;

  if gDocType is null and gDocId is null then
    if fSID is not null then
      gDocId := ClientAuth_Core.GetClientSessionId(fSID);
    end if;
    if gDocId is not null  then
      gDocType := Docs.DOC_CLIENT_SESSION;
    elsif fTermInfo.cl_client_id is not null then
      gDocType := Docs.DOC_CLIENT;
      gDocId   := fTermInfo.cl_client_id;
    end if;
  end if;

  commit;
  Util.CheckErrText(fFuncErrText);
  PrepareResponse;
exception
  when xml_Util.eFailedXML then
    LogWork.NotifyException(Pn1$, Pn2$);
    fReqId := Op_Online.RegRequest
              ( null, null, nvl(fRequestType, '?'), xml, aAddress=>GetIpAddress
              , aTerminal=>fTermInfo.terminal, aDirection=>Refs.FILE_DIR_IN, aStartProcessingTime=>fReqRecieved
              , aMaskingRules=>cReqMaskingRules
              );
    PrepareResponse('Некорректный XML');
  when others then
    rollback;
    LogWork.NotifyException(Pn1$, Pn2$);
    PrepareResponse(Util.NormalizeSqlErrMGetErrorClass(aShortTextForSystemError=>true, aErrorClass=>fErrorClass));
end Request;

---------
procedure Request(XML clob)
is
  fResponse clob;
begin
  WorkaroundForModPlSqlBug(Pn1$, 'Request');
  Request(XML, fResponse, aIsHttp=>true);
end Request;

---------
function Request(XML clob) return clob
is
  pragma autonomous_transaction;
  fResponse clob;
begin
  Request(XML, fResponse, aIsHttp=>false);
  commit;
  return fResponse;
end Request;


--! - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

---------
procedure CheckDuplicate(aHdr tp_msg_admin_header, aXML XMLType, aResponse out varchar2)
is
  fDupCheck OpPayment.TDupCheck;
begin
  fDupCheck.terminal      := aHdr.terminal;
  fDupCheck.client_id     := aHdr.cl_client_id;
  fDupCheck.oper_id       := xml_Util.GetValueN(aXML, 'TransactionId', aMaxLen=>10, aMinNumValue=>1);
  fDupCheck.check_width   := xml_Util.GetValueN(aXML, 'CheckWidth', aMaxLen=>2, aMinNumValue=>10, aMandatory=>false, aDefault=>50);
  if aHdr.cl_client_id is null then
    fDupCheck.auth_id       := xml_Util.GetValueS(aXML, 'AuthClientId', aMaxLen=>20, aMandatory=>false);
    fDupCheck.auth_id_type  := xml_Util.GetValueS(aXML, 'AuthClientId', aAttrName=>'IdType', aMaxLen=>10, aMandatory=>fDupCheck.auth_id is not null);
  end if;

  gDocType := Docs.DOC_OPER;
  gDocId   := fDupCheck.oper_id;

  OpPayment.CheckDuplicate(fDupCheck);

  if fDupCheck.check_header.count > 0 then
    aResponse := xml_Util.OpenElement('CheckHeader', aPreserveWhitespaces=>true);
    for i in 1..fDupCheck.check_header.count loop
      aResponse := aResponse || xml_Util.Element('CheckLine', rtrim(fDupCheck.check_header(i).StrInfo));
    end loop;
    aResponse := aResponse || xml_Util.CloseElement('CheckHeader');
  end if;

  if fDupCheck.check_footer.count > 0 then
    aResponse := aResponse || xml_Util.OpenElement('CheckFooter', aPreserveWhitespaces=>true);
    for i in 1..fDupCheck.check_footer.count loop
      aResponse := aResponse || xml_Util.Element('CheckLine', rtrim(fDupCheck.check_footer(i).StrInfo));
    end loop;
    aResponse := aResponse || xml_Util.CloseElement('CheckFooter');
  end if;
end CheckDuplicate;

---------
procedure GetUserServices(aHdr tp_msg_admin_header, aXML XMLType, aArrResponse out Util.TStrArr)
is
  fClnt ServiceSupport.TClientAndServicesInfo;
begin
  fClnt.client.id := aHdr.cl_client_id;

  if fClnt.client.id is null then
    fClnt.client.id :=
      ClClient.FindClientIdByIdent(xml_Util.GetValueS(aXML, 'ClientId', 'IdType', aMaxLen=>10), xml_Util.GetValueS(aXML, 'ClientId', aMaxLen=>20));
  end if;
  gDocType := Docs.DOC_CLIENT;
  gDocId   := fClnt.client.id;

  fClnt.client_service_id := xml_Util.GetValueS(aXML, 'Id', aMaxLen=>30, aMandatory=>false);

  ServiceSupport.GetClientInfo(aHdr.terminal, fClnt);

  aArrResponse(aArrResponse.count) :=
    xml_Util.Element('ClientInfo'
      , xml_Util.Element('FIO',      fClnt.client.fio,     aMandatory=>false)
      ||xml_Util.Element('Address',  fClnt.client.address, aMandatory=>false)
      ||xml_Util.Element('Email',    fClnt.client.email,   aMandatory=>false)
      ||xml_Util.Element('Phone',    fClnt.client.phone,   aEncoding=>false, aMandatory=>false)
      , aEncoding=>false, aCloseOnNewLine=>true);

  if fClnt.services.count > 0 then
    aArrResponse(aArrResponse.count) := xml_Util.OpenElement('Services', aIndentCount=>2);
    for i in 1..fClnt.services.count loop
      aArrResponse(aArrResponse.count) :=
           xml_Util.OpenElement('Service')
        || xml_Util.Element('Id',                   fClnt.services(i).id
           , xml_Util.CreateAttr('ServiceId', fClnt.services(i).service_id)
           ||case when fClnt.services(i).service_id is not null then xml_Util.CreateAttr('ServiceIdType', STP_NO) end
           , aEncoding=>false)
        || xml_Util.Element('Name',                 fClnt.services(i).name)
        || xml_Util.Element('PersonalAccount',      fClnt.services(i).personal_account)
        || xml_Util.Element('PersonalAccountName',  fClnt.services(i).personal_account_name, aMandatory=>false)
        || xml_Util.Element('Enabled',              fClnt.services(i).enabled, aMandatory=>false, aDefault=>true)
        || xml_Util.Element('GroupName',            fClnt.services(i).group_name
           , xml_Util.CreateAttr('Idx',             fClnt.services(i).seq_no_in_group))
        || xml_Util.Element('Expired',              fClnt.services(i).expired, 'yyyymmdd', aMandatory=>false)
        || xml_Util.Element('NextPay',              fClnt.services(i).next_pay, 'yyyymmdd', aMandatory=>false)
        || xml_Util.Element('Mode',                 nullif(fClnt.services(i).auto_mode, Cl_Service_Schedule.AUTO_MODE_PAY)
           , aEncoding=>false, aMandatory=>false)
        || xml_Util.Element('PaymentAmount',
             RCore.FmtAmount(fClnt.services(i).payment_amount, fClnt.services(i).currency, Fmt=>Rcore.fSimple),
             xml_Util.CreateAttr('Currency', fClnt.services(i).currency, aEncoding=>false), aEncoding=>false);

      if fClnt.services(i).params.count > 0 then
        aArrResponse(aArrResponse.count) := xml_Util.OpenElement('Parameters', aIndentCount=>4);
        for j in 1..fClnt.services(i).params.count loop
          aArrResponse(aArrResponse.count) :=
                   xml_Util.Element('Parameter', substr(fClnt.services(i).params(j).name, 1, 99),
                   xml_Util.CreateAttr('Id', fClnt.services(i).params(j).type, aEncoding=>false)
                || xml_Util.CreateAttr('DataType', fClnt.services(i).params(j).data_type, ServiceSupport.SDT_STRING, aEncoding=>false)
                || xml_Util.CreateAttr('DataFormat', fClnt.services(i).params(j).data_format)
                || xml_Util.CreateAttr('MinLength', least(255, fClnt.services(i).params(j).min_length)
                   , 0, aEncoding=>false)
                || xml_Util.CreateAttr('MaxLength', least(255, fClnt.services(i).params(j).max_length)
                   ,    aEncoding=>false)
                || xml_Util.CreateAttr('Value', substr(fClnt.services(i).params(j).data_value, 1, 255)),
                aIndentCount=>5);
        end loop;
        aArrResponse(aArrResponse.count) := xml_Util.CloseElement('Parameters', 4);
      end if;

      if fClnt.services(i).pa_enable is not null then
        aArrResponse(aArrResponse.count) :=
             xml_Util.OpenElement('PayAuto', aIndentCount=>4)
          || xml_Util.Element('Enabled', case when fClnt.services(i).pa_enable then Util.YES else Util.NO end, aIndentCount=>5, aEncoding=>false)
          || xml_Util.Element('MinBalance', RCore.FmtAmount(fClnt.services(i).pa_min_balance, fClnt.services(i).currency, Fmt=>Rcore.fSimple), aIndentCount=>5, aEncoding=>false)
          || xml_Util.Element('PaymentAmount', RCore.FmtAmount(fClnt.services(i).pa_pay_amount, fClnt.services(i).currency, Fmt=>Rcore.fSimple), aIndentCount=>5, aEncoding=>false)
          || xml_Util.CloseElement('PayAuto', 4);
      end if;

      if fClnt.services(i).schedule.count > 0 then
        aArrResponse(aArrResponse.count) := xml_Util.OpenElement('Schedules', aIndentCount=>4);
        for j in 1..fClnt.services(i).schedule.count loop
          aArrResponse(aArrResponse.count) :=
               xml_Util.OpenElement('Schedule', aIndentCount=>5)
            || xml_Util.Element('FirstStart', to_char(fClnt.services(i).schedule(j).first_start, 'yyyymmdd'), aIndentCount=>6, aEncoding=>false)
            || xml_Util.Element( 'PeriodScale', fClnt.services(i).schedule(j).period_scale, aIndentCount=>6
                               , aElementAttr => case when fClnt.services(i).schedule(j).period_length <> 1 then xml_Util.CreateAttr('Length', fClnt.services(i).schedule(j).period_length) end
                               )
            || xml_Util.Element('Describe', fClnt.services(i).schedule(j).descr, aIndentCount=>6)
            || xml_Util.CloseElement('Schedule', 5);
        end loop;
        aArrResponse(aArrResponse.count) := xml_Util.CloseElement('Schedules', 4);
      end if;
      aArrResponse(aArrResponse.count) := xml_Util.CloseElement('Service', 3);
    end loop;
    aArrResponse(aArrResponse.count) := xml_Util.CloseElement('Services', 2);
  end if;
end GetUserServices;

---------
procedure SetUserServices(aHdr tp_msg_admin_header, aXML XMLType, aResponse out varchar2)
is
  fClnt ServiceSupport.TClientAndServicesInfo;
  fSrv  ServiceSupport.TClientService;
begin
  fClnt.client.id := aHdr.cl_client_id;
  if fClnt.client.id is null then
    fClnt.ident_id  := ClClient.FindIdentId
                       ( xml_Util.GetValueS(aXML, 'ClientId', 'IdType', aMaxLen=>10)
                       , xml_Util.GetValueS(aXML, 'ClientId', aMaxLen=>20)
                       , aRaiseNotFound=>false
                       );
    if fClnt.ident_id is null then
      fClnt.client.id := ClClient.FindClientIdByIdent
                         ( xml_Util.GetValueS(aXML, 'ClientId', 'IdType', aMaxLen=>10)
                         , xml_Util.GetValueS(aXML, 'ClientId', aMaxLen=>20)
                         );
    else
      fClnt.client.id := ClClient.GetIdentClientId(fClnt.ident_id);
    end if;
  end if;
  gDocType := Docs.DOC_CLIENT;
  gDocId   := fClnt.client.id;

  for cSrv in (select value(tbl) as xml from table(xmlSequence(aXML.extract('Services/Service'))) tbl) loop
    fSrv := null;
    fSrv.id := xml_Util.GetValueS(cSrv.xml, 'Service/Id', aMaxLen=>30);

    fSrv.received_enabled := cSrv.xml.existsNode('Service/Enabled') > 0;
    fSrv.enabled := xml_Util.GetValueB(cSrv.xml, 'Service/Enabled', aMandatory=>false, aDefault=>true);

    fSrv.received_group_name := cSrv.xml.existsNode('Service/GroupName') > 0;
    fSrv.group_name := xml_Util.GetValueS(cSrv.xml, 'Service/GroupName', aMandatory=>false);
    fSrv.seq_no_in_group := xml_Util.GetValueN(cSrv.xml, 'Service/GroupName', 'Idx', aMaxNumValue=>9999, aMandatory=>false);

    fSrv.received_expired := cSrv.xml.existsNode('Service/Expired') > 0;
    fSrv.expired := xml_Util.GetValueD(cSrv.xml, 'Service/Expired', aMandatory=>false, aFormat=>'yyyymmdd');

    fSrv.received_p_amount := cSrv.xml.existsNode('Service/PaymentAmount') > 0;
    fSrv.payment_amount := nullif(xml_Util.GetElementValue(cSrv.xml, 'Service/PaymentAmount',
      15, aType=>'N', aFormat=>'999999999990D99', aMandatory=>false), 0);

    fSrv.auto_mode := xml_Util.GetElementValue(cSrv.xml, 'Service/Mode', 1, aMandatory=>false,
      aConstList=>tp_varchar2_100_table(Cl_Service_Schedule.AUTO_MODE_PAY, Cl_Service_Schedule.AUTO_MODE_INFO));

    fSrv.received_pers_acc_name := cSrv.xml.existsNode('Service/PersonalAccountName') > 0;
    if fSrv.received_pers_acc_name then
      fSrv.personal_account_name := xml_Util.GetElementValue(cSrv.xml, 'Service/PersonalAccountName', 30, aMandatory=>false);
      declare
        cPat varchar2(99) := '^(\{([^}]*)\}\\\s*)?((\d+)\)\s*)?(.*)$';
      begin
        if regexp_like(fSrv.personal_account_name, cPat) then
          if regexp_replace(fSrv.personal_account_name, cPat, '\1') is not null then
            fSrv.received_group_name := true;
            fSrv.group_name := regexp_replace(fSrv.personal_account_name, cPat, '\2');
          end if;
          fSrv.seq_no_in_group := regexp_replace(fSrv.personal_account_name, cPat, '\4');
          fSrv.personal_account_name := regexp_replace(fSrv.personal_account_name, cPat, '\5');
        end if;
      end;
    end if;

    for cPrm in (select rownum as rn, value(tbl) as val from table(xmlSequence(cSrv.xml.extract('Service/Parameters/Parameter'))) tbl) loop
      fSrv.params(cPrm.rn).type := xml_Util.GetElementAttrValue(cPrm.val, 'Parameter', 'Id', 8, aType=>'N');
      fSrv.params(cPrm.rn).data_value := trim(xml_Util.GetElementValue(cPrm.val, 'Parameter', 255, aMandatory=>false));
    end loop;

    if cSrv.xml.existsNode('Service/PayAuto') > 0 then
      fSrv.pa_enable      := xml_Util.GetValueB(cSrv.xml, 'Service/PayAuto/Enabled', aMandatory=>false, aDefault=>true);
      fSrv.pa_min_balance := xml_Util.GetValueN(cSrv.xml, 'Service/PayAuto/MinBalance'
      , aMaxNumValue=>(10**14-1)/100, aFormat=>'999999999990D99', aMandatory=>fSrv.pa_enable);
      fSrv.pa_pay_amount  := xml_Util.GetValueN(cSrv.xml, 'Service/PayAuto/PaymentAmount'
      , aMaxNumValue=>(10**14-1)/100, aFormat=>'999999999990D99', aMandatory=>fSrv.pa_enable);
    end if;

    for cSchd in (select rownum as rn, value(tbl) as val from table(xmlSequence(cSrv.xml.extract('Service/Schedules/Schedule'))) tbl) loop
      fSrv.schedule(cSchd.rn).first_start := xml_Util.GetElementValueD(cSchd.val, 'Schedule/FirstStart', 8,
        aMandatory=>false, aFormat=>'yyyymmdd');
      fSrv.schedule(cSchd.rn).period_scale := xml_Util.GetValueS(cSchd.val, 'Schedule/PeriodScale', aMaxLen => 1,
        aConstList => tp_varchar2_100_table('O', 'D', 'W', '2' /*в будущем следует удалить!!!*/, 'M', 'Q', 'Y'));
      fSrv.schedule(cSchd.rn).period_length := xml_Util.GetValueN(cSchd.val, 'Schedule/PeriodScale', 'Length', aMaxNumValue => 999, aDefault => 1);
      if fSrv.schedule(cSchd.rn).period_scale = '2' then
        fSrv.schedule(cSchd.rn).period_scale  := 'W';
        fSrv.schedule(cSchd.rn).period_length := 2;
      end if;
      fSrv.schedule(cSchd.rn).schd_action := xml_Util.GetElementValue(cSchd.val, 'Schedule/Action', 1,
        aConstList=>tp_varchar2_100_table('A', 'D'));
    end loop;
    fClnt.services(fClnt.services.count + 1) := fSrv;
  end loop;

  ServiceSupport.SetClientInfo(aHdr.terminal, fClnt);
end SetUserServices;

---------
procedure UserServiceAdd(aHdr tp_msg_admin_header, aXML XMLType, aResponse out varchar2)
is
  fClntIdType op_oper.client_ident_type%type;
  fClntId     op_oper.client_ident     %type;
  fServiceNo int;
  fOpId int;
  fClientServiceId varchar2(30);
begin
  if aHdr.sid is not null then
    fClntIdType := Refs.CLIENT_ID_TYPE_CLIENT;
    fClntId     := ClientAuth_Core.GetClientId(aHdr.sid);
  else
    fClntIdType := xml_Util.GetValueS(aXML, 'ClientId', aAttrName=>'IdType', aMaxLen=>10);
    fClntId     := xml_Util.GetValueS(aXML, 'ClientId',                      aMaxLen=>20);
  end if;
  DecodeServiceId(STP_ID, xml_Util.GetValueS(aXML, 'ServiceId', aMaxLen=>30), fServiceNo, fOpId, aHdr.terminal, fClntIdType, fClntId);

  ServiceSupport.AddClServiceByExtraNo
  ( aHdr.terminal
  , case when aHdr.cl_client_id is not null then aHdr.cl_client_id else ClClient.GetIdentClientId(ClClient.FindIdentId(fClntIdType, fClntId)) end
  , fServiceNo, fOpId, fClientServiceId
  , xml_Util.GetValueS(aXML, 'PersonalAccount', aMaxLen=>30, aMandatory=>fOpId is null)
  );
  -- Возвращаем id избранной услуги для возможности корректировки её параметров
  aResponse := xml_Util.Element('Id', fClientServiceId);
end UserServiceAdd;

---------
procedure GetUserIdents(aHdr tp_msg_admin_header, aXML XMLType, aResponse out varchar2)
is
  fCientId    int := aHdr.cl_client_id;
  fIdents     tp_cl_idents;
  fHash       Util.TStrArr;
begin
  if fCientId is null then
    fCientId := ClClient.FindClientIdByIdent(xml_Util.GetValueS(aXML, 'ClientId', 'IdType', aMaxLen=>10), xml_Util.GetValueS(aXML, 'ClientId', aMaxLen=>20));
  end if;

  ServiceSupport.GetClientIdents(aHdr.terminal, fCientId, fIdents, fHash);

  Util.CheckErr(fIdents.count = 0, 'Клиент, с указанным средством идентификации, не зарегистрирован');

  for i in 1 .. fIdents.count loop
    aResponse := aResponse
              || xml_Util.Element('ClientId', fIdents(i).ident
                 ,    xml_Util.CreateAttr('IdType', fIdents(i).ident_type)
                   || xml_Util.CreateAttr('Id', fHash(i))
                   || xml_Util.CreateAttr('Name', substr(Refs.FormatClientIdent(fIdents(i).ident_type, fIdents(i).ident), 1, 99))
                   || xml_Util.CreateAttr('AutoPay', fIdents(i).payment_priority is not null, aDefVal=>false)
                 , aIndentCount=>2, aEncoding=>false
                 );
  end loop;
end GetUserIdents;

---------
procedure SetAutoPayPriority(aHdr tp_msg_admin_header, aXML XMLType, aResponse out varchar2)
is
  fCientId    int := aHdr.cl_client_id;
  fHash Util.TStrArr;
begin
  if fCientId is null then
    fCientId := ClClient.FindClientIdByIdent(xml_Util.GetValueS(aXML, 'ClientId', 'IdType', aMaxLen=>10), xml_Util.GetValueS(aXML, 'ClientId', aMaxLen=>20));
  end if;

  for cIds in (select rownum as rn, value(tbl) as val from table(xmlSequence(aXML.extract('Ids/Id'))) tbl) loop
    fHash(cIds.rn) := xml_Util.GetValueS(cIds.val, 'Id', aMaxLen=>30);
  end loop;

  ServiceSupport.SetClientIdentsPayPriority(aHdr.terminal, fCientId, fHash);
end SetAutoPayPriority;

---------
procedure ExcludeFromTree(aHdr tp_msg_admin_header, aXML XMLType, aResponse out varchar2)
is
  fClntIdType op_oper.client_ident_type%type;
  fClntId     op_oper.client_ident     %type;
  fServiceNo int;
  fExtraId int;
begin
  if aHdr.sid is not null then
    fClntIdType := Refs.CLIENT_ID_TYPE_CLIENT;
    fClntId     := ClientAuth_Core.GetClientId(aHdr.sid);
  else
    fClntIdType := xml_Util.GetElementAttrValue(aXML, 'ClientId', 'IdType', 10);
    fClntId     := xml_Util.GetElementValue    (aXML, 'ClientId', 20);
  end if;
  DecodeServiceId(STP_ID, xml_Util.GetElementValue(aXML, 'ServiceId', 30), fServiceNo, fExtraId, aHdr.terminal, fClntIdType, fClntId);

  OpPayment.ExcludeAccountFromLastPaid(aHdr.terminal, fClntIdType, fClntId, fServiceNo, fExtraId);
end ExcludeFromTree;

---------
procedure ServiceHistory(aHdr tp_msg_admin_header, aXML XMLType, aResponse out clob)
is
  fData OpPayment.TOperationsInfoStats;
  fAttempts    int := 0;
  fOperations  int := 0;
  fLastOper    date;
begin
  fData :=
    OpPayment.GetClientServiceStatistics
    ( aHdr.cl_client_id
    , xml_Util.GetValueD(aXML, '/PeriodBegin',    aMandatory=>false, aDefault=>add_months(sysdate, -12))
    , xml_Util.GetValueD(aXML, '/PeriodEnd',      aMandatory=>false, aDefault=>sysdate)
    , xml_Util.GetValueB(aXML, '/OnlySuccessful', aMandatory=>false, aDefault=>false)
    );

  for i in 1..fData.count loop
    fAttempts   := fAttempts + fData(i).attempts;
    fOperations := fOperations + fData(i).operations;
    fLastOper   := case when fLastOper is null then fData(i).last_operation else greatest(fLastOper, nvl(fData(i).last_operation, fLastOper)) end;

    aResponse :=
         aResponse
      || xml_Util.Element
         ( 'Service'
         , fData(i).service_abbr
         , xml_Util.CreateAttr('ServiceId',     nvl(-fData(i).service_id, fData(i).erip_service_id))
         ||xml_Util.CreateAttr('ServiceIdType', STP_SERVICE_ID)
         ||xml_Util.CreateAttr('Currency',      fData(i).currency)
         ||xml_Util.CreateAttr('Amount',        RCore.FmtAmount(fData(i).amount, fData(i).currency, Fmt=>Rcore.fSimple))
         ||xml_Util.CreateAttr('LastOperation', fData(i).last_operation, xml_Util.FMT_DATE)
         ||xml_Util.CreateAttr('Operations',    fData(i).operations)
         ||xml_Util.CreateAttr('Attempts',      fData(i).attempts)
         );
  end loop;
  if fAttempts > 0 then
    aResponse :=
      xml_Util.Element
      ( 'Totals'
      , ''
      , xml_Util.CreateAttr('Operations',     fOperations)
      ||xml_Util.CreateAttr('Attempts',       fAttempts)
      ||xml_Util.CreateAttr('LastOperation',  fLastOper, xml_Util.FMT_DATE)
      ) || aResponse;
  end if;
end ServiceHistory;

---------
procedure GetOperationsHistory(aHdr tp_msg_admin_header, aXML XMLType, aResponse out clob)
is
  fOpers      OpPayment.TOperationsInfo;

  fIdent          varchar2(20);
  fIdentType      varchar2(10);
  fPeriodBegin    date;
  fPeriodEnd      date;
  fServiceNo      int;
  fServiceNoExtra int;
  --
  fAIdx    int;
  fTrxData varchar2(32000);
  fTerminalInfo TTerminalInfo;
begin
  fIdentType   := xml_Util.GetValueS(aXML, 'AuthClientId', aAttrName=>'IdType',  aMaxLen=>10, aMandatory=>false);
  fIdent       := xml_Util.GetValueS(aXML, 'AuthClientId',                       aMaxLen=>20, aMandatory=>false);
  fPeriodBegin := xml_Util.GetValueD(aXML, '/Filter/Period/Begin',                            aMandatory=>false);
  fPeriodEnd   := xml_Util.GetValueD(aXML, '/Filter/Period/End',                              aMandatory=>false);
  Util.CheckErr(fPeriodBegin > fPeriodEnd, 'Период задан неверно');
  if aHdr.sid is not null then
    fTerminalInfo.cl_client_id := aHdr.cl_client_id;
    if fIdent is not null then
      fIdent := ClClient.GetIdent(ClClient.GetClientBankProductId(aHdr.cl_client_id, fIdentType, fIdent));
    end if;
  elsif fIdentType = Refs.CLIENT_ID_TYPE_CLIENT then
    fTerminalInfo.cl_client_id := xml_Util.GetValueN(fIdent, 'AuthClientId[@IdType="Client"]');
    fIdentType := null;
    fIdent     := null;
  elsif fIdent is null then
    if Refs.IsTerminalInGroup(aHdr.terminal, RefParam.GetParamValueAsNum(PRM_OPER_HISTORY_AS_SEARCH), aNullGroupAs=>false) then
      fPeriodEnd := nvl(fPeriodEnd, sysdate);
      Util.CheckErr(fPeriodBegin is null or fPeriodEnd - fPeriodBegin > 1, 'Поиск разрешён за период не более 24 часов');
    else
      Util.RaiseErr('Не задано платёжное средство');
    end if;
  end if;
  DecodeServiceId
  ( xml_Util.GetValueS(aXML, '/Filter/ServiceId',  aAttrName=>'ServiceIdType', aMaxLen=>20, aMandatory=>false)
  , xml_Util.GetValueS(aXML, '/Filter/ServiceId',  aMaxLen=>30, aMandatory=>false)
  , fServiceNo, fServiceNoExtra
  );

  fOpers :=
    OpPayment.GetOperationsHistory
    ( fTerminalInfo.cl_client_id
    , case when fServiceNo is not null then ServiceSupport.GetSignedServiceIdByServiceNo(fTerminalInfo, fServiceNo) end
    , fPeriodBegin
    , fPeriodEnd
    , xml_Util.GetValueS(aXML, '/Filter/PersonalAccount',           aMaxLen     =>        30, aMandatory=>false)
    , fIdent
    , fIdentType
    , xml_Util.GetValueN(aXML, '/LastTransactionId',                aMaxNumValue=>9999999999, aMandatory=>false)
    , xml_Util.GetValueN(aXML, '/PageSize',        aMinNumValue=>1, aMaxNumValue=>        99, aMandatory=>false, aDefault=>20)
    , xml_Util.GetValueN(aXML, '/Filter/Currency', aMinNumValue=>1, aMaxNumValue=>       999, aMandatory=>false)
    , xml_Util.GetValueB(aXML, '/Filter/OnlySuccessful',                                      aMandatory=>false, aDefault=>false)
    , xml_Util.GetValueS(aXML, '/Filter/TerminalId',                aMaxLen     =>        30, aMandatory=>false)
    );

  for i in 1 .. fOpers.count loop
    fTrxData := null;
    -- Добавление параметров авторизации
    if fOpers(i).auth_params.count > 0 then
      fAIdx := fOpers(i).auth_params.first;
      while fAIdx is not null loop
        fTrxData :=    fTrxData
                    || xml_Util.Element
                       ( 'Parameter'
                       , fOpers(i).auth_params(fAIdx).value
                       , xml_Util.CreateAttr('Name', fOpers(i).auth_params(fAIdx).name)
                       );
        fAIdx := fOpers(i).auth_params.next(fAIdx);
     end loop;
      fTrxData := xml_Util.Element('AuthorizationDetails', fTrxData, aEncoding=>false, aCloseOnNewLine=>true);
    end if;

    fTrxData :=
      xml_Util.Element
      ( 'Transaction'
      ,    xml_Util.Element('Id',                 fOpers(i).id)
        || xml_Util.Element('Time',               fOpers(i).inserted, 'YYYYMMDDhh24miss')
        || xml_Util.Element('ResultText',         fOpers(i).oper_result)
        || xml_Util.Element('TerminalId',         fOpers(i).terminal_id)
        || xml_Util.Element('TerminalName',       fOpers(i).terminal_name)
        || xml_Util.Element('TerminalTime',       fOpers(i).terminal_local_time, 'YYYYMMDDhh24miss')
        || xml_Util.Element('TerminalErrorText',  fOpers(i).error_text, aMandatory=>false)
        || xml_Util.Element('IsSuccessful',       fOpers(i).is_successful, aMandatory=>false)
        || xml_Util.Element('Settled',            fOpers(i).settled, 'YYYYMMDD', aMandatory=>false)
        || xml_Util.Element('ServiceId',          ServiceSupport.GetServiceNoBySignedServiceId(fOpers(i).signed_service_id)
           , xml_Util.CreateAttr('ServiceIdType', STP_ID, aDefVal=>STP_ID/*!!*/)
           )
        || xml_Util.Element('ServiceName',        fOpers(i).service_name)
        || xml_Util.Element('PersonalAccount',    fOpers(i).personal_account)
        || xml_Util.Element('Amount'
           , RCore.FmtAmount(nvl(fOpers(i).amount, 0), fOpers(i).currency, Fmt=>RCore.fSimple)
           , xml_Util.CreateAttr('Currency',      fOpers(i).currency, aEncoding=>false)
           ||xml_Util.CreateAttr('CurrencyAbbr',  Refs.GetCurrencyAbbr(fOpers(i).currency), aEncoding=>false)
           )
        || xml_Util.Element('AuthClientId',    fOpers(i).auth_ident
           , xml_Util.CreateAttr('Type', fOpers(i).auth_ident_type)
           ||xml_Util.CreateAttr('Name', Refs.GetClientIdName(fOpers(i).auth_ident_type))
           )
        || fTrxData
      , aEncoding=>false, aCloseOnNewLine=>true
      );
    aResponse := aResponse || fTrxData;
  end loop;

  aResponse := xml_Util.OpenElement('TransactionList', xml_Util.CreateAttr('Count', fOpers.count)) || aResponse || xml_Util.CloseElement('TransactionList');
end GetOperationsHistory;

---------
procedure GetAuthHistory(aHdr tp_msg_admin_header, aXML XMLType, aResponse out varchar2)
is
  Pn2$ constant varchar2(30) := 'GetAuthHistory';

  fIdent      varchar2(20);

  fAuthParameters tp_auth_parameters;
  fHistory tp_auth_history_answer;
  fIdx int;
  fCurrency int;
  fTermInfo TTerminalInfo;
begin
  fIdent                           := xml_Util.GetValueS(aXML, 'AuthId', aMaxLen=>20);
  fTermInfo.actual_auth_ident_type := xml_Util.GetValueS(aXML, 'AuthId', aAttrName=>'IdType', aMaxLen=>10);

  if aHdr.cl_client_id is not null then
    fTermInfo.actual_ident_id := ClClient.GetClientPayToolId(aHdr.cl_client_id, fTermInfo.actual_auth_ident_type, fIdent);
    gDocType := Docs.DOC_CLIENT_IDENT;
    gDocId   := fTermInfo.actual_ident_id;
    fIdent := ClClient.GetIdent(fTermInfo.actual_ident_id);
  end if;
  ReadAuthParam(aXML, null, false, fAuthParameters, aTermInfo=>fTermInfo);

  OpPayment.GetHistory
  ( tp_auth_balance_request(aHdr.terminal, fTermInfo.actual_auth_ident_type, fIdent, to_char(null), fAuthParameters)
  , fHistory
  );

  if fHistory is not null then
    if fHistory.auth_parameters is not null then
      fIdx := fHistory.auth_parameters.first;
      while fIdx is not null loop
        aResponse := aResponse || xml_Util.Element('Parameter', fHistory.auth_parameters(fIdx).value, xml_Util.CreateAttr('Name', fHistory.auth_parameters(fIdx).name));
        fIdx := fHistory.auth_parameters.next(fIdx);
      end loop;
      if aResponse is not null then
        aResponse := xml_Util.Element('AuthorizationDetails', aResponse, aEncoding=>false, aCloseOnNewLine=>true);
      end if;
    end if;
    if fHistory.operations is not null then
      fIdx := fHistory.operations.first;
      while fIdx is not null loop
        fCurrency := Refs.GetCurrencyCode(fHistory.operations(fIdx).currency, false);
        aResponse := aResponse ||
          xml_Util.Element
          ( 'Operation'
          , RCore.FmtAmount(fHistory.operations(fIdx).amount, fCurrency, Fmt=>Rcore.fSimple)
          , xml_Util.CreateAttr('Date',         to_char(fHistory.operations(fIdx).op_date, 'yyyymmddhh24miss'))
          ||xml_Util.CreateAttr('Type',         fHistory.operations(fIdx).op_type)
          ||xml_Util.CreateAttr('Merchant',     fHistory.operations(fIdx).merchant)
          ||xml_Util.CreateAttr('Currency',     fCurrency)
          ||xml_Util.CreateAttr('CurrencyAbbr', fHistory.operations(fIdx).currency, aEncoding=>false)
          , aEncoding=>false);
        fIdx := fHistory.operations.next(fIdx);
      end loop;
    end if;

  end if;
exception
  when others then
    LogWork.NotifyException(Pn1$, Pn2$);
    raise;
end GetAuthHistory;

--! - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

---------
procedure GetFiles(aHdr tp_msg_admin_header, aXML XMLType, aArrResponse out Util.TStrArr)
is
  fFileListOnly boolean;
  fConfirmRequired boolean;
  fFilesLimit int;
  fPeriodBegin date;
  fPeriodEnd date;
  fFileMask varchar2(255);
  fStatuses varchar2(3);
  fFileIds tp_int_table;
  --
  fResXml clob;
begin
  fFileListOnly := nvl(xml_util.GetElementAttrValue(aXML, 'GetFiles', 'FileListOnly', aType=>'B', aMandatory=>false), Util.YES) = Util.YES;
  fConfirmRequired := nvl(xml_util.GetElementAttrValue(aXML, 'GetFiles', 'ConfirmRequired', aType=>'B', aMandatory=>false), Util.YES) = Util.YES;
  fFilesLimit := xml_util.GetElementAttrValue(aXML, 'GetFiles', 'FilesLimit', aMaxLen=>3, aType=>'N', aMandatory=>false);
  fPeriodBegin := xml_Util.GetElementValueD(aXML, 'GetFiles/Filter/Period/Begin', aMaxLen=>14, aMandatory=>false);
  fPeriodEnd   := xml_Util.GetElementValueD(aXML, 'GetFiles/Filter/Period/End', aMaxLen=>14, aMandatory=>false);
  Util.CheckErr(fPeriodBegin <= fPeriodEnd, 'Дата окончания периода должна быть позже даты начала периода');

  if aXML.existsNode('/GetFiles/Filter/Files') > 0 then
    for cFls in (select rownum as rn, value(tbl) as val from table(xmlSequence(aXML.extract('GetFiles/Filter/Files/File'))) tbl) loop
      if fFileIds is null then
        fFileIds := tp_int_table();
      end if;
      fFileIds.extend;
      fFileIds(cFls.rn) := xml_util.GetElementAttrValue(cFls.val, 'File', 'Id', aMaxLen=>10, aType=>'N');
    end loop;
  end if;

  fFileMask := xml_util.GetElementValue(aXML, 'GetFiles/Filter/FileMask', aMaxLen=>255, aMandatory=>false);
  fStatuses := nvl(xml_util.GetElementValue(aXML, 'GetFiles/Filter/Status', aMaxLen=>3, aMandatory=>false), 'R');
  Util.CheckErr(translate(fStatuses, '.RPS', '.') is not null, 'Указан неверный статус файла "%s"', fStatuses);

  Util.CheckErr((fPeriodBegin is not null or fPeriodEnd is not null) and instr(fStatuses, 'S') = 0,
    'Период формирования файла можно задать только при указании значения "S" в статусе файла');

  fResXml := msg_xml.GetFiles(aHdr.terminal, fFileListOnly, fConfirmRequired,
    fFilesLimit, fPeriodBegin, fPeriodEnd, fFileMask, fStatuses, fFileIds
  );

  declare
    fCount integer := 0;
    fStr varchar2(2000);
  begin
    loop
      fStr := dbms_lob.substr(fResXml, 2000, 2000*fCount + 1);
      exit when fStr is null;
      fCount := fCount + 1;
      aArrResponse(fCount) := fStr;
    end loop;
  end;
end GetFiles;

---------
procedure ConfirmFiles(aHdr tp_msg_admin_header, aXML XMLType, aResponse out varchar2)
is
  fFileIds tp_int_table := tp_int_table();
begin
  for cFls in (select rownum as rn, value(tbl) as val from table(xmlSequence(aXML.extract('Files/File'))) tbl) loop
    fFileIds.extend;
    fFileIds(cFls.rn) := xml_util.GetValueN(cFls.val, 'File', 'Id', aMaxLen=>10);
  end loop;
  Util.CheckErr(fFileIds.count = 0, 'Необходимо задать Уч.N хотя бы для одного файла');

  msg_xml.ConfirmFiles(aHdr.terminal, fFileIds);
end ConfirmFiles;

--! - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

---------
procedure CheckAmountPrecision(aAmount number, aCurrency int, aElementName varchar2)
is
begin
  if Refs.GetCurrencyAbbr(aCurrency, aRaiseException=>false) is not null then
    Util.CheckErr(aAmount <> Refs.RoundAmount(aAmount, aCurrency), 'Неверная сумма в ' || aElementName);
  end if;
end CheckAmountPrecision;

---------
procedure ExchangeStart(aHdr tp_msg_admin_header, aXML XMLType, aResponse out varchar2)
is
  Pn2$ constant varchar2(30) := 'ExchangeStart';
  fData op_exchange_deal%rowtype;
  fNeedClntData boolean;
  --
  procedure Check1034Code(aCode int, aElementName varchar2)
  is
  begin
    Util.CheckErr(aCode is not null and Refs.Get1034CodeName(aCode) is null, 'Неверный код отчётного данного по форме 1034 в ' || aElementName);
  end Check1034Code;
begin
  gDocType := Docs.DOC_EXCHANGE_DEAL;
  Util.CheckErr(aHdr.terminal_time not between sysdate - interval '2' hour and sysdate + interval '2' hour, 'Неверные данные в TerminalTime');

  fData.buy_amount      := xml_Util.GetElementValue    (aXML, 'BuyAmount', 15, aType=>'N', aFormat=>'999999999990D99');
  fData.buy_currency    := xml_Util.GetElementAttrValue(aXML, 'BuyAmount', 'Currency', 3, aType=>'N');
    CheckAmountPrecision(fData.buy_amount, fData.buy_currency, 'BuyAmount');
  fData.buy_1034_code   := xml_Util.GetElementAttrValue(aXML, 'BuyAmount', 'Code1034', 4, aType=>'N', aMandatory=>fData.buy_currency<>Refs.Cur_Domestic());
    Check1034Code(fData.buy_1034_code, 'BuyAmount@Code1034');
  fData.sell_amount     := xml_Util.GetElementValue    (aXML, 'SellAmount', 15, aType=>'N', aFormat=>'999999999990D99');
  fData.sell_currency   := xml_Util.GetElementAttrValue(aXML, 'SellAmount', 'Currency', 3, aType=>'N');
    CheckAmountPrecision(fData.sell_amount, fData.sell_currency, 'SellAmount');
  fData.sell_1034_code  := xml_Util.GetElementAttrValue(aXML, 'SellAmount', 'Code1034', 4, aType=>'N', aMandatory=>fData.sell_currency<>Refs.Cur_Domestic());
    Check1034Code(fData.sell_1034_code, 'SellAmount@Code1034');

  fNeedClntData := fData.buy_currency = Refs.Cur_Domestic() and fData.sell_currency <> Refs.Cur_Domestic();

  fData.surname         := xml_Util.GetElementAttrValue(aXML, 'Person', 'Surname', 30, aMandatory=>fNeedClntData);
  fData.name            := xml_Util.GetElementAttrValue(aXML, 'Person', 'FirstName', 30, aMandatory=>fNeedClntData);
  fData.patronymic      := xml_Util.GetElementAttrValue(aXML, 'Person', 'Patronymic', 30, aMandatory=>false);
  fData.document_no     := xml_Util.GetElementValue    (aXML, 'Person/Document', 30, aMandatory=>fNeedClntData);
  fData.document_type   := xml_Util.GetElementAttrValue(aXML, 'Person/Document', 'Type', 2, aType=>'N', aMandatory=>fNeedClntData);
     if fData.document_type is not null then
       Util.CheckErr(fData.document_type not in ( Refs.DOCUMENT_DOMESTIC
                                                , Refs.DOCUMENT_PERMIT
                                                , Refs.DOCUMENT_REFUGEE
                                                , Refs.DOCUMENT_FOREIGN
                                                )
       , 'Неверные данные в Person/Document@Type');
       Util.CheckErr(fData.document_type = Refs.DOCUMENT_DOMESTIC and not Refs.IsPassportNoValid(fData.document_no)
       , 'Неверные данные в Person/Document');
     end if;
  fData.personal_no     := xml_Util.GetElementValue    (aXML, 'Person/PersonalNo', 14
                           , aMandatory=>fData.document_type in (Refs.DOCUMENT_DOMESTIC, Refs.DOCUMENT_PERMIT) and fNeedClntData);
    Util.CheckErr(fData.personal_no is not null and not Refs.IsPersonalNoValid(fData.personal_no), 'Неверный идентификационный номер');
  fData.birthday        := xml_Util.GetElementValueD(aXML, 'Person/Birthday'
                           , aMandatory=>fData.document_type in (Refs.DOCUMENT_REFUGEE, Refs.DOCUMENT_FOREIGN) and fNeedClntData
                           , aFormat=>'fxdd.mm.yyyy');
    Util.CheckErr(fData.birthday is not null and fData.birthday >= sysdate, 'Неверные данные в Person/Birthday');
  fData.sell_purpose    := xml_Util.GetElementValue    (aXML, 'Purpose', 2, aType=>'N', aMandatory=>false);
    Util.CheckErr(fData.sell_purpose is not null and Refs.GetSellCurrencyPurpose(fData.sell_purpose) is null
    , 'Неверные данные в Purpose');
  fData.comments        := xml_Util.GetElementValue    (aXML, 'Comments', 255, aMandatory=>false);

  fData.terminal            := aHdr.terminal;
  fData.terminal_local_time := aHdr.terminal_time;

  ERIP_Online.DealStart(fData);
  gDocId   := fData.id;
  aResponse := xml_Util.Element('DealId', fData.id, aIndentCount=>2);
exception
  when others then
    LogWork.NotifyException(Pn1$, Pn2$);
    raise;
end ExchangeStart;

---------
procedure ExchangeResult(aHdr tp_msg_admin_header, aXML XMLType, aResponse out varchar2)
is
  Pn2$ constant varchar2(30) := 'ExchangeResult';
  fData op_exchange_deal%rowtype;
begin
  gDocType := Docs.DOC_EXCHANGE_DEAL;
  fData.id                  := xml_Util.GetElementValue(aXML, 'DealId', 8, aType=>'N');
  gDocId   := fData.id;
  fData.error_text          := xml_Util.GetElementValue(aXML, 'ErrorText', 20, aMandatory=>fData.id=0);
  fData.terminal_deal_id    := xml_Util.GetElementValue(aXML, 'TerminalDealId', 20, aMandatory=>fData.error_text is null);
  fData.terminal            := aHdr.terminal;

  ERIP_Online.DealResult(fData);
exception
  when others then
    LogWork.NotifyException(Pn1$, Pn2$);
    raise;
end ExchangeResult;

---------
procedure ExchangeStorn(aHdr tp_msg_admin_header, aXML XMLType, aResponse out varchar2)
is
  Pn2$ constant varchar2(30) := 'ExchangeStorn';
  fData op_exchange_deal%rowtype;
begin
  gDocType := Docs.DOC_EXCHANGE_DEAL;
  fData.id                  := xml_Util.GetElementValue(aXML, 'DealId', 8, aType=>'N');
  gDocId   := fData.id;
  fData.terminal_deal_id    := xml_Util.GetElementValue(aXML, 'TerminalDealId', 20, aMandatory=>fData.error_text is null);
  fData.terminal            := aHdr.terminal;

  ERIP_Online.DealStorn(fData);
exception
  when others then
    LogWork.NotifyException(Pn1$, Pn2$);
    raise;
end ExchangeStorn;


---------
procedure SearchPerson(aHdr tp_msg_admin_header, aXML XMLType, aResponse out varchar2)
is
  Pn2$ constant varchar2(30) := 'SearchPerson';
  fPerson  ERIP_Online.TPerson;
  fPersons ERIP_Online.TPersons;
begin
  fPerson.document_no     := xml_Util.GetValueS(aXML, 'Document', aMaxLen=>30, aMandatory=>false);
  fPerson.document_type   := xml_Util.GetValueN(aXML, 'Document', 'Type', 2, aMandatory=>false
                             , aConstList=>tp_num_table(Refs.DOCUMENT_DOMESTIC, Refs.DOCUMENT_PERMIT, Refs.DOCUMENT_REFUGEE, Refs.DOCUMENT_FOREIGN));
  fPerson.personal_no     := xml_Util.GetValueS(aXML, 'PersonalNo', aMaxLen=>14, aMandatory=>(fPerson.document_no is null));
  fPerson.birthday        := xml_Util.GetValueD(aXML, 'Birthday', aMandatory=>false, aFormat=>'fxdd.mm.yyyy');
  fPersons(1) := fPerson;
  --
  ERIP_Online.SearchPerson(fPersons);
  --
  aResponse := xml_Util.OpenElement('Persons', aIndentCount=>2);
  for i in 1..fPersons.Count loop
    aResponse := aResponse || xml_Util.OpenElement
    (  'Person'
    ,  xml_Util.CreateAttr('Surname',    fPersons(i).surname)
    || xml_Util.CreateAttr('FirstName',  fPersons(i).name)
    || xml_Util.CreateAttr('Patronymic', fPersons(i).patronymic)
    , 3
    );
    xml_Util.AddElementToBuff
    ( aResponse, 'Document', fPersons(i).document_no,
      xml_Util.CreateAttr('Type',    fPersons(i).document_type), aIndentCount=>4
    );
    xml_Util.AddElementToBuff
    ( aResponse, 'PersonalNo', fPersons(i).personal_no, aIndentCount=>4
    );
    xml_Util.AddElementToBuff
    ( aResponse, 'Birthday', to_char(fPersons(i).birthday, 'dd.mm.yyyy'), aIndentCount=>4
    );
    aResponse := aResponse || xml_Util.CloseElement('Person', 3);
  end loop;
  aResponse := aResponse || xml_Util.CloseElement('Persons', aIndentCount=>2);
  --
exception
  when others then
    LogWork.NotifyException(Pn1$, Pn2$);
    raise;
end SearchPerson;

---------
procedure SearchDeal(aHdr tp_msg_admin_header, aXML XMLType, aArrResponse out Util.TStrArr)
is
  Pn2$ constant varchar2(30) := 'SearchDeal';
  fDeal op_exchange_deal%rowtype;
  fDeals ERIP_Online.TDeals;
  i int;
  fExactNameMatch boolean;
  fPeriodBegin date;
  fPeriodEnd date;
  fCurrency int;
  fOperType varchar2(1);
  fMinAmount op_exchange_deal.buy_amount%type;
  fMaxAmount op_exchange_deal.buy_amount%type;
  fTerminalNames Util.TStrArrByS30;
  fTerminalBranches Util.TIntArrByS30;
  --
  procedure GetFioPart(aFioPart out varchar2, aFioPartName varchar2, aMinPartLenForNonexactMatch int := 1)
  is
  begin
    aFioPart := xml_Util.GetValueS(aXML, 'Person', aFioPartName, aMaxLen=>30, aMandatory=>false);
    Util.CheckErr(regexp_like(aFioPart, '[_%]'), 'Недопустимые символы в %s при @ExactNameMatch=N', aFioPartName);
    if not fExactNameMatch and aFioPart is not null then
      Util.CheckErr(length(aFioPart) < aMinPartLenForNonexactMatch, 'Недостаточная длина %s при @ExactNameMatch=N', aFioPartName);
      aFioPart := aFioPart || '%';
    end if;
  end GetFioPart;
  --
begin
  fPeriodBegin          := xml_Util.GetValueD(aXML, 'Period/Begin', aMaxLen=>14, aMandatory=>false);
  fPeriodEnd            := xml_Util.GetValueD(aXML, 'Period/End', aMaxLen=>14, aMandatory=>false);
  fExactNameMatch       := xml_Util.GetValueB(aXML, 'Person', 'ExactNameMatch', aMandatory=>false, aDefault=>true);
  GetFioPart(fDeal.surname                        , 'Surname', aMinPartLenForNonexactMatch=>3);
  GetFioPart(fDeal.name                           , 'FirstName');
  GetFioPart(fDeal.patronymic                     , 'Patronymic');
  fDeal.document_no     := xml_Util.GetValues(aXML, 'Person/Document', aMaxLen=>30, aMandatory=>false);
  fDeal.document_type   := xml_Util.GetValueN(aXML, 'Person/Document', 'Type', aMaxLen=>2, aMandatory=>false
                                             , aConstList=>tp_num_table(Refs.DOCUMENT_DOMESTIC, Refs.DOCUMENT_PERMIT, Refs.DOCUMENT_REFUGEE, Refs.DOCUMENT_FOREIGN) );
  fDeal.personal_no     := xml_Util.GetValueS(aXML, 'Person/PersonalNo', aMaxLen=>14, aMandatory=>false);
  Util.CheckErr
  (     fDeal.surname     is null
    and fDeal.document_no is null
    and fDeal.personal_no is null
    and (fPeriodBegin is null or fPeriodEnd is null)
  , 'Должен быть заполнен либо один из элементов Person/Surname, Person/Document, Person/PersonalNo, либо Period/Begin с Period/End'
  );
  fDeal.birthday        := xml_Util.GetValueD(aXML, 'Person/Birthday', aMandatory=>false, aFormat=>'fxdd.mm.yyyy');
  fOperType             := xml_Util.GetValueS(aXML, 'OperType', aMaxLen=>1, aMandatory=>false, aConstList=>tp_varchar2_100_table('S', 'B', 'C'));
  fMinAmount            := xml_Util.GetValueN(aXML, 'MinAmount', aFormat=>'999999999990D99', aMandatory=>false);
  fMaxAmount            := xml_Util.GetValueN(aXML, 'MaxAmount', aFormat=>'999999999990D99', aMandatory=>false);
  fCurrency             := xml_Util.GetValueN(aXML, 'Currency', aMinNumValue=>1, aMaxNumValue=>999, aMandatory=> (fMinAmount is not null or fMaxAmount is not null));
  --
  fDeals(fDeals.count + 1) := fDeal;
  --
  LogWork.Notify(Pn1$, Pn2$, '- searching ...');
  ERIP_Online.SearchDeal(fDeals, fOperType, fMinAmount, fMaxAmount, fCurrency, fPeriodBegin, fPeriodEnd);
  LogWork.NotifyFmt(Pn1$, Pn2$, '- Found %d. Formatting ...', fDeals.count);
  --
  aArrResponse(aArrResponse.count) := xml_Util.OpenElement('Deals', xml_Util.CreateAttr('Count', fDeals.count), aIndentCount=>2);
  for i in 1 .. fDeals.count loop
    fDeal := fDeals(i);
    if not fTerminalNames.exists(fDeal.terminal) then
      fTerminalNames(fDeal.terminal) := xml_util.EncodeXML(Lookup.GetLookupValueName('Lookup.AbonentList', fDeal.terminal));
    end if;
    if not fTerminalBranches.exists(fDeal.terminal) then
      fTerminalBranches(fDeal.terminal) := Refs.GetAbonentBranchCode(fDeal.terminal);
    end if;
    aArrResponse(aArrResponse.count) :=
                 xml_Util.OpenElement('Deal', xml_Util.CreateAttr('Time', fDeal.inserted, 'YYYYMMDDhh24miss'), aIndentCount=>3)
    || chr(10) || xml_Util.Element('DealId', fDeal.id, aIndentCount=>4, aEncoding=>false)
    || chr(10) || xml_Util.Element('TerminalId', fDeal.terminal,
                      xml_Util.CreateAttr('TerminalName', fTerminalNames(fDeal.terminal), aEncoding=>false)
                   || xml_Util.CreateAttr('BranchCode', fTerminalBranches(fDeal.terminal), aEncoding=>false), aIndentCount=>4, aEncoding=>false
                  )
    || chr(10) || xml_Util.Element('TerminalTime', fDeal.terminal_local_time, 'YYYYMMDDhh24miss', aIndentCount=>4)
    || chr(10) || xml_Util.Element('TerminalDealId', fDeal.terminal_deal_id, aIndentCount=>4, aEncoding=>false)
    || chr(10) || xml_Util.Element('BuyAmount', fDeal.buy_amount,
                      xml_Util.CreateAttr('Currency', fDeal.buy_currency, aEncoding=>false)
                   || xml_Util.CreateAttr('Code1034', fDeal.buy_1034_code, aEncoding=>false), aIndentCount=>4, aEncoding=>false
                  )
    || chr(10) || xml_Util.Element('SellAmount', fDeal.sell_amount,
                      xml_Util.CreateAttr('Currency', fDeal.sell_currency, aEncoding=>false)
                   || xml_Util.CreateAttr('Code1034', fDeal.sell_1034_code, aEncoding=>false), aIndentCount=>5, aEncoding=>false
                  )
    || chr(10) || xml_Util.OpenElement
                  ( 'Person'
                  ,     xml_Util.CreateAttr('Surname',    fDeal.surname)
                     || xml_Util.CreateAttr('FirstName',  fDeal.name)
                     || xml_Util.CreateAttr('Patronymic', fDeal.patronymic)
                  , aIndentCount=>5
                  )
    || chr(10) ||   xml_Util.Element('Document', fDeal.document_no,
                      xml_Util.CreateAttr('Type',    fDeal.document_type, aEncoding=>false), aIndentCount=>6
                    )
    || chr(10) ||   xml_Util.Element('PersonalNo', fDeal.personal_no, aIndentCount=>6, aEncoding=>false)
    || chr(10) ||   xml_Util.Element('Birthday', fDeal.birthday, 'dd.mm.yyyy', aIndentCount=>6)
    || chr(10) || xml_Util.CloseElement('Person', aIndentCount=>5)
    || chr(10) || xml_Util.Element('Purpose', fDeal.sell_purpose, aIndentCount=>5, aEncoding=>false)
    || chr(10) || xml_Util.Element('Comments', fDeal.comments, aIndentCount=>5)
    || chr(10) ||xml_Util.CloseElement('Deal', 2);
  end loop;
  aArrResponse(aArrResponse.count) := xml_Util.CloseElement('Deals', aIndentCount=>3);
  LogWork.Notify(Pn1$, Pn2$, '- formatted ...');
  --
exception
  when others then
    LogWork.NotifyException(Pn1$, Pn2$);
    raise;
end SearchDeal;

---------
procedure News(aHdr tp_msg_admin_header, aXML XMLType, aResponse out clob)
is
  Pn2$          constant varchar2(30) := 'News';
  fNews         ClientMsg.TMessages;
  fOnlySubject  boolean;
  fPageSize     int;
begin
  fOnlySubject  :=  xml_Util.GetValueB(aXML, 'OnlySubject', aDefault=>false);
  fPageSize     :=  xml_Util.GetValueN(aXML, 'PageSize', aMaxLen => 2, aMinNumValue=>1, aDefault=>10);

  fNews := ClientMsg.GetMessages
           ( aMsgId     => xml_Util.GetValueN(aXML, 'Id',     aMaxLen=>12, aMandatory=> false)
           , aFromId    => xml_Util.GetValueN(aXML, 'FromId', aMaxLen=>12, aMandatory=> false)
           , aPeriod    => xml_Util.GetValueN(aXML, 'Period', aMaxLen=>3,  aMinNumValue=>1, aMandatory=>false, aDefault=>360)
           , aMaxCount  => fPageSize + 1
           );
  for i in 1..fNews.count loop
    if i > fPageSize then
      aResponse := aResponse || xml_Util.Element('NextId', fNews(i).id);
      exit;
    end if;
    aResponse :=
        aResponse
        ||xml_Util.OpenElement('Message')
        ||xml_Util.Element('Id', fNews(i).id)
        ||xml_Util.Element('Created', fNews(i).created, xml_Util.FMT_DATE)
        ||xml_Util.Element('Subject', nvl(fNews(i).subject, 'Информация'))
        ||case when not fOnlySubject then xml_Util.Element('Body', fNews(i).body, aMandatory => false) end
        ||xml_Util.CloseElement('Message')
        ;
  end loop;
exception
  when others then
    LogWork.NotifyException(Pn1$, Pn2$);
    raise;
end News;

---------
procedure Rates(aHdr tp_msg_admin_header, aXML XMLType, aResponse out clob)
is
  fData        Refs.TRateByCurrencies;
  fBegin       date;
  fEnd         date;
  fPrevBuy     Util.TNumArr;
  fPrevSale    Util.TNumArr;
  fBuff        varchar2(30000);
  fCurrentDay  Util.TStrArr;
  fIdx         int;
  --
  procedure ElementCurrency(aData date, aCurrency int, aBuy number, aSale number)
  is
  begin
    if aData between fBegin and fEnd then
      fBuff :=    fBuff
               || xml_Util.Element('Currency' ,  ''
                  , xml_Util.CreateAttr('Code',  aCurrency)
                  ||xml_Util.CreateAttr('Abbr',  Refs.GetCurrencyAbbr(aCurrency, aRaiseException=>false))
                  ||xml_Util.CreateAttr('Name',  Refs.GetCurrencyName(aCurrency, aRaiseException=>false))
                  ||xml_Util.CreateAttr('Buy' ,  ServiceSupport.Float2Str(aBuy,  1, 12, 5))
                  ||xml_Util.CreateAttr('Sale',  ServiceSupport.Float2Str(aSale, 1, 12, 5))
                  ||xml_Util.CreateAttr('BuyDifference',  case when fPrevBuy.exists(aCurrency) then
                                                            ServiceSupport.Float2Str(nullif(aBuy - fPrevBuy(aCurrency), 0),  1, 12, 5)
                                                          end)
                  ||xml_Util.CreateAttr('SaleDifference', case when fPrevBuy.exists(aCurrency) then
                                                            ServiceSupport.Float2Str(nullif(aSale - fPrevSale(aCurrency), 0), 1, 12, 5)
                                                          end)
                  );
    end if;
    fPrevBuy (aCurrency) := aBuy;
    fPrevSale(aCurrency) := aSale;
  end ElementCurrency;
begin
  fBegin  := xml_Util.GetValueD(aXML, '/PeriodBegin', aFormat=>'yyyymmdd');
  fEnd    := xml_Util.GetValueD(aXML, '/PeriodEnd',   aFormat=>'yyyymmdd');
  fData   := Refs.GetRatesConversion(fBegin - 1, fEnd);
  for i in reverse 1..fData.count loop
    fBuff := '';
    for j in 1 .. fData(i).currency.count loop
      fCurrentDay(fData(i).currency(j)) := null;
      ElementCurrency(fData(i).rate_date, fData(i).currency(j), fData(i).buy(j), fData(i).sale(j));
    end loop;

    fIdx := fPrevBuy.first;
    while fIdx is not null loop
      if not fCurrentDay.exists(fIdx) then
        ElementCurrency(fData(i).rate_date, fIdx, fPrevBuy(fIdx), fPrevSale(fIdx));
      end if;
      fIdx := fPrevBuy.next(fIdx);
    end loop;
    fCurrentDay.delete;

    if fBuff is not null then
      aResponse := xml_Util.Element('Rate', fBuff, xml_Util.CreateAttr('Date', fData(i).rate_date, 'yyyymmdd')
                   , aEncoding=>false, aCloseOnNewLine=>true) || aResponse;
    end if;
  end loop;
end Rates;

---------
procedure GetActualRates(aHdr tp_msg_admin_header, aXML XMLType, aResponse out clob)
  is
  Pn2$                 constant varchar2(30) := 'GetActualRates';
  fRateDate            date := sysdate;
  fCurrenciesPairs     Util.TInts2D;
  fRateTypeId          int := Refs.RATE_CONVERSION_DEFAULT_TYPE;
  fSell                number;
  fBuy                 number;
  fRateDateTime        date;
begin
  fRateTypeId := case
                   when xml_Util.GetValueS(aXML, '/Type', aMandatory=> false) is null
                     then Refs.RATE_CONVERSION_DEFAULT_TYPE
                   else Lookup.GetLookupValueCode(Refs.RateConversionTypes, xml_Util.GetValueS(aXML, '/Type', aMandatory=> false))
                 end;
  fCurrenciesPairs := Refs.RatesConv$ActualCurrency$Get(fRateDate, fRateTypeId);
  aResponse := xml_Util.OpenElement('Rates');
  for i in 1 .. fCurrenciesPairs.count loop
    Refs.RatesConv$BuySellRates$Get
      (fRateDate
     , fCurrenciesPairs(i)(1)
     , fCurrenciesPairs(i)(2)
     , fBuy
     , fSell
     , fRateTypeId
     , fRateDateTime);
    if fBuy is not null and fSell is not null then
          xml_Util.AddElementToBuff
          ( aResponse
          , 'Rate'
          , null
          ,    xml_Util.CreateAttr('To',   fCurrenciesPairs(i)(1))
            || xml_Util.CreateAttr('From', fCurrenciesPairs(i)(2))
            || xml_Util.CreateAttr('Date', Util.DMYHMS(fRateDateTime))
            || xml_Util.CreateAttr('Buy',  RCore.Fmtn(Util.RoundSignificantDigits(fBuy, 9)))
            || xml_Util.CreateAttr('Sell', RCore.Fmtn(Util.RoundSignificantDigits(fSell, 9)))
          );
        end if;
  end loop;
  aResponse := aResponse || xml_Util.CloseElement('Rates');

  LogWork.NotifyFmt(Pn1$, Pn2$, '- CurrenciesPairs=%d, RateTypeId=%d:(%s)', fCurrenciesPairs.count, fRateTypeId
  , xml_Util.GetValueS(aXML, '/Type', aMandatory=> false));

end GetActualRates;

---------
procedure Admin -- main
( XML                   clob
, aResponse out nocopy  clob
, aIsHttp               boolean
, aJson                 boolean := false
, aEncrypted            boolean := false
)
is
  Pn2$ constant varchar2(30) := 'Admin';

  fReqRecieved  timestamp := systimestamp;
  fXML          XMLType;
  fXMLToLog     XMLType;
  fJson         pljson;
  fJsonToLog    pljson;
  fResponseJson pljson_value;
  fArrResponse  Util.TStrArr;

  fReqType      varchar2(30);
  fSubsystem    varchar2(10);
  fExtension    varchar2(20);
  fReqName      varchar2(50) := '?';
  fMsgHeader    tp_msg_admin_header;
  fBool         boolean;

  fNotLogging           boolean := false;
  fSignSalt             obj_abonent.signature_salt%type;
  fNeedAddAnswerTypeTag boolean := false;
  fErrorClass           int;
  fReqId                int;
  fPkgName              varchar2(30);
  f3DESKey              raw(24);
  ---------
  procedure PrepareResponse(aErrText varchar2 := null)
  is
    fInfo TExtraInfo;
    fFullResponseJson pljson := pljson();
  begin
    if aJson then
      fFullResponseJson.put('ServerTime', to_char(sysdate, xml_Util.FMT_STD_DATE_TIME));
      if fMsgHeader.terminal_version is not null then
        fFullResponseJson.put
        ( 'ErrorCode'
        , - case when aErrText is null
              then 0
              else case when fErrorClass between ERROR_CLASS$J$ERR_DEFAULT and ERROR_CLASS$J$ERR_LAST
                     then fErrorClass
                     else ERROR_CLASS$J$ERR_DEFAULT
                   end
            end
        );
        fFullResponseJson.put('ErrorMessage', Util.CutOff(aErrText, 2000));
      else
        fFullResponseJson.put('Error', Util.CutOff(aErrText, 2000));
      end if;
    end if;

    if aResponse is null and fArrResponse.count > 0 then
      if fArrResponse is not null and fArrResponse.count > 0 then
        LogWork.NotifyFmt(Pn1$, Pn2$, '- converting %d items into clob ...', fArrResponse.count);
        if fNeedAddAnswerTypeTag then
          fArrResponse(fArrResponse.first - 1) := xml_Util.OpenElement(fReqType);
          fArrResponse(fArrResponse.last  + 1) := xml_Util.CloseElement(fReqType);
        end if;
        Util.TStrArr2Clob(fArrResponse, aResponse, aAddCR=>false);
        LogWork.Notify(Pn1$, Pn2$, '- converted.');
      end if;
    else
      if aJson then
        if fReqType is not null then
          fFullResponseJson.put(fReqType, nvl(fResponseJson, pljson_value(pljson())));
        end if;
      else
        aResponse := case when fNeedAddAnswerTypeTag then xml_Util.OpenElement(fReqType) end
                  || aResponse
                  || case when fNeedAddAnswerTypeTag then xml_Util.CloseElement(fReqType) end;
      end if;
    end if;

    if aErrText is not null and not aJson then
      ServiceSupport.StrToInfo($IF OwnerInfo.LANGUAGE_SUPPORT $THEN Ref_Translate.Get(aErrText, fMsgHeader.language) $ELSE aErrText $END, 99, fInfo);
      aResponse := xml_Util.CloseElement('Error') || aResponse;
      for i in reverse 1..fInfo.count loop
        aResponse := xml_Util.Element('ErrorLine', rtrim(fInfo(i).StrInfo), xml_Util.CreateAttr('Idx', i, aEncoding=>false)) || aResponse;
      end loop;
      aResponse :=
        xml_Util.OpenElement
        ( 'Error'
        , xml_Util.CreateAttr('Count', fInfo.count, aEncoding=>false)
        ||xml_Util.CreateAttr('Class', fErrorClass)
        )
        || aResponse;
    end if;

    if aJson then
      dbms_lob.createtemporary(aResponse, false);
      fFullResponseJson.to_clob(aResponse, spaces=>true);
    else
      aResponse :=
           xml_Util.OpenElement(ROOTELEMENT_RESPONSE, aLeftBR=>false)
        || xml_Util.Element('ServerTime', to_char(sysdate, 'yyyymmddhh24miss'), aIndentCount=>1, aEncoding=>false)
        || PrintSession(fMsgHeader.sid, fMsgHeader.terminal)
        || aResponse
        || xml_Util.CloseElement(ROOTELEMENT_RESPONSE);
      begin
        aResponse := xml_Util.XML_HEADER
                  || case when RefParam.IsDevDB
                       then xml_Util.SerializeXML(xmltype(aResponse))
                       else aResponse
                     end;
      exception
        when xml_Util.eFailedXML then
          aResponse := xml_Util.XML_HEADER || aResponse;
      end;
    end if;

    if aIsHttp then
      owa_util.mime_header(ccontent_type=>case when aJson then 'application/json' else 'text/xml' end, bclose_header=>false);
      if fSignSalt is not null then
        declare
          fSign varchar2(2000);
        begin
          fSign := CGI_PARAM_SIGNATURE || ':'|| GetMsgSignature(fSignSalt, aResponse);
          LogWork.Notify(Pn1$, Pn2$, fSign);
          htp.p(fSign);
        end;
      end if;
      if RefParam.GetParamValueAsStr(PRM$ACCESS_CTR_ALLOW_ORIGIN) is not null then
        htp.print('Access-Control-Allow-Origin: ' || RefParam.GetParamValueAsStr(PRM$ACCESS_CTR_ALLOW_ORIGIN));
      end if;
      owa_util.http_header_close;

      declare
        fData clob := aResponse;
        fBlob blob;
      begin
        if aEncrypted and f3DESKey is not null then
          dbms_lob.createtemporary(fBlob, true);
          dbms_crypto.encrypt
          ( fBlob
          , UtilLob.Clob2Blob(fData, aCharSet=>'AL32UTF8')
          , dbms_crypto.ENCRYPT_3DES + dbms_crypto.CHAIN_CBC + dbms_crypto.PAD_PKCS5
          , f3DESKey
          , iv=>utl_raw.cast_to_raw('00000000')
          );
          fData := UtilLob.Base64Encode(fBlob);
        end if;

        for i in 0 .. floor(length(fData) / PACK_LENGTH) loop
          htp.prn(substr(fData, 1 + i*PACK_LENGTH, PACK_LENGTH));
        end loop;
      end;
    end if;

    if gContextDocType = Docs.DOC_CLIENT_SESSION and gDocType = Docs.DOC_CLIENT then
      gDocType := gContextDocType;
      gDocId   := gContextDocId;
    end if;

    if fReqId is null then
      fReqId := Op_Online.RegRequest
                ( null, null, fReqName, xml
                , aAddress=>GetIpAddress
                , aTerminal=>case when fMsgHeader is not null then fMsgHeader.terminal end
                , aDirection=>Refs.FILE_DIR_IN
                , aStartProcessingTime=>fReqRecieved
                , aMaskingRules=>cReqMaskingRules
                );
    end if;

    Op_Online.RegAnswer
    ( fReqId, aResponse
    , aSaveLength=>case when fNotLogging then 2000 end
    , aIsError=>aErrText is not null
    , aDocType=>gDocType, aDocId=>gDocId, aDataLength=>length(aResponse)
    , aRequestMaskingRules=>Util.TStrs2TStrs2D(Util.TpVarchar4000Table2TStrs(fMsgHeader.request_masking_rules))
    , aContextDocType=>gContextDocType, aContextDocId=>gContextDocId
    );
  exception
    when others then
      LogWork.NotifyException(Pn1$, Pn2$, 'PrepareResponse');
      rollback;
      if aIsHttp then
        owa_util.status_line(utl_http.HTTP_NOT_IMPLEMENTED);
      end if;
  end PrepareResponse;
  --
  procedure TestAuth
  is
  begin
    Util.CheckErr(fMsgHeader.cl_client_id is null, 'Функция требует аутентификации клиента');
  end TestAuth;
begin
  ClientAuth_Core.ClearRefresh;
  fMsgHeader := tp_msg_admin_header();
  gDocType := null;
  gDocId   := null;
  gContextDocType := null;
  gContextDocId   := null;
  fMsgHeader.terminal_ip := GetSingleIpAddress;

  Util.CheckErr(XML is null, 'Отсутствует тело запроса');
  declare
    fData clob := XML;
    fBlob blob;
  begin
    if aEncrypted then
      UtilLob.ReadBlobInit(UtilLob.Base64Decode(fData), 'AL32UTF8');
      Util.CheckErr(UtilLob.ReadBlobLength < 18, 'Неверная длина пакета');
      f3DESKey := Terminal$GetKey_3DS(UtilLob.ReadBlobS(1, 16));
      dbms_lob.createtemporary(fBlob, true);
      dbms_crypto.decrypt
      ( fBlob
      , UtilLob.ReadBlobBlob(17, UtilLob.ReadBlobLength)
      , dbms_crypto.ENCRYPT_3DES + dbms_crypto.CHAIN_CBC + dbms_crypto.PAD_PKCS5
      , f3DESKey
      , iv=>utl_raw.cast_to_raw('00000000')
      );
      UtilLob.Blob2Clob(fBlob, fData, 'AL32UTF8');
    end if;

    if aJson then
      fJson := pljson(fData);
      fJsonToLog := fJson;
    else
      fXML := XMLType(fData);
      fXMLToLog := fXML;
    end if;
  end;

  declare
    fRoot varchar2(2000);
    fTermType int;
  begin
    if not aJson then
      fRoot := substr(fXML.getRootElement(), 1, 100);
      Util.CheckErr(fRoot <> ROOTELEMENT_REQUEST, 'Некорректный корневой элемент "%s!=%s"', fRoot, ROOTELEMENT_REQUEST);
      fXML := fXML.extract('/' || ROOTELEMENT_REQUEST || '/*');
    end if;

    $IF OwnerInfo.LANGUAGE_SUPPORT $THEN
      fMsgHeader.language := xml_Util.GetValueS(fXML, 'Language', aMaxLen=>2, aMandatory=>false, aDefault=>Ref_Translate.LANG$CODE$DEFAULT);
      if fMsgHeader.language not member of Ref_Translate.gValidLangs then
        fMsgHeader.language := Ref_Translate.LANG$CODE$DEFAULT;
      end if;
    $END

    if aJson then
      fMsgHeader.terminal         := xml_Util.GetValueS(pljson_ext.get_string(fJson, 'TerminalId'), 'TerminalId', aMaxLen=>30, aMandatory=>aIsHttp);
      fMsgHeader.terminal_version := xml_Util.GetValueS(pljson_ext.get_string(fJson, 'TerminalVersion'), 'TerminalVersion', aMaxLen=>30, aMandatory=>false);
      fSubsystem  := xml_Util.GetValueS(pljson_ext.get_string(fJson, 'Subsystem'), 'Subsystem',   aMaxLen=>10, aMandatory=>false);
      fReqType    := xml_Util.GetValueS(pljson_ext.get_string(fJson, 'RequestType'), 'RequestType', aMaxLen=>30);
    else
      fMsgHeader.terminal         := xml_Util.GetValueS(fXML, 'TerminalId', aMaxLen=>30, aMandatory=>aIsHttp);
      fMsgHeader.terminal_version := xml_Util.GetValueS(fXML, 'TerminalId', 'Version', aMaxLen=>30, aMandatory=>false);
      fSubsystem  := xml_Util.GetValueS(fXML, 'Subsystem',   aMaxLen=>10, aMandatory=>false);
      fReqType    := xml_Util.GetValueS(fXML, 'RequestType', aMaxLen=>30);
    end if;
    if fSubsystem is not null then
      fExtension := xml_Util.GetValueS(fXML, 'Subsystem', 'Extension',  aMaxLen=>15, aMandatory=>false);
    end if;
    fReqName :=
      case when fSubsystem is not null
        then fSubSystem || ':' || case when fExtension is not null then fExtension || ':' end
      end ||
      fReqType;

    Util.CheckErr(case when aJson then not fJson.exist(fReqType) else fXML.existsNode(fReqType) <> 1 end, 'Не задан элемент \%s\%s', ROOTELEMENT_REQUEST, fReqType);
    CheckTerminal(aIsHttp, fMsgHeader.terminal, fTermType, fSignSalt);
    CrAccessIsDenied(aTerminal => fMsgHeader.terminal, aRequest => fReqName, aSubsystem => fSubsystem, aExtension => fExtension, aTerminalType => fTermType);
    if aIsHttp then
      TestSignature(fSignSalt, XML);
    end if;

    if aJson then
      fMsgHeader.terminal_time := xml_Util.GetValueT(pljson_ext.get_string(fJson, 'TerminalTime'), 'TerminalTime');
      fJson := pljson_ext.get_json(fJson, fReqType);
    else
      fMsgHeader.terminal_time := xml_Util.GetValueD(fXML, 'TerminalTime');

      TestSession(fXML.extract('/Session'), fMsgHeader.terminal, fMsgHeader.sid, fBool
      , aCheckWhenNotFound=>(fSubsystem is null and upper(fReqType) not in ('NEWS', 'RATES', 'GETACTUALRATES'))
                         or (fSubsystem = ClientAuth_Core.SUB_SYSTEM and upper(fReqType) not in ('LOGIN', 'GETLOGINTYPES', 'EXECUTEACTION')));
      fMsgHeader.ses_auth_checked := case fBool when true then Util.YES when false then Util.NO end;
      if fMsgHeader.sid is not null then
        fMsgHeader.cl_client_id := ClientAuth_Core.GetClientId(fMsgHeader.sid);
      end if;

      fXML := fXML.extract('/' || fReqType);
    end if;
  exception
    when others then
      fReqId := Op_Online.RegRequest
                ( null, null, fReqName, case when aJson then fJsonToLog.to_char else xml_util.SerializeXML(fXMLToLog) end
                , aAddress=>GetIpAddress, aTerminal=>fMsgHeader.terminal, aDirection=>Refs.FILE_DIR_IN, aStartProcessingTime=>fReqRecieved
                , aMaskingRules=>cReqMaskingRules
                );
      raise;
  end;
  fReqId := Op_Online.RegRequest
            ( null, null, fReqName, case when aJson then fJsonToLog.to_char else xml_util.SerializeXML(fXMLToLog) end
            , aAddress=>GetIpAddress, aTerminal=>fMsgHeader.terminal, aDirection=>Refs.FILE_DIR_IN, aStartProcessingTime=>fReqRecieved
            , aMaskingRules=>cReqMaskingRules
            );

  if fSubsystem is not null then
    Util.CheckErr(not Refs.SubsystemExists(fSubsystem), 'Подсистема "%s" не поддерживается сервером', fSubsystem);
    if fExtension is not null then
      fPkgName := upper(fSubsystem) || '#' || fExtension || '#XML';
    else
      fPkgName := upper(fSubsystem) || '_' || upper(Pn1$);
    end if;

    for x in
    ( select null from user_procedures
        where object_name = upper(fPkgName)
          and procedure_name = upper(fReqType)
        having count(*)=0
    ) loop
      Util.RaiseErr('Не найден обработчик сообщения');
    end loop;

    declare
      fErrText varchar2(4000);
      --
      procedure SetDocData
      is
      begin
        if fMsgHeader.doc_type is not null then
          gDocType := fMsgHeader.doc_type;
          gDocId   := fMsgHeader.doc_id;
        end if;
      end;
    begin
      begin
        if aJson then
          execute immediate
               'begin :ErrText:=null;'
            || fPkgName||'.'||fReqType||'(:Header, :Msg, :Response);'
            || 'exception when others then'
            || '  LogWork.NotifyException(:Pn1$, :Pn2$);'
            || '  rollback;'
            || '  :ErrText := Util.NormalizeSqlErrMGetErrorClass(aShortTextForSystemError=>true, aErrorClass=>:ErrorClass);'
            || '  :Response := null;' -- to avoid ORA-22275: invalid LOB locator specified
            || 'end;'
            using
                 out fErrText
            , in out fMsgHeader
            , in     fJson
            ,    out fResponseJson
            , in     Pn1$
            , in     Pn2$
            ,    out fErrorClass
          ;
        else
          --if Refs.IsSubsystemOptionEnabled(fSubsystem, Refs.SUBSYS_OPT_REMOVE_REQUEST_TAG) then
          --  fXML := fXML.extract('/' || fReqType || '/*');
          --end if;
          execute immediate
               'begin :ErrText:=null;'
            || fPkgName||'.'||fReqType||'(:Header, :Msg, :Response);'
            || 'exception when others then'
            || '  LogWork.NotifyException(:Pn1$, :Pn2$);'
            || '  rollback;'
            || '  :ErrText := Util.NormalizeSqlErrMGetErrorClass(aShortTextForSystemError=>true, aErrorClass=>:ErrorClass);'
            || '  :Response := null;' -- to avoid ORA-22275: invalid LOB locator specified
            || 'end;'
            using
                 out fErrText
            , in out fMsgHeader
            , in     fXML
            ,    out aResponse
            , in     Pn1$
            , in     Pn2$
            ,    out fErrorClass
          ;
        end if;
        Util.CheckErrText(fErrText, fErrorClass);
        if aJson then
          fNeedAddAnswerTypeTag := true;
        else
          fNeedAddAnswerTypeTag := aResponse is null or not regexp_like(aResponse, '^\s*<' || fReqType || '(\s+.+|)/?>');
        end if;
        SetDocData;
      exception
        when others then
          SetDocData;
          raise;
      end;
    end;
  else
    fNeedAddAnswerTypeTag := true;
    case fReqType
      when 'CheckDuplicate'     then CheckDuplicate       (fMsgHeader, fXML.extract('/' || fReqType || '/*'), aResponse);
      when 'GetAuthHistory'     then GetAuthHistory       (fMsgHeader, fXML.extract('/' || fReqType || '/*'), aResponse);
      when 'GetUserServices'    then GetUserServices      (fMsgHeader, fXML.extract('/' || fReqType || '/*'), fArrResponse);
      when 'SetUserServices'    then SetUserServices      (fMsgHeader, fXML.extract('/' || fReqType || '/*'), aResponse);
      when 'UserServiceAdd'     then UserServiceAdd       (fMsgHeader, fXML.extract('/' || fReqType || '/*'), aResponse);
      when 'GetUserIdents'      then GetUserIdents        (fMsgHeader, fXML.extract('/' || fReqType || '/*'), aResponse);
      when 'SetAutoPayPriority' then SetAutoPayPriority   (fMsgHeader, fXML.extract('/' || fReqType || '/*'), aResponse);
      when 'ExcludeFromTree'    then ExcludeFromTree      (fMsgHeader, fXML.extract('/' || fReqType || '/*'), aResponse);
      when 'ServiceHistory'     then TestAuth;
                                     ServiceHistory       (fMsgHeader, fXML.extract('/' || fReqType || '/*'), aResponse);
      when 'OperationsHistory'  then GetOperationsHistory (fMsgHeader, fXML.extract('/' || fReqType || '/*'), aResponse); fNotLogging := not RefParam.IsDevDB;
      when 'GetFiles'           then GetFiles             (fMsgHeader, fXML, fArrResponse);
                                     fNotLogging := true;
                                     fNeedAddAnswerTypeTag := false;
      when 'ConfirmFiles'       then ConfirmFiles         (fMsgHeader, fXML.extract('/' || fReqType || '/*'), aResponse);
      when 'ExchangeStart'      then ExchangeStart        (fMsgHeader, fXML.extract('/' || fReqType || '/*'), aResponse);
      when 'ExchangeResult'     then ExchangeResult       (fMsgHeader, fXML.extract('/' || fReqType || '/*'), aResponse);
      when 'ExchangeStorn'      then ExchangeStorn        (fMsgHeader, fXML.extract('/' || fReqType || '/*'), aResponse);
      when 'SearchPerson'       then SearchPerson         (fMsgHeader, fXML.extract('/' || fReqType || '/*'), aResponse);
      when 'SearchDeal'         then SearchDeal           (fMsgHeader, fXML.extract('/' || fReqType || '/*'), fArrResponse); fNotLogging := true;
      when 'News'               then News                 (fMsgHeader, fXML.extract('/' || fReqType || '/*'), aResponse); fNotLogging := not RefParam.IsDevDB;
      when 'Rates'              then Rates                (fMsgHeader, fXML.extract('/' || fReqType || '/*'), aResponse);
      when 'GetActualRates'     then GetActualRates       (fMsgHeader, fXML.extract('/' || fReqType || '/*'), aResponse);
                                else Util.RaiseErr('Неподдерживаемый тип запроса (RequestType:%s) для %s.%s', fReqType, Pn1$, Pn2$);
    end case;
  end if;
  PrepareResponse;
exception
  when xml_Util.eFailedXML or ERR$JSON$SCANNER_EXCEPTION then
    PrepareResponse('Некорректный ' || case when aJson then 'json' else 'XML' end);
  when others then
    LogWork.NotifyException(Pn1$, Pn2$);
    rollback;
    PrepareResponse(Util.NormalizeSqlErrMGetErrorClass(aShortTextForSystemError=>true, aErrorClass=>fErrorClass));
end Admin;

---------
procedure Admin(XML clob)
is
  fResponse clob;
begin
  WorkaroundForModPlSqlBug(Pn1$, 'Admin');
  Admin(XML, fResponse, aIsHttp=>true);
end Admin;

---------
function Admin(XML clob) return clob
is
  pragma autonomous_transaction;
  fResponse clob;
begin
  Admin(XML, fResponse, aIsHttp=>false);
  commit;
  return fResponse;
end Admin;

---------
procedure AdminJson(aData clob, aEncrypted boolean := false)
is
  fResponse clob;
begin
  Admin(aData, fResponse, aIsHttp=>true, aJson=>true, aEncrypted=>aEncrypted);
end AdminJson;

---------
function Subsystems return Util.RefCursor
is
  fCur Util.RefCursor;
  sRE_PluginPackage constant varchar2(99) := '^(\w+)(_'||upper(Pn1$)||'|#\w+#XML)$';
begin
  open fCur for
    select value, name
      from
        ( select distinct regexp_replace(object_name, sRE_PluginPackage, '\1') as value
            from user_procedures
            where regexp_like(object_name, sRE_PluginPackage)
        )
      , ref_subsystem
      where upper(subsystem) = value
    order by name;
  return fCur;
end Subsystems;

---------
function Extensions(aSubsystem varchar2 := null) return Util.RefCursor
is
  fCur Util.RefCursor;
begin
  open fCur for
    select distinct upper(ext) as value, ext as name
      from (select regexp_substr(name, '^[^:]+:[^:]+') as ext, name as nm from ref_online_request  where instr(name, ':', 1, 2) > 0)
      where ( ( upper(replace(ext, ':', '#')) ||'#XML'
              , upper(regexp_substr(nm, '[^:]+$'))
              ) in (select object_name, procedure_name from user_procedures)
              and
              upper(ext) like upper(aSubsystem) || '%'
            )
      order by name;
  return fCur;
end Extensions;

---------
function Requests(aSubsystem varchar2 := null, aExtension varchar2 := null) return Util.RefCursor
is
  fCur Util.RefCursor;
  fCoreRequests tp_varchar2_100_table :=
    tp_varchar2_100_table( 'CheckDuplicate'  , 'GetAuthHistory'    , 'GetUserServices'   , 'SetUserServices'
                         , 'UserServiceAdd'  , 'GetUserIdents'     , 'SetAutoPayPriority', 'ExcludeFromTree'
                         , 'ServiceHistory'  , 'OperationsHistory' , 'PersonalizeToken'  , 'TestToken'
                         , 'GetFiles'        , 'ConfirmFiles'      , 'ExchangeStart'     , 'ExchangeResult'
                         , 'ExchangeStorn'   , 'SearchPerson'      , 'SearchDeal'        , 'News'
                         , 'Rates'           , 'FilterList'        , 'ServiceList'       , 'ServiceTree'
                         , 'ServiceInfo'     , 'TransactionStart'  , 'TransactionResult' , 'Balance'
                         , 'StornStart'      , 'StornResult'       , 'SearchAccount'     , 'SearchNameAndAddr'
                         , 'GetActualRates'  , 'TransactionsStart' , 'TransactionsResult'
                         );
begin
  open fCur for
    select name as value, name
      from ref_online_request
      where ( name member of fCoreRequests
              and
              aSubsystem is null
            )
         or ( ( upper(regexp_replace(regexp_replace(name, '^([^:]+):([^:]+):[^:]+$', '\1#\2#XML'), '^([^:]+):[^:]+$', '\1_XML_ONLINE'))
              , upper(regexp_substr(name, '[^:]+$'))
              ) in (select object_name, procedure_name from user_procedures)
              and
              upper(name) like upper(aSubsystem)
                            || case when aExtension is not null then ':' || upper(aExtension) end
                            || '%'
            )
      order by sign(instr(name, ':')), regexp_substr(name, '^[^:]+'), sign(instr(name, ':', 1, 2)), name;
  return fCur;
end Requests;

-- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

---------
procedure ToForm(name_array in owa.vc_arr, value_array in owa.vc_arr)
is
  Pn2$      constant varchar2(30) := 'ToForm';
  fLogRecs  Util.TStrArr;
  fAnswer   varchar2(32767);
  --
  procedure SaveRequest(aAnswer varchar2, aIsError boolean := false)
  is
  begin
    Op_Online.RegAnswer
    ( Op_Online.RegRequest
      ( null, null
      , Pn1$ || ':' || Pn2$
      , Util.TStrArr2Clob(fLogRecs)
      , aAddress    => Util_IP.GetOwaIpAddress(aOnlyFirst => true)
      , aDirection  => Refs.FILE_DIR_IN
      )
    , fAnswer
    , aIsError=>aIsError
    );
  end SaveRequest;
begin
  fLogRecs(fLogRecs.count + 1) := 'request_method=>'  || owa_util.get_cgi_env('REQUEST_METHOD');
  fLogRecs(fLogRecs.count + 1) := 'path_info=>'  || owa_util.get_cgi_env('PATH_INFO');

  for i in 1..name_array.count loop
    fLogRecs(fLogRecs.count + 1) := name_array(i) || '=' || value_array(i);
    fAnswer := fAnswer || Util.ReplaceMacros
                          ( '<input name="$NAME$" value="$VALUE$" type="hidden">'
                          , Util.TStrs
                            ( '$NAME$' , name_array(i)
                            , '$VALUE$', value_array(i)
                            )
                          );
  end loop;
  owa_util.mime_header('text/html', ccharset => '');
  fAnswer := Util.ReplaceMacros('<!doctype html><html><head><title>To Form</title></head><body><form action="#">$INPUT$</form></body></html>', Util.TStrs('$INPUT$', fAnswer));
  htp.p(fAnswer);

  SaveRequest(fAnswer);
exception
  when others then
    LogWork.NotifyException(Pn1$, Pn2$);
    SaveRequest(Util.NormalizeSqlErrM(aShortTextForSystemError => true), aIsError=>true);
    owa_util.status_line(utl_http.HTTP_BAD_REQUEST, creason=>'Bad request', bclose_header=>false);
    owa_util.mime_header(ccontent_type => 'text/html', bclose_header=>true);
end ToForm;

---------
procedure ProcessRedirect(name_array in owa.vc_arr, value_array in owa.vc_arr)
is
  Pn2$      constant varchar2(30) := 'ProcessRedirect';
  fLogRecs  Util.TStrArr;
  fPrm      Util.TStrs;
  fReqId    int;
  fPrmName  varchar2(100);
  fURL      varchar2(10000);
  fData     varchar2(32000);
begin
  fLogRecs(fLogRecs.count + 1) := 'request_method=>'  || owa_util.get_cgi_env('REQUEST_METHOD');
  fLogRecs(fLogRecs.count + 1) := 'path_info=>'  || owa_util.get_cgi_env('PATH_INFO');
  fLogRecs(fLogRecs.count + 1) := utl_url.unescape(replace(owa_util.get_cgi_env('QUERY_STRING'), '+', ' '));
  fPrm := Util.SubNames2TStrs(fLogRecs(fLogRecs.count), '&');
  fLogRecs(fLogRecs.count) := 'query_string=>' || fLogRecs(fLogRecs.count);

  fReqId :=
    Op_Online.RegRequest
    ( null, null
    , Pn1$ || ':' || Pn2$
    , Util.TStrArr2Clob(fLogRecs)
    , aAddress    => Util_IP.GetOwaIpAddress(aOnlyFirst => true)
    , aDirection  => Refs.FILE_DIR_IN
    );

  for i in 1 .. fPrm.count loop
    if Util.SubName(fPrm(i), 1, '=') = 'BSData' then
      fPrmName := Util.SubName(fPrm(i), 2, '=');
      exit;
    end if;
  end loop;
  Util.CheckErr(fPrmName is null, 'Parameter "BSData" not found');

  for i in 1..name_array.count loop
    case name_array(i)
      when 'BSData' then null;
      when fPrmName then fURL := UtilLob.Blob2Clob(UtilLob.Base64Decode(value_array(i)), 'AL32UTF8');
      else               fData := fData || Util.Format('&'||'%s=%s', name_array(i), value_array(i));
    end case;
  end loop;
  if instr(fURL, '?') = 0 then
    fData := '?' || ltrim('&', fData);
  end if;
  htp.prn(Util.Format('Location: %s%s%s', Util.TStrs(fURL, fData, Util.CRLF)));
  owa_util.status_line(utl_http.HTTP_FOUND);

  Op_Online.RegAnswer(fReqId, fURL || Util.CRLF || fData);
exception
  when others then
    LogWork.NotifyException(Pn1$, Pn2$);
    owa_util.status_line(utl_http.HTTP_BAD_REQUEST, creason=>'Bad request', bclose_header=>true);
    Op_Online.RegAnswer(fReqId, Util.NormalizeSqlErrM(aShortTextForSystemError => true), aIsError=>true);
end ProcessRedirect;

-- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

procedure DownloadFile(file varchar2 := null)
is
begin
  WebData_Processing.DownloadFile(file);
end DownloadFile;

-- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
end xml_OnLine;
/
show err

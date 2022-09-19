prompt create or replace package body SMS_Core

create or replace package body SMS_Core
as

Pn1$                            constant varchar2(30) := 'SMS_Core';

---------
function RegisterMessage
( aSenderMnemonic         varchar2
, aMessage                varchar2
, aPhone                  int
, aDocType                int := null
, aDocId                  int := null
, aOpt                    int := null
, aTerminal               varchar2 := null
, aClientId               int := null
, aMessengerParamsId      int := null
, aTimeout                int := null
, aAutonomousTransaction  boolean := false
) return int
is
  Pn2$ constant varchar2(30) := 'RegisterMessage';
  fResult int;
  --
  procedure Do
  is
  begin
    execute immediate 'begin :Rslt := SMS_Gate.RegisterMessage(:Sender, :Msg, :Phone, :DocType, :DocId, :Opt, :Term, :ClId, :MsngPrm, :Timeout); end;'
      using out fResult
          ,     aSenderMnemonic
          ,     aMessage
          ,     aPhone
          ,     aDocType
          ,     aDocId
          ,     aOpt
          ,     aTerminal
          ,     aClientId
          ,     aMessengerParamsId
          ,     aTimeout;
  end Do;
  --
  procedure DoAuto
  is
    pragma autonomous_transaction;
  begin
    Do;
    commit;
  end DoAuto;
begin
  case when aAutonomousTransaction
    then DoAuto;
    else Do;
  end case;

  return fResult;
exception
  when others then
    LogWork.NotifyException(Pn1$, Pn2$);
    raise;
end RegisterMessage;

---------
procedure SendSMS(aSmsId int, aNoRepeat boolean := false)
is
  Pn2$ constant varchar2(30) := 'SendSMS';
begin
  execute immediate 'begin SMS_Gate.SendSMS(:SmsId, sys.diutil.int_to_bool(:NoRepeat)); end;'
    using aSmsId, sys.diutil.bool_to_int(aNoRepeat);
exception
  when others then
    LogWork.NotifyException(Pn1$, Pn2$);
    raise;
end SendSMS;

---------
function Enabled(aSenderMnemonic varchar2) return boolean
is
  fIntRes int;
begin
  if Administration.ObjExists('SMS_Gate') then
    execute immediate 'begin :Rslt := sys.diutil.bool_to_int(SMS_Gate.Enabled(:Sender)); end;'
      using out fIntRes
          ,  in aSenderMnemonic
    ;
    return sys.diutil.int_to_bool(fIntRes);
  end if;
  return false;
end Enabled;

---------
function IsPhoneValidForSender(aSenderMnemonic varchar2, aPhone int) return boolean
is
  fIntRes int;
begin
  execute immediate 'begin :Rslt := sys.diutil.bool_to_int(SMS_Gate.IsPhoneValidForSender(:Sender, :Phone)); end;'
    using out fIntRes
        ,  in aSenderMnemonic
        ,  in aPhone
  ;
  return sys.diutil.int_to_bool(fIntRes);
end IsPhoneValidForSender;

---------
procedure SendFirebasePUSH(aDeviceId varchar2, aMessage varchar2, aNewsId int := null, aMailId int := null)
is
  Pn2$ constant varchar2(30) := 'SendFirebasePUSH';
  fDummy int;
  fResult varchar2(32767);
begin
  execute immediate 'begin :result := SMS_Gate_Push.SendFirebasePUSH(:device_id, :message, :result_out, :news_id, :mail_id); end;'
    using out fDummy, in aDeviceId, in aMessage, out fResult, in aNewsId, in aMailId;
exception
  when others then
    LogWork.NotifyException(Pn1$, Pn2$);
    raise;
end SendFirebasePUSH;

---------
end SMS_Core;
/
show errors;

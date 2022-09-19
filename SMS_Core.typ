set echo on

--! sms-gate

create or replace type tp_sms_data  as object
( terminal                        varchar2(30)
, phone                           number(12)
, message_in                      varchar2(1000)
--
, message_out                     varchar2(1000)
, options                         int
, doc_type                        int
, doc_id                          int
, ussd_continue_dialog            varchar2(1) -- boolean
);
/
show err

--! sms-bank

create or replace type tp_sms_bank_plug_data as object
( phone                           number(12)
, sms_bank_id                     int
, terminal                        varchar2(30)
, client_id                       int
, ident_id                        int
, is_sms                          varchar2(1) -- boolean
, request                         varchar2(1000)
, service_id                      int -- >0 - loacal, < 0 - ÅÐÈÏ
--
, answer                          varchar2(1000)
, options                         int
, ussd_continue_dialog            varchar2(1) -- boolean
--
, doc_type                        int
, doc_id                          int
--
, constructor function tp_sms_bank_plug_data
  ( self in out nocopy tp_sms_bank_plug_data
  ) return self as result
);
/
show err

create or replace type body tp_sms_bank_plug_data
as
  constructor function tp_sms_bank_plug_data
  ( self in out nocopy tp_sms_bank_plug_data
  ) return self as result
  is
  begin
    return;
  end;
end;
/
show err

set echo off

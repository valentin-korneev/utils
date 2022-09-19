
Prompt create or replace package body WorkLog

create or replace package body WorkLog
as

Pn1$ constant varchar2(30) := 'WorkLog';

gOperatorId constant int := Administration.GetOperatorId;

---------
procedure RegMessage(aText varchar2, aLevel int := LEVEL_INFO, aDocType int := null, aDocId int := null
, aAutonomousTransaction boolean := false
)
is
  fText adm_work_log.text%type := substr(aText, 1, 2000);
  procedure Reg
  is
  begin
    if aText is not null then
      insert into adm_work_log
        (operator_id, audsid, message_level, text, doc_type, doc_id)
        values
        (gOperatorId, userenv('SESSIONID'), aLevel, fText, aDocType, aDocId);
    end if;
  end Reg;
  --
  procedure RegAuto
  is
    pragma autonomous_transaction;
  begin
    Reg;
    commit;
  end RegAuto;
  --
begin
  if aAutonomousTransaction then
    RegAuto;
  else
    Reg;
  end if;
end RegMessage;

---------
procedure RegMessageFmt
( aFormatText varchar2,
  S1 varchar2,
  S2 varchar2 := '', S3 varchar2 := '', S4 varchar2 := '',
  S5 varchar2 := '', S6 varchar2 := '', S7 varchar2 := '',
  S8 varchar2 := '', S9 varchar2 := '', S10 varchar2 := '',
  aLevel int := LEVEL_INFO, aDocType int := null, aDocId int := null
, aAutonomousTransaction boolean := false
)
is
begin
  RegMessage(Util.Format(aFormatText, S1, S2, S3, S4, S5, S6, S7, S8, S9, S10), aLevel, aDocType, aDocId, aAutonomousTransaction);
end RegMessageFmt;

---------
procedure RegMessageFmt
( aFormatText varchar2
, aArgs Util.TStrs
, aLevel int := LEVEL_INFO, aDocType int := null, aDocId int := null
, aAutonomousTransaction boolean := false
)
is
begin
  RegMessage(Util.Format(aFormatText, aArgs), aLevel, aDocType, aDocId, aAutonomousTransaction);
end RegMessageFmt;

---------
procedure RegMessageMacros
( aMessage               varchar2
, aMacros                Util.TStrs
, aLevel                 int      := LEVEL_INFO
, aDocType               int      := null
, aDocId                 int      := null
, aAutonomousTransaction boolean  := false
, aBracketChars          varchar2 := '{}'
)
is
begin
  RegMessage
  ( Util.ReplaceOptionalMacros(aMessage, aMacros, aBracketChars=>aBracketChars)
  , aLevel, aDocType, aDocId, aAutonomousTransaction
  );
end RegMessageMacros;

---------
procedure NightlyJob
is
  Pn2$            constant varchar2(30) := 'NightlyJob';
  cRowsPerDelete  constant int := 10000;
  fDeleted int;
begin
  LogWork.Notify(Pn1$, Pn2$, '-=>');
  loop
    delete adm_work_log
      where inserted < trunc(sysdate) - interval '3' year
        and doc_id is null
        and rownum <= cRowsPerDelete;
    fDeleted := sql%rowcount;
    commit;
    Logwork.NotifyFmt(Pn1$, Pn2$, '<=- deleted %d row(s)', fDeleted);
    exit when fDeleted < cRowsPerDelete;
  end loop;
  LogWork.Notify(Pn1$, Pn2$, '<=- ');
exception
  when others then
    LogWork.NotifyException(Pn1$, Pn2$);
    raise;
end NightlyJob;

---------
end WorkLog;
/
show error

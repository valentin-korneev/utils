prompt
set feed off
set serveroutput on

declare
  s varchar2(32000) := (&1);
begin
  dbms_output.put_line(nvl(s,'(_NULL_)'));
end;
/

set feed on
prompt

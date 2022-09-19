prompt
set feed off

declare
  n int;
begin
  for x in (select name from v$db_pipes where name like 'RCORE%') loop
    n := dbms_pipe.remove_pipe(x.name);
    dbms_output.put_line('Removed pipe ' || x.name);
  end loop;
end loop;
/

set feed on
prompt

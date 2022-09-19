prompt

set serveroutput on size 20480
set feedback off

var Table varchar2(30)
exec :Table:='&1'

declare
  Tabl_   varchar2(30):=upper(:Table);
  SqlStatement varchar2(2000);
  cursor cons_columns(tab in varchar2, cons in varchar2) is
    select column_name from user_cons_columns
      where table_name=upper(tab) and constraint_name=upper(cons)
      order by position;
begin
  dbms_output.put_line('Table "'||Tabl_||'" referenced by table(s):');
  for c in
  ( select a.table_name, b.table_name tname2,
        a.constraint_name cons, b.constraint_name cons_parent,
        a.delete_rule, a.deferrable, a.deferred
      from user_constraints a, user_constraints b
      where b.table_name = Tabl_
        and a.r_constraint_name=b.constraint_name
        and b.constraint_type in ('P','U')
        and a.constraint_type='R'
      order by 1,2
  ) loop
    SqlStatement:=c.table_name||'(';
    for col in cons_columns(c.table_name,c.cons) loop
      SqlStatement:=SqlStatement||col.column_name||',';
    end loop;
    SqlStatement:=rtrim(SqlStatement,',')||')  constraint '||c.cons||
      '  references '||c.tname2||'(';
    for col in cons_columns(c.tname2,c.cons_parent) loop
      SqlStatement:=SqlStatement||col.column_name||',';
    end loop;
    SqlStatement:=rtrim(SqlStatement,',')||')  constraint '||c.cons_parent;
    if c.delete_rule<>'NO ACTION' then
      SqlStatement:=SqlStatement||' on delete '||c.delete_rule;
    end if;
    SqlStatement:=SqlStatement||' '||nullif(c.deferrable, 'NOT DEFERRABLE')||' '||nullif(c.deferred, 'IMMEDIATE');
    dbms_output.put_line(SqlStatement);
  end loop;
  dbms_output.put_line('.');
end;
/

set feedback on

prompt

prompt
set pagesize 0 feed off

select * from table(dbms_xplan.display_cursor(regexp_substr('&1', '[[:alnum:]]+'), regexp_substr('&1', '[[:alnum:]]+', 1, 2), 'ALL'));
set pagesize 40 feed on

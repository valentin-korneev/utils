
--------------------------------------------------------------------------
-- CONSTR.SQL
---
-- Display constraints of table &1
---------

col type_name        for a61 hea 'Table constraint'
col referenced       for a55 hea 'Referenced table constraint'
col search_condition for a60 hea 'Search Condition'
set feed off
var ConstraintTable varchar2(30)
exec :ConstraintTable:=upper('&1')
break on table_name skip 1 on owner skip

select decode(c.status,'ENABLED','+','-')||decode(c.validated,'NOT VALIDATED','?') "$",
    decode(c.constraint_type,
        'P','Pri','U','Uni','R','Ref','C','Chk','V','Vie',
        '?'||c.constraint_type||'?')||' '||
      initcap(c.table_name)||' '||c.constraint_name type_name,
    decode(r.constraint_type,'P','Pri ','U','Uni ')||
      ltrim(initcap(nullif(c.r_owner, user))||'.'||initcap(r.table_name)||' '||
      c.r_constraint_name,'. ') referenced,
    c.delete_rule,
    c.deferrable,
    c.deferred,
    c.search_condition
  , c.generated
  from user_constraints c, all_constraints r
  where c.table_name like :ConstraintTable
    and r.constraint_name(+)=c.r_constraint_name
    and r.owner(+)=c.r_owner
  order by decode(c.constraint_type,'P',1,'U',2,'R',3,'C',4,'V',5,6),
    c.constraint_name;

col type_name cle
col referenced cle
col search_condition cle
cle bre
set feed on
prompt

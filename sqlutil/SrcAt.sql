

set hea off
set feed off

var ErrorLine number
var ErrorSource varchar2(30)
exec :ErrorLine:=&2; :ErrorSource:=upper('&3')


col line for 9999
col text for a255
col type new_v objtype noprint
col name new_v objname noprint
tti left ': ' objtype '  ' objname skip 2
break on type skip page


execute dbms_flashback.enable_at_time(systimestamp - numtodsinterval(&1, 'hour'));

select type,name,line, text
  from user_source
  where name = :ErrorSource
    and line between :ErrorLine-5 and :ErrorLine+5
order by 1,2,3;

execute dbms_flashback.disable;

col line cle
col text cle
col type cle
col name cle

tti off
cle bre

set feed on
set hea on
prompt

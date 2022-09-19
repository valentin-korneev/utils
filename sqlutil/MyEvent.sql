set feed off termout off
col mysid new_value mysid_
select sys_context('userenv', 'sid') as mysid from dual;
col mysid cle
set feed off termout on
@@SesEventAll &mysid_

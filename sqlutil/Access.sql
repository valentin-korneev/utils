col sid      for 9990    hea 'Sid'
col serial#  for 99990  hea 'Ser#'
col audsid   for 999999990 hea 'Audsid'
col username for a16   hea 'UserName' tru
col terminal for a8    hea 'Terminal' tru
col mach_usr for a32   hea 'OsUser@Machine(Terminal)' tru
col locked   for a4    hea 'Lock'
col logon_time for a8  hea 'Connect'
col last_call  for a8  hea 'Last Act'

col owner for a30
col obj for a40

select  /*+ opt_param('_optimizer_cartesian_enabled','false') */
    a.type||' '||a.owner||'.'||a.object as obj,
    a.sid, 
    username,
    decode(status,'ACTIVE','!','INACTIVE','+','KILLED','-','?') "$",
    nullif(osuser||'@'||rtrim(machine, chr(0))|| case when rtrim(machine, chr(0)) not like '%'||terminal then ' ('||terminal||')' end, '@')
      as mach_usr,
    to_char
    ( logon_time,
      case when trunc(logon_time) = trunc(sysdate)       then 'hh24:mi:ss'
           when months_between(sysdate, logon_time) <  1 then 'dd/hh24:mi'
           when months_between(sysdate, logon_time) < 12 then 'dd.mm/hh24'
                                                         else 'mm.yyyy'
      end
    ) as logon_time,
    to_char
    ( sysdate - LAST_CALL_ET*1/24/60/60,
      case when trunc(sysdate - LAST_CALL_ET*1/24/60/60) = trunc(sysdate)       then 'hh24:mi:ss'
           when months_between(sysdate, sysdate - LAST_CALL_ET*1/24/60/60) <  1 then 'dd/hh24:mi'
           when months_between(sysdate, sysdate - LAST_CALL_ET*1/24/60/60) < 12 then 'dd.mm/hh24'
                                                                                else 'mm.yyyy'
      end
    ) as last_call,
    decode(module, null, program,
      program|| ' - '|| module||
        decode(action,null,'',' (act='||action||')')||
        decode(client_info,null,'',' (info='||client_info||')')
    ) program
  from v$access a, v$session s
  where upper(object) like upper('&1')
    and a.type not in ('SYNONYM')
    and s.sid = a.sid
  order by 2, 3, 1 
;

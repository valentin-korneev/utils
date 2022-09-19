col event for a50
col waited for a12
col alive for a12
col pct for 99990.00
bre on alive

select
    lpad(ltrim(trunc(sysdate-s.logon_time)||'d'||to_char(trunc(sysdate)+(sysdate-s.logon_time), 'hh24:mi:ss'), '0d:'), 12) as alive,
    --RCore.Fmtn(round((sysdate-s.logon_time)*24*60*60), 8, 1, 'hh24:mi:ss') as alive,
    e.event,
    lpad(ltrim(trunc(e.time_waited/100/24/60/60)||'d'||to_char(trunc(sysdate)+numtodsinterval(e.time_waited/100,'second'), 'hh24:mi:ss'), '0d:'), 12) as waited,
    --RCore.Fmtn(round(e.time_waited/100), 8, 1, 'hh24:mi:ss') as waited,
    e.time_waited/24/60/60/(sysdate-s.logon_time) as pct,
    e.total_waits, e.total_timeouts as timeouts,
    e.average_wait/100 as average/*, e.max_wait/100 as max_wait*/, e.wait_class
  from (select startup_time as logon_time from v$instance) s,
    (select e.* from v$system_event e) e
  where (e.time_waited > 500 or e.total_waits > 1000)
    --and e.wait_class <> 'Idle'
    and e.event not in ('rdbms ipc message', 'pmon timer', 'smon timer')
  order by decode(e.wait_class, 'Idle', 2, 1), e.time_waited desc
;

col program for a25
col event for a50
col alive for a12
col pct for 990.00
col r_pct for 990.00

break on sid on program on alive skip page

select s.sid, s.program,
    lpad(ltrim(trunc(sysdate-s.logon_time)||'d'||to_char(trunc(sysdate)+(sysdate-s.logon_time), 'hh24:mi:ss'), '0d:'), 12) as alive,
    --RCore.Fmtn(round((sysdate-s.logon_time)*24*60*60), 8, 1, 'hh24:mi:ss') as alive,
    e.event,
    lpad(ltrim(trunc(e.time_waited/100/24/60/60)||'d'||to_char(cast(trunc(sysdate) as timestamp)+numtodsinterval(e.time_waited/100,'second'), 'hh24:mi:ss.ff2'), '0d:'), 15) as waited,
    --RCore.Fmtn(round(e.time_waited/100), 8, 1, 'hh24:mi:ss') as waited,
    e.time_waited/24/60/60/(sysdate-s.logon_time) as pct,
    sum(e.time_waited/24/60/60/(sysdate-s.logon_time)) over (partition by s.sid order by decode(e.wait_class, 'Idle', 2, 1), e.time_waited desc) as r_pct,
    e.total_waits, e.total_timeouts as timeouts,
    e.average_wait/100 as average, e.max_wait/100 as max_wait, e.wait_class
  from v$session s, v$session_event e
  where case when ltrim('&1', '0123456789') is null then case when to_char(s.sid)='&&1' then 0 end
              else case when lower(username) like lower('%&&1%')
                          or lower(program)  like lower('%&&1%')
                          or lower(module)   like lower('%&&1%')
                        then 0 end
        end is not null
    and e.sid = s.sid
    --and e.time_waited > 500
    --and e.wait_class <> 'Idle'
    and e.event not in ('rdbms ipc message', 'pmon timer', 'smon timer')
  order by s.program, s.logon_time, s.sid, decode(e.wait_class, 'Idle', 2, 1), e.time_waited desc
;


col program cle

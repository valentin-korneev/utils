cle bre
tti off
col sid_serial# for a11 hea 'Sid,Ser#'
col audsid   for 999999990 hea 'Audsid'
col username for a20   hea 'User[/Schema]' tru
col terminal for a8    hea 'Terminal' tru
col mach_usr for a32   hea 'OsUser@Machine(Terminal)' tru
col logon_time for a8  hea 'Connect'
col last_call  for a8  hea 'Last Act'
col in_call    for a14 hea 'InCall'
col program    for a71 wra
col waiting    for a80 word_wra
col sql_id_and_child_number for a16
col plsql for a80
col details for a170

set linesize 1000

set feed off
col xyz1 noprint new_v extra_where
col xyz2 noprint new_v extra_order

select '' as xyz1, '' as xyz2 from dual where 1 = 0;
col xyz1 cle
col xyz2 cle
set feed on




select
    sid ||','|| serial# as sid_serial#
  , decode(status,'ACTIVE','!','INACTIVE','+','KILLED','-','?') || nvl2(lockwait,'L','') as "$$"
  , username || decode(schemaname, username, '', '/'||schemaname) as username,
    nullif(osuser||'@'||rtrim(machine, chr(0))|| case when rtrim(machine, chr(0)) not like '%'||terminal then ' ('||terminal||')' end, '@')
      as mach_usr,
    --terminal,
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
    --to_char(sysdate - LAST_CALL_ET*1/24/60/60,decode(trunc(LAST_CALL_ET*1/24/60/60), 0, 'hh24:mi:ss', 'dd/hh24:mi')) last_call,
    decode(status,'ACTIVE', cast(numtodsinterval(LAST_CALL_ET, 'second') as interval day(3) to second(0))) as in_call
  , sql_id|| case when sql_child_number <> 0 then '/' ||sql_child_number end sql_id_and_child_number
  , regexp_replace
    ( case when module like replace(program, '.exe', '%') then module
           when module = program                          then module
                                                          else program || case when module is not null then ' - ' || module end
      end
    , '\(([A-Za-z][A-Z0-9]{3})\)| \(TNS V1-V3\)?|\.worker|ORACLE.EXE|'||nvl((select regexp_replace(host_name, '^[^.]+') from v$instance),'xYzAbC'), '\1'
    )
    || decode(action,null,'',' (act='||action||')')
    || decode(client_info,null,'',' ('||client_info||')')
    --  as program
  ||case when PLSQL_ENTRY_OBJECT_ID is not null or PLSQL_OBJECT_ID is not null then '  PLS:' end
  ||case when PLSQL_ENTRY_OBJECT_ID is not null then
      nvl
      ( ( select case when p.owner <> user then p.owner||'.' end
              || p.object_name || case when p.PROCEDURE_NAME is not null then '.' || p.PROCEDURE_NAME end
              || case when overload <> 1 then '['||overload||']'end
            from all_procedures p
            where p.OBJECT_ID     = v$session.PLSQL_ENTRY_OBJECT_ID
              and p.SUBPROGRAM_ID = v$session.PLSQL_ENTRY_SUBPROGRAM_ID
        )
      , PLSQL_ENTRY_OBJECT_ID || '/' || PLSQL_ENTRY_SUBPROGRAM_ID
      )
    end
  ||case when PLSQL_OBJECT_ID is not null then
      ' -> '
    ||coalesce
      ( ( select case when p.owner <> user then p.owner||'.' end
              || p.object_name || case when p.PROCEDURE_NAME is not null then '.' || p.PROCEDURE_NAME end
              || case when overload <> 1 then '['||overload||']'end
            from all_procedures p
            where p.OBJECT_ID     = v$session.PLSQL_OBJECT_ID
              and p.SUBPROGRAM_ID = v$session.PLSQL_SUBPROGRAM_ID
        )
      , nvl((select object_name from all_objects where object_id = v$session.PLSQL_OBJECT_ID), PLSQL_OBJECT_ID) || '/' || PLSQL_SUBPROGRAM_ID
      )
    end
    -- as plsql
  ||case wait_time when 0 then
      '  ?:'||seconds_in_wait||'s '||wait_class||': '||event
    ||case when p1text is not null then
        ' ('||p1text||'='||p1
      ||case when p2text is not null then
          ', '||p2text||'='||p2
        ||case when p3text is not null then
            ', '||p3text||'='||p3
          end
        end
      || ')'
      end
    end
      as details
    -- as waiting -- ќжидание
  , case when audsid < power(2,31) then audsid else round(audsid - power(2,32)) end as audsid
  from v$session
  where 1 = 1 &extra_where
  order by    &extra_order
    v$session.logon_time;

undefine extra_where
undefine extra_order

col sid_serial# cle
col audsid   cle
col username cle
col mach_usr cle
col terminal cle
col logon_time cle
col last_call  cle
col program    cle

prompt

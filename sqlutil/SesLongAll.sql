col opname for a20
col target for a32
col progress for a32
col time for a15 hea "Time(/Total)" 
col username for a20
col sql_text for a200
col sid for 9990
col serial# for 999990
col context for 90 hea "Ctx"


set feed off termout off
col rem new_value start_of_rem noprint
define start_of_rem="--"
select ' ' rem from v$sql where rownum = 1;
col rem cle
set feed on termout on

select 
    sid
  , serial#
  , opname
  , replace(replace(trim(target || ' ' || target_desc), user||'.'), 'OWNER') as target
  , case when sofar <> totalwork then sofar||'('||round(sofar/nullif(totalwork,0)*100)||'%) of ' end||totalwork||' '||units as progress
  , to_char(start_time, 'hh24:mi:ss') as start_time
  , to_char(LAST_UPDATE_TIME, 'hh24:mi:ss') as last_update_time
  , ltrim((last_update_time - start_time) day to second(0), '+0 :') 
    || case when sofar <> totalwork then
       '/'|| ltrim(cast((last_update_time - start_time) day to second*(totalwork/nullif(sofar,0)) as interval day to second(0)), '+0 :')
       end as time
  , username
  , sql_id
    &start_of_rem , (select sql_text from v$sql s where s.sql_id = sl.sql_id and rownum = 1) as sql_text 
  from v$session_longops sl
  --where last_update_time > sysdate - 1/24 
  order by start_time desc
;

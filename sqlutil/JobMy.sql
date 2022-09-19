cle bre
tti off
col job        for 999990   hea 'Job#'
col SCHEMA_USER for a17     hea 'SchemaOwner'
col PRIV_USER  for a17      hea 'PrivsOfUser'
col LOG_USER   for a17      hea 'LoggedUser'
col total_time for 99999990 hea 'TotalSec'
col what       for a30 wor  hea 'What (PL/SQL block)'
col interval   for a20 wor  hea 'Interval'
col flag       for a1       hea '$'
col last_date               hea 'LastSuccess'
col this_date               hea 'StartTime'
col next_date               hea 'NextStartTime'

prompt
prompt *******************************************************************
prompt ** Queued Jobs (R,r-running; Q,q-queued; R,Q-ready; r,q-broken)  **

select j.job,
    decode(j.broken,
      'Y', decode(j.this_date,null,'q','r'),
      'N', decode(j.this_date,null,'Q','R'),
      '?') flag,
    substr(j.what, 1, 30) what, j.next_date, j.interval, j.last_date, j.this_date,
    j.SCHEMA_USER, j.PRIV_USER, j.LOG_USER, j.failures, j.total_time
  from DBA_JOBS j
  where j.SCHEMA_USER=
    ( select schemaname from v$session where audsid=userenv('sessionid'))
  order by j.this_date, j.next_date
;

col job        cle
col SCHEMA_USER cle
col PRIV_USER  cle
col LOG_USER   cle
col total_time cle
col what       cle
col interval   cle
col flag       cle
col last_date  cle
col this_date  cle
col next_date  cle
cle bre

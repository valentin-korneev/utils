set recsep off
cle bre
col audsid     for 999999990
col srcsubsrc  for a42    hea 'Источник^Подысточник' wor
col msg        for a150   hea 'Сообщение'            wra
col time       for a18    hea 'Послано'

set feed off
col xyz1 noprint new_v minutes_to_log
col xyz2 noprint new_v log_time
col xyz3 noprint new_v extra_where
select '' as xyz1, '' as xyz2, '' as xyz3 from dual where 1 = 0;
col xyz1 cle
col xyz2 cle
set feed on

select --+ index(log_info log_info$i$trunc_time_mi)
    src||'^'||subsrc srcsubsrc, audsid, to_char(time,'hh24:mi:ss,ff9') time, msg
  from log_info
  , ( select nvl(t, sysdate - i) as t, i
        from
        ( select to_date('&log_time', 'hh24miss') + to_char(sysdate, 'dd') - 1 as t
               , numtodsinterval(nvl('&minutes_to_log', 15)    , 'minute') as i
            from dual
        )
    )
  where trunc(time, 'mi') between trunc(t, 'mi') - interval '1' minute and trunc(t, 'mi') + i + interval '2' minute
    and       time        between       t                              and       t        + i + interval '1' second
  /**/  &extra_where
  order by log_info.time;

undefine minutes_to_log
undefine log_time
undefine extra_where

cle bre
col audsid     cle
col srcsubsrc  cle
col time       cle
--tti off

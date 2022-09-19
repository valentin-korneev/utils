col name for a45
select s.sid, s.value, n.name from v$statname n, v$sesstat s
  where s.statistic#=n.statistic#
    and s.value<>0
    and n.name in
    ( 'redo size'
    )
  order by s.sid, n.class, n.statistic#
;
col name cle

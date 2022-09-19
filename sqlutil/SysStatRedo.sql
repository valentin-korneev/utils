col name for a45
select s.value, n.name from v$statname n, v$sysstat s
  where s.statistic#=n.statistic#
    --and (n.class in (8, 64, 1) or n.statistic# in (133, 134, 135))
    and s.value<>0
    and (n.name like '%redo%' or n.name like '%commit%')
  order by n.class, n.statistic#
;
col name cle

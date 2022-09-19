col name for a45
select s.value, n.name from v$statname n, v$sesstat s
  where s.sid=&1
    and s.statistic#=n.statistic#
    and (n.class in (8, 64, 1) or n.statistic# in (133, 134, 135))
    and s.value<>0
/*    and n.name in
    ( 'recursive calls',
      'db block gets',
      'consistent gets',
      'physical reads',
      'sorts (memory)',
      'sorts (disk)',
      'rows processed'
    )*/
  order by n.class, n.statistic#
;
col name cle

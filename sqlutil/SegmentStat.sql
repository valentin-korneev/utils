col owner for a20 tru
col statistic_name for a20

select s.owner, s.object_name, s.STATISTIC_NAME, sum(s.value) value, ss.blocks,
    Round(sum(s.value)/ss.blocks/100) "%"
  from v$segment_statistics s, dba_segments ss
  where statistic# in (0,2,3) and s.owner not like '%SYS%'
    and s.object_name=ss.segment_name
    and s.owner=ss.owner
  group by s.owner, s.object_name, s.STATISTIC_NAME, ss.blocks
  order by 1,2,3;

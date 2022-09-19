col object_name for a30



SELECT OWNER, OBJECT_NAME
  FROM V$SEGMENT_STATISTICS
  WHERE STATISTIC_NAME = 'ITL waits'
    AND VALUE > 0;

Select s.sid            SID,
      s.serial#   Serial#,
      l.type            type,
      ' '         object_name,
      lmode             held,
      request     request
      from v$lock l, v$session s, v$process p
      where s.sid = l.sid and
            s.username <> ' ' and
            s.paddr = p.addr and
            l.type <> 'TM' and
            (l.type <> 'TX' or l.type = 'TX' and l.lmode <> 6)
union
select      s.sid       SID,
      s.serial#   Serial#,
      l.type            type,
      object_name object_name,
      lmode       held,
      request           request
      from v$lock l, v$session s, v$process p, sys.dba_objects o
      where s.sid = l.sid and
            o.object_id = l.id1 and
            l.type = 'TM' and
            s.username <> ' ' and
            s.paddr = p.addr
union
select      s.sid       SID,
      s.serial#   Serial#,
      l.type            type,
      '(Rollback='||rtrim(r.name)||')' object_name,
      lmode             held,
      request           request
      from v$lock l, v$session s, v$process p, v$rollname r
      where s.sid = l.sid and
            l.type = 'TX' and
            l.lmode = 6 and
            trunc(l.id1/65536) = r.usn and
            s.username <> ' ' and
            s.paddr = p.addr
order by 5, 6
;

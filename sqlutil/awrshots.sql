col STARTUP_TIME for a25
col BEGIN_INTERVAL_TIME for a25
col END_INTERVAL_TIME  for a25
col FLUSH_ELAPSED  for a20
select * from DBA_HIST_SNAPSHOT order by SNAP_ID;
set feed off
select * from sys.WRM$_SNAPSHOT where status <> 0 order by SNAP_ID;
set feed on

set feed off
--alter session set sql_trace=false timed_statistics=false;
alter session set events '10046 trace name context off' statistics_level=typical;

set feed on

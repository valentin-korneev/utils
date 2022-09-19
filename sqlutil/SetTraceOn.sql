set feed off
alter session set events '10046 trace name context forever, level 12' statistics_level=all;
set feed on

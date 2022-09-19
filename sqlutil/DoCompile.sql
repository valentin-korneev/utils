set feedback off
col script_dir_ new_value script_dir noprint

select nvl(regexp_replace('&1', '[\][^\]+$'), '.')  as script_dir_ from dual;

col script_dir_ clear
set feedback on
set time on
set timing on

start "&1"
exit

set feed off

col sql_text for a150 wor
col child_number   for 999 hea '#' newline
col child_latch    for 99 hea 'L#'
col executions     for 9999999999 hea 'Executions'
col disk_reads     for 9999999999 hea 'DiskReads'
col buffer_gets    for 9999999999 hea 'BufferGets'
col rows_processed for 9999999999 hea '#_Rows'
col fetches        for 9999999999 hea 'Fetches'
col sorts          for 99999999 hea 'Sorts'
col loads          for 9999 hea 'Loads'
col invalidations  for 9999 hea 'Inval'
col parse_calls    for 9999999999 hea 'ParseCalls'
col Disk_ratio     for 990.00 hea 'DiskR%'
col username       for a15 tru
col parse_ratio    for 990.00 hea 'Parse%'
col buf_per_exec   for 99999990 hea 'Buf/Exec'
col cpu_time       for 999990.0000
col elapsed_time   for 999990.0000

set feed off
col xyz1 noprint new_v sqlarea_where
col xyz2 noprint new_v sqlarea_order
select '' as xyz1, '' as xyz2 from dual where 1 = 0;
col xyz1 cle
col xyz2 cle
set feed on




select
    sql_text,
    child_number,
    child_latch,
    to_date(first_load_time, 'yyyy-mm-dd/hh24:mi:ss') as first_load_time,
    --address as "Sql Addr",
    executions,
    disk_reads,
    buffer_gets,
    rows_processed,
    fetches,
    sorts,
    loads,
    invalidations,
    parse_calls,
    decode(buffer_gets, 0, to_number(null), disk_reads / buffer_gets * 100) Disk_ratio,
    decode(executions, 0, to_number(null), parse_calls / executions * 100) parse_ratio,
    decode(executions, 0, to_number(null), buffer_gets / executions) buf_per_exec,
    cpu_time/1e6 as cpu_time,
    elapsed_time/1e6 as elapsed_time,
    substr(round(elapsed_time/1e6/nullif(executions, 0),least(-trunc(log(10, elapsed_time/1e6/nullif(executions, 0)))+2, 5)), 1, 6) as "Ela/E",
    sql_id,
    last_active_time,
    last_load_time,
    (select u.username from all_users u where u.user_id = s.parsing_schema_id) as username,
    hash_value
  , nvl((select owner||'.'||object_name from all_objects where object_id = program_id), '#'||program_id) || ':' || program_line# as from_program
  from v$sql s
  where( upper(sql_text) like upper('%&1%') escape '\'
         or
         sql_id = '&1'
       )
    and sql_text not like '%to_date(first_load_time%v$sql%'
    and upper(sql_text) not like 'EXPLAIN PLAN%'
    and upper(sql_text) not like 'BEGIN%'
    and upper(sql_text) not like 'DECLARE%'
    and upper(sql_text) not like '%DBMS_XPLAN%'
    and sql_text not like '%dbms_stats%'
    and sql_text not like '%OPT_DYN_SAMP%'
    and sql_text not like '%SQL Analyze%'
    and executions <> 0
    &sqlarea_where
  order by &sqlarea_order sql_text, child_number;

undefine sqlarea_where
undefine sqlarea_order

set feed on
prompt

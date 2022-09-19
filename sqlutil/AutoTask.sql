select operation_name, status from dba_autotask_operation;
select t.client_name,t.task_name,t.operation_name,t.status,t.last_good_date,t.last_try_result from dba_autotask_task t;

col client_name for a40 
col job_duration for a15
col window_name for a18
col job_status for a10
col job_info for a100
select client_name
     , cast(job_start_time as date) as job_start_time
     , job_duration
     , cast(job_start_time + job_duration as date) as job_finish_time
     , window_name
     , job_status
     , job_error
     , job_info
  from dba_autotask_job_history
  where job_start_time>trunc(sysdate)-7
  order by job_start_time desc
;

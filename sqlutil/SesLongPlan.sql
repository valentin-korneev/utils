col operation for a50

with
  q_sess as (select sql_id, sql_child_number, s.sql_exec_id, s.sid
               from v$session s where s.status = 'ACTIVE' and s.audsid <> 0 and s.sid <> sys_context('userenv', 'sid')),
  q_plan as (select id, lpad(' ',depth * 2,' ')||operation||' '||options operation, object_name, cardinality, bytes, cost
                  , p.sql_id, p.child_number, s.sql_exec_id, s.sid
               from v$sql_plan p, q_sess s
              where (p.sql_id, p.child_number) = ((s.sql_id, s.sql_child_number))
            )
select q_plan.sid
     , q_plan.id, q_plan.operation, q_plan.object_name, q_plan.cardinality, q_plan.bytes, q_plan.cost
     , round(lo.sofar/lo.totalwork*100) pct, lo.elapsed_seconds, lo.time_remaining
  from q_plan
     , v$session_longops lo
 where lo.sid(+) = q_plan.sid
   and lo.sql_plan_line_id(+) = q_plan.id
   and lo.sql_exec_id(+) = q_plan.sql_exec_id
   and lo.sql_id(+) = q_plan.sql_id
 order by sid, id;

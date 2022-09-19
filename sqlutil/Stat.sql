set feed off
set hea off
tti left docno skip 2
col doc noprint new_v docno
col changed for a23
select (select rdt.name from ref_doc_type rdt where rdt.doc_type = sl.doc_type) || ' (' || sl.doc_type || ')  #' || doc_id doc,
    to_char(sl.changed, 'dd.mm.yyyy hh24:mi:ss.ff3') as changed,
    sl.status,
    (select rs.name from ref_status rs where decode(rs.status, sl.status, 0) = 0) as description,
    sl.operator_id,
    (select ao.username || ' (' || ao.fio || ')' from adm_operator ao where id = sl.operator_id) as operator_name
  from status_log sl
  where sl.doc_type = (select rdt.doc_type from ref_doc_type rdt where rdt.table_name like upper('&2'))
    and sl.doc_id = &1
  order by sl.changed;
col doc cle
col changed cle
tti off
set hea on
set feed on
prompt

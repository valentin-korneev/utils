
select object_type, object_name, subobject_name, statistic_name, value
  from v$segment_statistics
  where owner = user
    and value <> 0
    and (upper(object_name) like upper('&1') or upper(subobject_name) like upper('&1'))
  order by  owner, object_type, object_name, subobject_name, statistic#;

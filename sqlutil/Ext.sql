rem ------------------------------------------------
rem -- Show extent usage for all objects like '&1'
rem ------------------------------------------------
prompt
col segment for a64 hea 'Object'
--col max_extents for a10 justify right hea 'MaxExtents'
--col next_extent for 99990 hea 'Next'
col cnt for 99990 hea 'Extents'
col kbytes for 9G999G999G999 hea 'KBytes'
col blocks for 999999990 hea 'Blocks'
col tablespace_name for a15 hea 'TableSpace'
col pct_free for 990 hea 'PctFree'
col extra_info for a100
col data_object_id for 9999999 hea "DataObjId"
compute sum of cnt    on report
compute sum of kbytes on report
compute sum of blocks on report
break on report

set feed off
col xyz1 noprint new_v ext_where
select '' as xyz1 from dual where 1 = 0;
col xyz1 cle
set feed on



select
    replace(replace(replace(replace(lower(s.segment_type)
    , 'table partititon', 'tab part'), 'table subpartition', 'tab subpart')
    , 'index partititon', 'ind part'), 'index subpartition', 'ind subpart')
      || ' ' || s.segment_name || case when s.partition_name is not null then '.'||s.partition_name end segment,
--    decode(trunc(s.max_extents/1000000), 0, to_char(s.max_extents),
--      null, '???', 'Unlimited') max_extents,
--    s.next_extent/1024 next_extent,
    s.extents cnt,
    s.bytes/1024 kbytes,
    s.blocks blocks,
    o.pct_free,
    s.tablespace_name,
    o.last_analyzed,
    o.num_rows,
    to_char(o.sample_size/nullif(o.num_rows,0)*100, '990.0') as "Smpl %"
  , oo.data_object_id
  , case when s.segment_type in ('LOBSEGMENT', 'LOBINDEX')
         then ( select l.table_name||'.'||l.column_name
                    || case when s.segment_type = 'LOBSEGMENT'
                            then ', ' || decode(l.in_row, 'YES', 'In', 'Out of') || ' row'
                              || case when l.pctversion is not null then ', Pctversion='||l.pctversion end
                              || case when l.retention  is not null then ', Retention=' ||l.retention  end
                              || case when l.securefile = 'YES' then ', SecureFile' end
                              || case when l.compression = 'YES' then ', Compression' end
                       end
                  from user_lobs l
                  where decode(s.segment_type, 'LOBSEGMENT', l.segment_name, l.index_name) = s.segment_name
              )
         else o.extra_info
    end as extra_info
  from user_segments s, user_objects oo,
  ( select 'TABLE' segment_type, table_name segment_name, null subsegment_name, pct_free, last_analyzed, num_rows, sample_size,
        trim(        case when trim(degree) not in ('1') then 'DOP='||trim(degree) end
           || ' ' || case when ini_trans > 1 then 'Ini_trans='||ini_trans end
            ) as extra_info
      from user_tables
    union all
    select 'TABLE PARTITION' segment_type, table_name segment_name, partition_name subsegment_name, pct_free, last_analyzed, num_rows, sample_size,
        trim(rtrim(  case when ini_trans > 1 then 'Ini_trans='||ini_trans||', ' end
                  || case when GLOBAL_STATS = 'YES' then 'Global_stats=YES, ' end
                  || case when USER_STATS = 'YES' then 'User_stats=YES, ' end
                  || case when nvl(subpartition_count, 0) <> 0 then 'SubPartitions count=' || subpartition_count ||', ' end
                  || 'High Value='||
                     extractvalue(dbms_xmlgen.getxmltype(
                       'select HIGH_VALUE from USER_TAB_PARTITIONS where TABLE_NAME='''||table_name||''' and PARTITION_NAME='''||partition_name||'''')
                       , '//HIGH_VALUE')
                  , ', ')
            ) as extra_info
      from user_tab_partitions
    union all
    select 'TABLE SUBPARTITION' segment_type, table_name segment_name, subpartition_name subsegment_name, pct_free, last_analyzed, num_rows, sample_size,
        trim(rtrim( ' ' || case when ini_trans > 1 then 'Ini_trans='||ini_trans||', ' end
                  || case when GLOBAL_STATS = 'YES' then 'Global_stats=YES, ' end
                  || case when USER_STATS = 'YES' then 'User_stats=YES, ' end
                  || 'High Value='||
                     extractvalue(dbms_xmlgen.getxmltype(
                       'select HIGH_VALUE from USER_TAB_SUBPARTITIONS where TABLE_NAME='''||table_name||''' and SUBPARTITION_NAME='''||subpartition_name||'''')
                       , '//HIGH_VALUE')
                  , ', ')
            ) as extra_info
      from user_tab_subpartitions
    union all
    select 'INDEX' segment_type, index_name segment_name, null subsegment_name, pct_free, last_analyzed, num_rows, sample_size,
        trim(        'CF='||CLUSTERING_FACTOR
           || ' ' || case when trim(degree) not in ('1', '0') then 'DOP='||trim(degree)||' ' end
                  || nullif(uniqueness, 'NONUNIQUE')
           || ' ' || trim(replace(index_type, 'NORMAL'))
           || ' ' || case when prefix_length > 0 then 'Prefix='||prefix_length end
           || ' ' || case when ini_trans > 2 then 'Ini_trans='||ini_trans end
           /*|| ' ' || case when index_type = 'FUNCTION-BASED NORMAL' then
                       ( select sys_connect_by_path(ie.column_expression, '~')
                           from user_ind_expressions ie
                           start with ie.index_name = i.index_name and ie.column_position = 1
                           connect by ie.index_name = i.index_name and ie.column_position = prior ie.column_position + 1
                       )
                     end*/
            ) as extra_info
      from user_indexes i
    union all
    select 'CLUSTER' segment_type, cluster_name segment_name, null subsegment_name, pct_free, null, null, null, 'Size='||key_size as extra_info
      from user_clusters
  ) o
  where s.segment_name like upper(substr('&1', 1, nvl(nullif(instr('&1', ','), 0) - 1, 4000))) escape '\'
    and o.segment_type(+) = s.segment_type
    and o.segment_name(+) = s.segment_name
    and decode(o.subsegment_name(+), s.partition_name, '=') = '='
    and s.bytes/1024 > nvl(to_number(substr('&1', nullif(instr('&1', ','), 0) + 1)), 0) * 1024
    and oo.object_type(+) = s.segment_type
    and oo.object_name(+) = s.segment_name
    and decode(oo.subobject_name(+), s.partition_name, '=') = '='
    &ext_where
  order by s.segment_type desc, s.segment_name || case when s.partition_name is not null then '.'||s.partition_name end
;

undefine ext_where

col segment cle
--col max_extents cle
--col next_extent cle
col cnt cle
col kbytes cle
col blocks cle
col pct_free cle
col tablespace_name cle
cle compute
cle break
prompt

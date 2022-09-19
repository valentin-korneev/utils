prompt
prompt ClusterKeys/Block histogram for clusterized table "&1" on key "&2"

select count(*) block_count, cluster_keys_per_block
  from
  ( select count(*) cluster_keys_per_block
      from
      ( select distinct &2, dbms_rowid.rowid_relative_fno(rowid)||'~'||dbms_rowid.rowid_block_number(rowid) block_id from &1
      )
      group by block_id
  )
  group by cluster_keys_per_block
  order by 1 desc
;

select avg(count(*)) avg_cluster_keys_per_block
  from
  ( select distinct &2, dbms_rowid.rowid_relative_fno(rowid)||'~'||dbms_rowid.rowid_block_number(rowid) block_id from &1
  )
  group by block_id
;

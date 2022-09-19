prompt
prompt Rows/Block histogram for table &1

select count(*) block_count, rows_per_block
  from
  ( select count(*) rows_per_block
      from &1
      group by dbms_rowid.rowid_relative_fno(rowid)||'~'||dbms_rowid.rowid_block_number(rowid)
  )
  group by rows_per_block
  order by 1 desc
;

select sum(rows_per_block) as row_count, count(*) as block_count, avg(rows_per_block) avg_rows_per_block
  from
  ( select count(*) rows_per_block
      from &1
      group by dbms_rowid.rowid_relative_fno(rowid)||'~'||dbms_rowid.rowid_block_number(rowid)
  )
;

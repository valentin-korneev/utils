
--------------------------------------------------------------------------
-- COLS.SQL
---
-- Display columns of table &1
---------

set feed off

var CTable varchar2(30)
begin
  select object_name into :CTable
    from user_objects where upper(object_name) = upper('&1') and rownum = 1;
exception
  when no_data_found then :CTable := '';
end;
/

col column_id    for 999    hea 'Id'
col internal_column_id for 999 hea 'fiz'
col column_name  for a30    hea 'Column name'
col data_type    for a21    hea 'Data type'
col nullable     for a1     hea 'n'
col data_default for a80    hea 'Default'
col num_distinct for 9999999999 hea 'Distinct'
col num_nulls    for 9999999999 hea 'Nulls'
col density      for 0.000000 hea 'Density'
col sample_size  for 9999999999 hea 'SampleSz'
col value_range  for a150    hea 'Value range'
col col_comments for a200

select
    c.column_id
  , nullif(c.internal_column_id, c.column_id) as internal_column_id
  , decode(virtual_column, 'YES', 'V') || decode(hidden_column, 'YES', 'H') as "$$"
  , c.column_name
  , c.data_type ||
      decode
      ( regexp_replace(c.data_type, '^(N?(|VAR)CHAR2?|RAW)$', '#'),
          'NUMBER', decode(c.data_scale, null, '',
            '(' || nvl(to_char(c.data_precision), '*') ||
              case when c.data_scale <> 0 or c.data_scale = 0 and c.data_precision is null then ',' || c.data_scale end || ')'),
          'FLOAT', decode(c.data_precision, null, '',
            '(' || c.data_precision || ')'),
          '#', decode(c.data_length, null, '', '(' || case when c.char_used = 'C' then to_char(c.char_length) || ' CHAR' else to_char(c.data_length) end || ')')
      )
      as data_type
  , c.nullable
  , c.num_distinct
  , c.num_nulls
  , c.density
  , c.last_analyzed
  , c.sample_size
  , c.histogram
  , c.data_default
  --, c.low_value || ' - ' || c.high_value value_range
  , n.comments as col_comments
  from user_tab_cols c, user_col_comments n
  where c.table_name = :CTable
    and n.table_name(+) = c.table_name
    and n.column_name(+) = c.column_name
  order by c.column_id, c.internal_column_id
;

col column_id    cle
col column_name  cle
col data_type    cle
col nullable     cle
col data_default cle
col num_distinct cle
col num_nulls    cle
col density      cle
col sample_size  cle
col value_range  cle


set feed on
prompt

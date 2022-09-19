
--------------------------------------------------------------------------
-- DbFiles.sql - Database files with autoextend information
---------

col file# for 9999 hea 'File#'
col megabytes for 9g999g999 hea 'Size'
col maxextend for 9g999g999 hea 'MaxSize'
col inc for 9999 hea 'Increment'
col min_resize for 99g999 hea 'MinResize'
col name for a60 hea 'Name'
col tablespace for a15 wra Hea 'Tablespace'
col free for 9g999g999 hea 'Free'
col ord noprint
compute sum of megabytes on tablespace
compute sum of maxextend on tablespace
compute sum of free on tablespace
compute sum of megabytes on report
compute sum of maxextend on report
bre on tablespace skip 1 on report

select * from
(
select tablespace_name as tablespace
     , f.file_id as file#
     , f.bytes/1024/1024 as megabytes
     , decode
       ( f.maxblocks
       , null, to_number(null)
       , f.maxbytes/1024/1024
       ) as maxextend
     , decode
       ( f.increment_by
       , null, to_number(null)
       , f.increment_by*(f.bytes/f.blocks)/1024/1024
       ) as inc
     , ceil(nvl(r.min_resize,0)*(f.bytes/f.blocks)/1024/1024) min_resize
     , (f.bytes - nvl(r.used, 0)*(f.bytes/f.blocks))/1024/1024 as free
     , (select ff.creation_time from v$tempfile ff where ff.file# = f.file_id) as creation_time
     , file_name as name
     , 1 as ord
  from dba_temp_files f
  , ( select
          SEGFILE# -200 file#
        , max(SEGBLK# + BLOCKS) as min_resize
        , sum(BLOCKS) as used
        from V$TEMPSEG_USAGE
        group by SEGFILE#
    ) r
  where r.file#(+) = f.file_id
union all
select tablespace_name as tablespace
     , f.file_id as file#
     , f.bytes/1024/1024 as megabytes
     , decode
       ( f.maxblocks
       , null, to_number(null)
       , round(f.maxbytes/1024/1024,0)
       ) as maxextend
     , decode
       ( f.increment_by
       , null, to_number(null)
       , f.increment_by*(f.bytes/f.blocks)/1024/1024
       ) as inc
     , ceil(nvl(r.min_resize,0)*(f.bytes/f.blocks)/1024/1024) min_resize
     , (f.bytes - nvl(r.used,0))/1024/1024 as free
     , (select ff.creation_time from v$datafile ff where ff.file# = f.file_id) as creation_time
     , file_name as name
     , 2 as ord
  from dba_data_files f
  , ( select
          e.file_id file#
        , max(e.block_id + e.blocks) as min_resize
        , sum(bytes) as used
        from dba_extents e
        group by e.file_id
    ) r
  where r.file#(+) = f.file_id
)
  order by ord, min(file#) over (partition by tablespace),  tablespace, file#
;

col file# cle
col megabytes cle
col maxextend cle
col inc cle
col min_resize cle
col name cle
col free cle

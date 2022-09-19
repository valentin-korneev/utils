set ver off
set serveroutput on

prompt
declare
  p_segname varchar2(30) := regexp_substr(upper('&1'), '[^.]+', 1, 1);
  p_owner varchar2(30) := user;
  p_type varchar2(50) := '&2';
  p_partition varchar2(100) := regexp_substr(upper('&1'), '[^.]+', 1, 2);
  l_free_blks                 number;
  l_total_blocks              number;
  l_total_bytes               number;
  l_unused_blocks             number;
  l_unused_bytes              number;
  l_LastUsedExtFileId         number;
  l_LastUsedExtBlockId        number;
  l_LAST_USED_BLOCK           number;
  l_segment_space_mgmt        varchar2(255);
  l_unformatted_blocks number;
  l_unformatted_bytes number;
  l_fs1_blocks number; l_fs1_bytes number;
  l_fs2_blocks number; l_fs2_bytes number;
  l_fs3_blocks number; l_fs3_bytes number;
  l_fs4_blocks number; l_fs4_bytes number;
  l_full_blocks number; l_full_bytes number;

  procedure p( p_label in varchar2, p_num in number )
  is
  begin
      dbms_output.put_line(rpad(p_label, 40, '.') || lpad(to_char(p_num, '999g999g999g990', 'nls_numeric_characters='', '''), 15));
  end;
begin
  p_type := case lower(p_type) when 't' then 'TABLE' when 'i' then 'INDEX' when 'l' then 'LOB' else p_type end;
  dbms_output.put_line('');
  dbms_output.put_line(rpad('=', 56, '='));
  dbms_output.put_line(p_type||'.'||p_segname ||rtrim('.'||p_partition, '.'));
  dbms_output.put_line(rpad('=', 56, '='));
  dbms_output.put_line('');
  /*begin
    execute immediate
      ' select ts.segment_space_management
          from dba_segments seg, dba_tablespaces ts
         where seg.segment_name      = :p_segname
           and (:p_partition is null or
               seg.partition_name = :p_partition)
           and seg.owner = :p_owner
           and seg.tablespace_name = ts.tablespace_name
       '
       into*/ l_segment_space_mgmt := 'AUTO';
       /*using p_segname, p_partition, p_partition, p_owner;
   exception
       when too_many_rows then
          dbms_output.put_line('Это секционированная таблица, используйте p_partition => ');
          return;
   end;*/
   -- Если объект расположен в табличном пространстве ASSM, мы должны использовать
   -- этот вызов для получения информации о пространстве, иначе мы используем
   -- вызов FREE_BLOCKS для сегментов, управляемых пользователем
   if l_segment_space_mgmt = 'AUTO' then
     dbms_space.space_usage
     ( p_owner, p_segname, p_type, l_unformatted_blocks,
       l_unformatted_bytes, l_fs1_blocks, l_fs1_bytes,
       l_fs2_blocks, l_fs2_bytes, l_fs3_blocks, l_fs3_bytes,
       l_fs4_blocks, l_fs4_bytes, l_full_blocks, l_full_bytes, p_partition);

     p( 'Full Blocks (0% free)',         l_full_blocks );
     p( 'FS1 Blocks (0-25% free) ' ,  l_fs1_blocks );
     p( 'FS2 Blocks (25-50% free) ',  l_fs2_blocks );
     p( 'FS3 Blocks (50-75% free) ',  l_fs3_blocks );
     p( 'FS4 Blocks (75-100% free) ', l_fs4_blocks );
     p( 'Unformatted Blocks (100% free)',  l_unformatted_blocks );
  else
     dbms_space.free_blocks
     ( segment_owner     => p_owner,
       segment_name      => p_segname,
       segment_type      => p_type,
       freelist_group_id => 0,
       free_blks         => l_free_blks
     );
     p('Free Blocks ', l_free_blks );
  end if;
  -- А затем мы вызываем процедуру unused_space для получения остальной
  -- информации
  dbms_space.unused_space
  ( segment_owner     => p_owner,
    segment_name      => p_segname,
    segment_type      => p_type,
    partition_name    => p_partition,
    total_blocks      => l_total_blocks,
    total_bytes       => l_total_bytes,
    unused_blocks     => l_unused_blocks,
    unused_bytes      => l_unused_bytes,
    LAST_USED_EXTENT_FILE_ID => l_LastUsedExtFileId,
    LAST_USED_EXTENT_BLOCK_ID => l_LastUsedExtBlockId,
    LAST_USED_BLOCK => l_LAST_USED_BLOCK
  );

  p('Total Blocks ', l_total_blocks );
  p('Total Bytes ', l_total_bytes );
  --p('Total MBytes ', trunc(l_total_bytes/1024/1024) );
  p('Unused Blocks ', l_unused_blocks );
  p('Unused Bytes ', l_unused_bytes );
  p('Last Used Ext FileId ', l_LastUsedExtFileId );
  p('Last Used Ext BlockId ', l_LastUsedExtBlockId );
  p('Last Used Block ', l_LAST_USED_BLOCK );

  dbms_output.put_line(rpad('=', 56, '='));
end;
/

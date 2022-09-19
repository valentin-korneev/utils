
select * from v$sga;

select * from (select * from v$sgastat order by pool, bytes desc) where rownum <= 40;


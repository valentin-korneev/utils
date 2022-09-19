define extra_where="and status='ACTIVE' and username is not null and sid != (select sid from v$mystat where rownum=1) and module||'`' not like '%TAlerterThread%'"
define extra_order="last_call_et desc,"
@@Ses.sql

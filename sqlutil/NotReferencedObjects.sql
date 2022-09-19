------------------------------------------------------------------------------------------
-- Elic 05.06.2001 12:41 - creation
--
-- This script shows all user's objects that has no explicit references
------------------------------------------------------------------------------------------


select o.object_type, o.object_name
  from user_objects o
  where o.object_type in ('FUNCTION','PACKAGE','PROCEDURE','SEQUENCE','TABLE','VIEW')
    and not exists
    ( select null from dba_dependencies d
        where d.referenced_type = o.object_type
          and d.referenced_name = o.object_name
          and d.referenced_owner = user
          and not (o.object_type = 'PACKAGE' and d.type = 'PACKAGE BODY' and d.name = o.object_name)
    )
    and not exists
    ( select null from user_tab_privs p
        where p.owner = user
          and p.table_name = o.object_name
    )
    and not exists
    ( select null from adm_function_grant a
        where a.db_object_name = o.object_name
    )
  order by 1, 2
;

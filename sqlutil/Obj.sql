cle bre
col object_name for a30 tru
col owner       for a18 tru
col subobject_name for a14
col edition_name for a8
break on owner

select * from sys.dba_objects
  where object_name like upper('%&1%') escape '\'
  order by decode(owner, user, 1, 2), owner, object_name, object_type;

col object_name cle
col owner       cle
cle bre

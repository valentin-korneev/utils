set linesize 1000
cle bre
col object_name for a30 tru
col owner       for a18 tru
col subobject_name for a14
col edition_name for a8
break on owner

set hea off
set feed off
select 'Objects like "'||upper('%&1%')||'" in schema "'||sys_context('userenv', 'current_schema')||'" :'
  from dual;
set hea on
set feed on

select *
  from sys.user_objects o
  where o.object_name like upper('%&1%') escape '\'
  order by object_name, object_type
;

col object_name cle
col owner       cle
cle bre

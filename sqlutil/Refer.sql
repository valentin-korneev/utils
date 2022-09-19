REM     **********************************************************
REM     **              FILE DEPEND.SQL                         **
REM     **                                                      **
REM     **   DISPLAY ALL OBJECTS WHICH OBJECT &1 REFERENCES BY  **
REM     **                                                      **
REM     **********************************************************

prompt

col referenced_name new_v namevar noprint
col referenced_type new_v typevar noprint
set hea off
tti left  '===================================================================' skip -
          '== ' typevar ' "' namevar '" referenced by objects:'                 skip -
          '===================================================================' skip
break on referenced_name on referenced_type skip page on type

select distinct
    referenced_name,
    initcap(referenced_type) referenced_type,
    initcap(type) type,
    name
  from user_dependencies
  where upper(referenced_name) like upper('&1')
    and referenced_owner=user
  order by 1,2,3,4
;

tti off
set hea on
col referenced_name cle
col referenced_type cle
cle bre

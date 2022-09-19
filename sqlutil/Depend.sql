REM     **********************************************************
REM     **              FILE DEPEND.SQL                         **
REM     **                                                      **
REM     **    DISPLAY ALL OBJECTS WHICH OBJECT &1 DEPEND ON     **
REM     **                                                      **
REM     **********************************************************

prompt

col referenced_owner for a20
col name new_v namevar noprint
col type new_v typevar noprint
set hea off
tti left  '===================================================================' skip -
          '== ' typevar ' "' namevar '" depend on objects:'           skip -
          '===================================================================' skip
break on name on type skip page on referenced_owner skip 1 on referenced_type

select distinct
    name,
    initcap(type) type,
    referenced_owner,
    initcap(referenced_type) referenced_type,
    referenced_name
  from user_dependencies
  where upper(name)=upper('&1')
  order by 1,2,3,4,5
;

tti off
set hea on
col referenced_owner cle
col name cle
col type cle
cle bre

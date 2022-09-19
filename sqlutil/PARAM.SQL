col num   for 9990     hea '#'
col name  for a41 wor hea 'Название инициализационного параметра'
col value for a47 wor hea 'Значение параметра'
col display_value for a50 wor
col update_comment for a30

select *
/*    num,
    name,
    decode(type,1,'L',2,'C',3,'N',4,'I','?') "@",
    decode(isdefault,'TRUE','+','FALSE','-','?') "?",
    value*/
  from v$parameter 
  where name like '%&1%'
  order by name
;

col num cle
col name cle
col value cle

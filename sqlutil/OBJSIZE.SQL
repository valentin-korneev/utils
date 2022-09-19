select decode(type,
      'FUNCTION','Func',     'PROCEDURE','Proc',
      'TRIGGER','Trig',      'PACKAGE','Pack',
      'PACKAGE BODY','Body', initcap(substr(type,1,4))) type,
    substr(name,1,20) name,
    source_size, parsed_size, code_size, error_size
  from sys.dba_object_size
  where owner=user
  order by code_size desc;

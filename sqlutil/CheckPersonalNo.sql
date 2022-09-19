declare 
  fPersonalNo varchar2(20) := '&1';
begin
  if Refs.IsPersonalNoValid(fPersonalNo) then
    dbms_output.put_line(fPersonalNo||' - OK.');
  else
    for i in 0 .. 9 loop
      fPersonalNo := regexp_replace(fPersonalNo, '\d$', i);
      dbms_output.put_line(fPersonalNo||': '||case when Refs.IsPersonalNoValid(fPersonalNo) then '+' else '-' end);
    end loop;
  end if;
end;
/

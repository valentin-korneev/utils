declare
  fUNP int := '&1';
begin
  if Refs.IsUNPValid(fUNP) then
    dbms_output.put_line(fUNP||' - OK.');
  else
    if fUNP between 10**8 and 10**9-1 then
      for i in 0 .. 9 loop
        fUNP := trunc(fUNP, -1) + i;
        dbms_output.put_line(fUNP||': '||case when Refs.IsUNPValid(fUNP) then '+' else '-' end);
      end loop;
    else
     dbms_output.put_line(fUNP||': BAD');
    end if;
  end if;
end;
/

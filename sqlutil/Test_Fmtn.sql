declare
  n number;
begin
  for i in -20 .. 20-23*0 loop
    n := 999999*10**i;
    dbms_output.put_line('|'||to_char(i, '99')||'|'||rpad(n, 30)
               || '|' || RCore.Fmtn(n, 12, Fmt=>RCore.fGroupped)
               || '|' || RCore.Fmtn(n, 12) 
               || '|' || RCore.Fmtn(n, 8)
               || '|' || RCore.Fmtn(n, 5)
               || '|' || RCore.Fmtn(n, 4)
              || '||' || RCore.Fmtn(-n, 12, Fmt=>RCore.fGroupped)
               || '|' || RCore.Fmtn(-n, 12) 
               || '|' || RCore.Fmtn(-n, 8)
               || '|' || RCore.Fmtn(-n, 5)
               || '|' || RCore.Fmtn(-n, 4)
              || '||' || RCore.Fmtn(n, 12, Fmt=>'0.00')
               || '|' || RCore.Fmtn(n, 12, Fmt=>'0.00', fill=>'0')
               || '|');
  end loop;
end;
/




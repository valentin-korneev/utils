set feed off timing off




declare
  n number;
  t timestamp := SYSTIMESTAMP;
  c int;
begin
  for j in 1 .. 2 loop
    c := Util.TInts(974, 840)(j);
    dbms_output.put_line(RCore.FmtCurr(c)||':');
    for i in -12 .. 20-23*0 loop
      n := 999999*10**i;
      dbms_output.put_line('|'||to_char(i, '99')||'|'||rpad(n, 30)
                 || '|' || RCore.FmtAmount(n, c, 12, Fmt=>RCore.fSimple)
                 || '|' || RCore.FmtAmount(n, c, 12) 
                 || '|' || RCore.FmtAmount(n, c, 8)
                 || '|' || RCore.FmtAmount(n, c, 5)
                 || '|' || RCore.FmtAmount(n, c, 4)
                || '||' || RCore.FmtAmount(-n, c, 12, Fmt=>RCore.fSimple)
                 || '|' || RCore.FmtAmount(-n, c, 12) 
                 || '|' || RCore.FmtAmount(-n, c, 8)
                 || '|' || RCore.FmtAmount(-n, c, 5)
                 || '|' || RCore.FmtAmount(-n, c, 4)
                 || '||' || RCore.FmtAmount(n, c));
    end loop;
  end loop;
  dbms_output.put_line((SYSTIMESTAMP - t));
end;
/



declare
  n number;
  t timestamp := SYSTIMESTAMP;
begin
  for i in -20 .. 20-23*0 loop
    n := 999999*10**i;
    dbms_output.put_line('|'||to_char(i, '99')||'|'||rpad(n, 30)
               || '|' || RCore.Fmtn(n, 12, Fmt=>RCore.fGroupped)
               || '|' || RCore.Fmtn(n, 12, Fmt=>'D00') 
               || '|' || RCore.Fmtn(n, 8)
               || '|' || RCore.Fmtn(n, 5)
               || '|' || RCore.Fmtn(n, 4)
              || '||' || RCore.Fmtn(-n, 12, Fmt=>RCore.fGroupped)
               || '|' || RCore.Fmtn(-n, 12) 
               || '|' || RCore.Fmtn(-n, 8)
               || '|' || RCore.Fmtn(-n, 5)
               || '|' || RCore.Fmtn(-n, 4)
              || '||' || RCore.Fmtn(n)
               );
  end loop;
  dbms_output.put_line((SYSTIMESTAMP - t));
end;
/



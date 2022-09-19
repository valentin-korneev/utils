prompt

set serveroutput on size unlimited
set feed off

declare
  procedure Log(Msg varchar2)
  is
  begin
    dbms_output.put_line(/*replace(*/Msg/*,' ',chr(7))*/);
  end Log;
  procedure OutRep
  is
    fBufLen int;
    fStatus int;
    fRows RCore.StrArray;
    fPageNo int := 1;
    fRowNo int := 0;
  begin
    RCore.ReaderInitialize(:RCoreTestPipe);
    loop
      fBufLen := 1;
      fStatus := RCore.ReaderGetRows(fBufLen, fRows);
      if fStatus in (0, 2) and fBufLen > 0 then
        if fRows(1) = chr(12) then
          fRowNo := 0;
          fPageNo := fPageNo + 1;
          Log(Util.Format('%2.2d:======Page%2.2d%s', fPageNo, fPageNo, rpad('=', 130-8,'=')));
        else
          fRowNo := fRowNo + 1;
          Log(Util.Format('%2.2d:%2.2d |%s', fPageNo, fRowNo, fRows(1)));
        end if;
      end if;
      exit when fStatus <> 0;
    end loop;
    if fStatus <> 2 then
      Log('!!!!!!!!!!!!!!!!!!!  Unexpected end of report  !!!!!!!!!!!!!!!!!11');
    end if;
  end;
begin
  RCore.WriterInitialize(:RCoreTestPipe);
  RCore.CloseReport;
  OutRep;
end;
/

set feed on

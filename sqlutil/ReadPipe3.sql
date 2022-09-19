set serveroutput on size unlimited


declare
  fPipe varchar2(255) := '&1';
  fCnt int := 0;
  fMaxCnt int := &2;
  n number;
  s varchar2(32000);
  d date;
  rid rowid;
  r raw(255);

  procedure Log(Msg varchar2, Force boolean := false)
  is
  begin
    if Force then
      dbms_output.put_line(to_char(fCnt, 'fm0000')||')'||Msg);
    end if;
  end Log;

begin
  Log('-=> Pipe "'||fPipe||'":', true);
  while fCnt < fMaxCnt and dbms_pipe.receive_message(fPipe,0) = 0 loop
    fCnt := fCnt + 1;
    while dbms_pipe.next_item_type <> 0 loop
      if    dbms_pipe.next_item_type = 9 then
        dbms_pipe.unpack_message(s);
        Log('...S='||s);
      elsif dbms_pipe.next_item_type = 6 then
        dbms_pipe.unpack_message(n);
        Log('...N='||n);
      elsif dbms_pipe.next_item_type = 11 then
        dbms_pipe.unpack_message(rid);
        Log('RowId='||rid);
      elsif dbms_pipe.next_item_type = 12 then
        dbms_pipe.unpack_message(d);
        Log('...D='||to_char(d,'dd.mm.yyyy hh24:mi:ss'));
      elsif dbms_pipe.next_item_type = 23 then
        dbms_pipe.unpack_message(r);
        Log('...R='||r);
      else
        Log('...?'||dbms_pipe.next_item_type);
        exit;
      end if;
    end loop;
  end loop;
  Log('<=- End of Pipe "'||fPipe||'".', true);
end;
/

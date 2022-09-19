set serveroutput on size unlimited


declare
  fPipe varchar2(255) := '&1';
  fCnt int := 0;
  n number;
  s varchar2(32000);
  d date;
  rid rowid;
  r raw(32000);

  procedure Log(Msg varchar2)
  is
  begin
    dbms_output.put_line(fCnt||')'||Msg);
  end Log;

begin
  Log('-=> Pipe "'||fPipe||'":');
  while dbms_pipe.receive_message(fPipe,0) = 0 loop
    fCnt := fCnt + 1;
    while dbms_pipe.next_item_type <> 0 loop
      if    dbms_pipe.next_item_type = 9 then
        dbms_pipe.unpack_message(s);
        Log('...S='||substr(s, 1, 255));
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
  Log('<=- End of Pipe "'||fPipe||'".');
end;
/

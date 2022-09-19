var RCoreTestPipe varchar2(100)

set feed off

begin
  RCore.WriterInitialize(:RCoreTestPipe);
end;
/
set feed on


-- В цикле есть логическаяя ошибка, которая может очень "больно" выстрелить
procedure InitSendReportTo
is
  Pn2$ constant varchar2(30) := 'SendReportTo';
  fPackageVars tp_varchar2_100_table;
  i int;
begin
  if gSendReportToPkgs is null then
    select object_name bulk collect into gSendReportToPkgs
      from user_procedures
      where procedure_name = upper(Pn2$)
      order by object_name desc;
  end if;
  --
  i := gSendReportToPkgs.first;
  while i is not null loop
    begin
      execute immediate 'begin "'||gSendReportToPkgs(i)||'".'||Pn2$||'(:l); end;'
        using out fPackageVars;
      -- using fPackageVars ...
      i := gSendReportToPkgs.next(i);
    exception
      when others then
        LogWork.NotifyException(Pn1$, Pn2$, gSendReportToPkgs(i)
        , aResetPackageStateIfNeeded=>true);
    end;
  end loop;
exception
  when others then
    LogWork.NotifyException(Pn1$, Pn2$);
    raise;
end InitSendReportTo;



-- Как просто ускорить процедуру в ~3 раза?
procedure TStrArr2Clob(aStrArr TStrArr, aClob in out nocopy clob)
is
begin
  aClob := null;
  for i in 1 .. aStrArr.count loop
    aClob := aClob || aStrArr(i) || chr(13) || chr(10);
  end loop;
end TStrArr2Clob;
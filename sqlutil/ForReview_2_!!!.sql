-- � ����� ���� ����������� ������, ������� ����� ����� "������" ����������
create or replace type tp_varchar2_100_table  is table of varchar2(100);

procedure InitSendReportTo
is
  Pn2$ constant varchar2(30) := 'SendReportTo';

  fSendReportToPkgs tp_varchar2_100_table;
  fPackageVars      tp_varchar2_100_table;
  i int;
begin
  if fSendReportToPkgs is null then
    select object_name bulk collect into fSendReportToPkgs
      from user_procedures
      where procedure_name = upper(Pn2$)
      order by object_name desc;
  end if;
  --
  i := fSendReportToPkgs.first;
  while i is not null loop
    begin
      execute immediate 'begin "'||fSendReportToPkgs(i)||'".'||Pn2$||'(:l); end;'
        using out fPackageVars;
      i := fSendReportToPkgs.next(i);
    exception
      when others then
        dbms_output.put_line(Pn2$ || ':' || fSendReportToPkgs(i));
    end;
  end loop;
exception
  when others then
    dbms_output.put_line(Pn2$ || ':' || sqlerrm);
    raise;
end InitSendReportTo;


-- ��� ������ �������� ��������� � ~3 ����?
type TStrArr is table of varchar2(32767) index by pls_integer;

procedure TStrArr2Clob(aStrArr TStrArr, aClob in out nocopy clob)
is
begin
  aClob := null;
  for i in 1 .. aStrArr.count loop
    aClob := aClob || aStrArr(i) || chr(13) || chr(10);
  end loop;
end TStrArr2Clob;


-- �������� ������ ��������� ������� ������ � ���������� �������� � ���
create table test_string (name varchar2(100));

insert into test_string values('���� ������');
insert into test_string values('���� ����� ���� ������');
insert into test_string values('������� ��� ����������� 25 ���');
insert into test_string values('   ');

commit;

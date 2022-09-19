
prompt create or replace package body UtilSql

create or replace package body UtilSql
as

Pn1$ constant varchar2(30) := 'UtilSql';

---------
procedure OutLines(S clob, aMaxLines int := 1000)
is
  cLineSize constant int := 150;
  fLines     Util.TStrs   := Util.SubNames2TStrs(dbms_lob.substr(S), chr(10));
  fCnt       int          := least(fLines.count, aMaxLines);
  fLineNoFmt varchar2(99) := 'fm' || rpad('0', length(fCnt), '0');
  fLine      varchar2(32767);
  fLinePart  varchar2(1000);
begin
  for i in  1 .. fCnt loop
    fLine := fLines(i);
    for j in 1 .. 30 loop
      exit when fLine is null and j > 1;
      fLinePart := regexp_substr(fLine, '^.{1,150}([-[:space:],;+*/=<>]+|$)');
      dbms_output.put_line
      (   '|' || case when i = 1 and j = 1 then to_char(systimestamp, 'hh24:mi:ss.ff3') else rpad(' ', 12) end
       || '|' || case when fCnt > 1 then to_char(i, fLineNoFmt) || '|' end
              || fLinePart
      );
      fLine := substr(fLine, length(fLinePart) + 1);
    end loop;
  end loop;
  if fCnt > 1 then
    dbms_output.put_line(case when fLines.count > fCnt then '...' else '.' end);
  end if;
end OutLines;

---------
procedure ShowErrors(aType varchar2, aOwner varchar2, aName varchar2)
is
  fOwner varchar2(30) := nvl(aOwner, user);
begin
  OutLines('Errors for ' || aType || ' ' || fOwner || '.' || aName || ':');
  for cErr in
  ( select * from all_errors
      where type = aType
        and owner = aOwner
        and name = aName
      order by sequence
  ) loop
    OutLines('| ' || cErr.line || '/' || cErr.position || ': ' || cErr.text);
  end loop;
  OutLines('|.');
end ShowErrors;

---------
procedure Serialize
( aSrc          varchar2
, aSubsrc       varchar2
, aStarting     boolean
)
is
  Pn2$ constant varchar2(30) := 'Serialize';
  fLockHandle varchar2(128);
begin
  if aSrc is not null or aSubsrc is not null then
    fLockHandle := UtilLock.GetLockHandle(Pn1$, Pn2$);
    if aStarting then
      LogWork.Notify(aSrc, aSubsrc, 'Waiting to start ...');
      UtilLock.Request(fLockHandle, aReleaseOnCommit=>false);
    else
      LogWork.Notify(aSrc, aSubsrc, 'Finished.');
      UtilLock.Release(fLockHandle);
    end if;
  end if;
exception
  when others then
    LogWork.NotifyException(aSrc, aSubsrc, Pn2$);
    raise;
end Serialize;

---------
function Quotes (aValue clob, aNeedComma boolean := true) return clob
is
begin
  if aValue is not null then
    return q'{q'^}' || aValue || q'{^'}' || case when aNeedComma then ',' end;
  else
    return 'null' || case when aNeedComma then ',' end;
  end if;
end Quotes;

---------
function Quotes(aValue Util.TStrs, aNeedComma boolean := true) return clob
is
  fClob clob := 'Util.TStrs(';
begin
  if aValue is not null then
    for i in 1..aValue.count loop
      fClob := fClob || Quotes(aValue(i), case when i = aValue.count then false else true end);
    end loop;
    return fClob || ')' || case when aNeedComma then ',' end ;
  else
    return 'null' || case when aNeedComma then ',' end;
  end if;
end Quotes;

---------
function Quotes(aValue Util.TInts, aNeedComma boolean := true) return clob
is
  fClob clob := 'Util.TInts(';
begin
  if aValue is not null then
    for i in 1..aValue.count loop
      fClob := fClob || aValue(i) || case when i <> aValue.count then ',' end;
    end loop;
    return fClob || ')' || case when aNeedComma then ',' end;
  else
    return 'null' || case when aNeedComma then ',' end;
  end if;
end Quotes;

---------
function Execute
( aSrc             varchar2
, aSubsrc          varchar2
, aStatement       clob
, aParams          Util.TStrs := null
, aIgnoreErrors    Util.TInts := null
, aMaxLines        int        := 1000
, aSerialize       boolean    := false
, aMacros          Util.TStrs := null
, aAsJob           boolean    := false
, aJobStartDate    date       := null
, aBinds           Util.TStrs := null
, aIsQuery         boolean    := false
, aQueryResult out Util.TStrs
, aIterateDmlTill0RowsAffected boolean := false
, aAutonomousTransaction       boolean := false
) return boolean
is
  --
  function Exec return boolean
  is
    fStatement       clob := aStatement;
    fMaskedStatement clob;
    cCreateOrReplace varchar2(200) :=
      '^\s*create\s+(or\s+replace\s+)?(procedure|function|trigger|package(\s+body)?|type(\s+body)?)\s+(([a-z]+[a-z_$#0-9]+)\s*\.\s*)?([a-z]+[a-z_$#0-9]+).*$';
    fStatementStart  varchar2(100);
    fType            varchar2(100);
    fOwner           varchar2(100);
    fName            varchar2(100);
    fHasBinds        boolean := aBinds is not null and aBinds.count > 0;
    fAffectedRows    int;
    fQueryResult     tp_varchar2_4000_table;
    fStarted         timestamp with time zone := systimestamp;
    --
    procedure Out(aErr boolean := true)
    is
    begin
      if xor(aMaxLines > 0, aErr) then
        OutLines(fMaskedStatement, abs(aMaxLines));
      end if;
    end Out;
    --
  begin
    if aParams is not null then
      Util.Format(fStatement, aParams);
    end if;
    if aMacros is not null then
      Util.ReplaceMacros(fStatement, aMacros);
    end if;
    if aAsJob then
      Execute
      ( aSrc
      , aSubsrc
      , Util.TStrs(fStatement)
      , aIgnoreErrors=>aIgnoreErrors
      , aSerialize=>aSerialize
      , aAsJob=>true
      , aJobStartDate => aJobStartDate
      , aIterateDmlTill0RowsAffected=>aIterateDmlTill0RowsAffected
      );
      return null;
    end if;
    if fHasBinds then
      fStatement := 'declare b# tp_varchar2_4000_table := :b; begin execute immediate '
                 || Quotes(fStatement, aNeedComma=>false) || ' '
                 || case when aIsQuery then 'bulk collect into :r ' end
                 || 'using '
                 ;
      for i in 1 .. aBinds.count loop
        fStatement := fStatement || ('b#(' || i || '),');
      end loop;
      fStatement := rtrim(fStatement, ',') || '; :cnt:=sql%rowcount; end;';
    end if;
    if aSerialize then
      Serialize(aSrc, aSubsrc, true);
    end if;
    fMaskedStatement := regexp_replace(fStatement, '(identified\s+by\s+)(\w+|"[^"]+")', '\1***', 1, 0, 'i');
    if (aSrc is not null or aSubsrc is not null) and not aIsQuery then
      LogWork.Notify(aSrc, aSubsrc, fMaskedStatement);
    end if;
    fStatementStart := upper(regexp_replace(dbms_lob.substr(fStatement, 100), '^\s+'));
    fType  := regexp_substr (fStatementStart, cCreateOrReplace,       1, 1, 'in', 2);
    fOwner := regexp_substr (fStatementStart, cCreateOrReplace,       1, 1, 'in', 6);
    fName  := regexp_substr (fStatementStart, cCreateOrReplace,       1, 1, 'in', 7);
    Out(aErr=>false);
    if length(fStatement) <= 32767 and fType in ('PACKAGE', 'PACKAGE BODY', 'PROCEDURE', 'FUNCTION') then
      Util.CheckErr(fHasBinds, 'Cannot specify binds in DDL');
      dbms_ddl.create_wrapped(fStatement);
    else
      loop
        fAffectedRows := 0;
        if fHasBinds then
          if aIsQuery then
            execute immediate fStatement using Util.TStrs2TpVarchar4000Table(aBinds), out fQueryResult, out fAffectedRows;
          else
            execute immediate fStatement using Util.TStrs2TpVarchar4000Table(aBinds), out fAffectedRows;
          end if;
        else
          if aIsQuery then
            execute immediate fStatement bulk collect into fQueryResult;
          else
            execute immediate fStatement;
          end if;
          fAffectedRows := sql%rowcount;
        end if;
        if aMaxLines > 0 and (fAffectedRows > 0 or systimestamp - fStarted > interval '0.1' second) then
          declare
            fMsg varchar2(200) :=
              Util.Format
              ( case
                  when aIsQuery                                                      then 'Selected %d row(s)'
                  when regexp_like(fStatementStart, '^(<<|DECLARE|BEGIN)')           then 'Executed'
                  when regexp_like(fStatementStart, '^(INSERT|UPDATE|DELETE|MERGE)') then 'Affected %d row(s)'
                  else                                                                    'Completed'
                end
              , fAffectedRows
              )
              || Util.Format(' in %i', systimestamp - fStarted)
              ;
          begin
            OutLines(fMsg);
            if aSrc is not null or aSubsrc is not null then
              LogWork.Notify(aSrc, aSubsrc, '- ' || fMsg);
            end if;
          end;
        end if;
        exit when aIsQuery or not aIterateDmlTill0RowsAffected or fAffectedRows = 0;
        commit;
      end loop;
      aQueryResult := Util.TpVarchar4000Table2TStrs(fQueryResult);
    end if;
    if aSerialize then
      Serialize(aSrc, aSubsrc, false);
    end if;
    return true;
  exception
    when Util.eSuccessWithCompilationError then
      Out;
      if aSrc is not null or aSubsrc is not null then
        LogWork.NotifyException(aSrc, aSubsrc);
      end if;
      ShowErrors(fType, fOwner, fName);
      raise;
    when others then
      if aIgnoreErrors is null or sqlcode not member of aIgnoreErrors then
        Out;
        if aSrc is not null or aSubsrc is not null then
          if aIsQuery then
            LogWork.Notify(aSrc, aSubsrc, fMaskedStatement);
          end if;
          LogWork.NotifyException(aSrc, aSubsrc, Util.TStrs2SubNames(aBinds));
        else
          if fHasBinds then
            OutLines('Binds: ' || Util.TStrs2SubNames(aBinds));
          end if;
          LogWork.ResetPackageStateIfNeeded(Pn1$, 'Execute');
        end if;
        raise;
      elsif aIgnoreErrors is not null and 0 member of aIgnoreErrors then -- Output ignored statement
        Out;
      end if;
      if aSrc is not null or aSubsrc is not null then
        LogWork.NotifyException(aSrc, aSubsrc);
      elsif aMaxLines > 0 then
        OutLines(sqlerrm);
      end if;
      return false;
  end Exec;
  --
  function ExecAuto return boolean
  is
    pragma autonomous_transaction;
    fResult boolean;
  begin
    fResult := Exec();
    commit;
    return fResult;
  end ExecAuto;
begin
  if aAutonomousTransaction then
    return ExecAuto;
  else
    return Exec;
  end if;
end Execute;

---------
function Execute
( aSrc          varchar2
, aSubsrc       varchar2
, aStatement    clob
, aParams       Util.TStrs := null
, aIgnoreErrors Util.TInts := null
, aMaxLines     int        := 1000
, aSerialize    boolean    := false
, aMacros       Util.TStrs := null
, aAsJob        boolean    := false
, aJobStartDate date       := null
, aBinds        Util.TStrs := null
, aAutonomousTransaction       boolean := false
) return boolean
is
  fQueryResult Util.TStrs;
begin
  return Execute
  ( aSrc
  , aSubsrc
  , aStatement
  , aParams
  , aIgnoreErrors
  , aMaxLines
  , aSerialize
  , aMacros
  , aAsJob
  , aJobStartDate
  , aBinds
  , aQueryResult=>fQueryResult
  , aAutonomousTransaction=>aAutonomousTransaction
  );
end Execute;


---------
procedure Execute
( aSrc          varchar2
, aSubsrc       varchar2
, aStatement    clob
, aParams       Util.TStrs := null
, aIgnoreErrors Util.TInts := null
, aMaxLines     int        := 1000
, aSerialize    boolean    := false
, aMacros       Util.TStrs := null
, aAsJob        boolean    := false
, aJobStartDate date       := null
, aBinds        Util.TStrs := null
, aIterateDmlTill0RowsAffected boolean := false
, aAutonomousTransaction       boolean := false
)
is
  fResult boolean;
  fQueryResult Util.TStrs;
begin
  fResult := Execute
  ( aSrc
  , aSubsrc
  , aStatement
  , aParams
  , aIgnoreErrors
  , aMaxLines
  , aSerialize
  , aMacros
  , aAsJob
  , aJobStartDate
  , aBinds
  , aQueryResult=>fQueryResult
  , aIterateDmlTill0RowsAffected=>aIterateDmlTill0RowsAffected
  , aAutonomousTransaction=>aAutonomousTransaction
  );
end Execute;

---------
function Execute
( aStatement    clob
, aParams       Util.TStrs := null
, aIgnoreErrors Util.TInts := null
, aMaxLines     int        := 1000
, aMacros       Util.TStrs := null
, aBinds        Util.TStrs := null
, aAutonomousTransaction       boolean := false
) return boolean
is
begin
  return Execute('', '', aStatement, aParams, aIgnoreErrors, aMaxLines, aMacros=>aMacros, aBinds=>aBinds, aAutonomousTransaction=>aAutonomousTransaction);
end Execute;

---------
procedure Execute
( aStatement    clob
, aParams       Util.TStrs := null
, aIgnoreErrors Util.TInts := null
, aMaxLines     int        := 1000
, aMacros       Util.TStrs := null
, aBinds        Util.TStrs := null
, aAutonomousTransaction       boolean := false
)
is
begin
  Execute('', '', aStatement, aParams, aIgnoreErrors, aMaxLines, aMacros=>aMacros, aBinds=>aBinds, aAutonomousTransaction=>aAutonomousTransaction);
end Execute;

---------
procedure Execute
( aSrc          varchar2
, aSubsrc       varchar2
, aStatements   Util.TStrs
, aIgnoreErrors Util.TInts := null
, aMaxLines     int        := 1000
, aMacros       Util.TStrs := null
, aSerialize    boolean    := false
, aAsJob        boolean    := false
, aJobStartDate date       := null
, aIterateDmlTill0RowsAffected boolean := false
)
is
  Pn2$ constant varchar2(30) := 'Execute';
  fJobStr varchar2(4000);
begin
  if aAsJob then
   fJobStr :=
        Pn1$ || '.' || Pn2$ || '('
     || 'aSrc=>'          || Quotes(aSrc)
     || 'aSubsrc=>'       || Quotes(aSubsrc)
     || 'aStatements=>'   || Quotes(aStatements)
     || 'aMacros=>'       || Quotes(aMacros)
     || 'aIgnoreErrors=>' || Quotes(aIgnoreErrors)
     || 'aSerialize=>'    || case when aSerialize then 'true' else 'false' end
     || ',aIterateDmlTill0RowsAffected=>' || case when aIterateDmlTill0RowsAffected then 'true' else 'false' end
     || ');';
    LogWork.Notify(Pn1$, Pn2$, 'Adding job:'||chr(10)||fJobStr);
    RunJob(aSubsrc, fJobStr, aJobStartDate => aJobStartDate);
    return;
  end if;
  if aSerialize then
    Serialize(aSrc, aSubsrc, true);
  end if;
  if aStatements is not null then
    for i in 1 .. aStatements.count loop
      Execute(aSrc, aSubsrc, aStatements(i), aIgnoreErrors=>aIgnoreErrors, aMaxLines=>aMaxLines, aMacros=>aMacros, aIterateDmlTill0RowsAffected=>aIterateDmlTill0RowsAffected);
    end loop;
  end if;
  if aSerialize then
    Serialize(aSrc, aSubsrc, false);
  end if;
end Execute;

---------
procedure Execute
( aStatements   Util.TStrs
, aIgnoreErrors Util.TInts := null
, aMaxLines     int        := 1000
, aMacros       Util.TStrs := null
)
is
begin
  Execute('', '', aStatements, aIgnoreErrors, aMaxLines, aMacros=>aMacros);
end Execute;

---------
procedure ParseQuery
( aQuery        varchar2
, aParams       Util.TStrs := null
, aMaxLines     int        := -100
, aMacros       Util.TStrs := null
)
is
  fStatement varchar2(32767) := aQuery;
  fBinds Util.TBoolArrByS100;
  fBind varchar2(100);
  eBindDoesNotExist exception;
  pragma exception_init(eBindDoesNotExist, -1006);
begin
  if aParams is not null then
    Util.Format(fStatement, aParams);
  end if;
  if aMacros is not null then
    Util.ReplaceMacros(fStatement, aMacros);
  end if;
  fStatement := 'declare c sys_refcursor; s varchar2(1); begin execute immediate q''@begin return; open :c for '
                || fStatement ||'; end;@'' using in out c {binds}; end;';
  for i in 2 .. 30 loop
    fBind := regexp_substr(fStatement, ':[[:alnum:]_#$]+', 1, i);
    exit when fBind is null;
    if not fBinds.exists(fBind) then
      fBinds(fBind) := null;
    end if;
  end loop;
  for i in reverse 0 .. fBinds.count loop
    exit when Execute
              ( fStatement
              , aMacros=>Util.TStrs('{binds}', rpad(',s', i*2, ',s'))
              , aIgnoreErrors=>case when i > 0 then Util.Tints(-1006) end
              , aMaxLines=>aMaxLines
              );
  end loop;
end ParseQuery;

---------
function ExecuteQuery
( aSrc          varchar2
, aSubsrc       varchar2
, aQuery        varchar2
, aParams       Util.TStrs := null
, aMacros       Util.TStrs := null
, aBinds        Util.TStrs := null
, aExactFetch   boolean    := true
) return Util.TStrs
is
  fResult boolean;
  fQueryResult Util.TStrs;
begin
  fResult := Execute
  ( aSrc
  , aSubsrc
  , aQuery
  , aParams
  , aMaxLines=>-100
  , aMacros=>aMacros
  , aBinds=>aBinds
  , aIsQuery=>true
  , aQueryResult=>fQueryResult
  );
  if aExactFetch then
    case nvl(fQueryResult.count, 0)
      when 0 then raise no_data_found;
      when 1 then null;
             else raise too_many_rows;
    end case;
  end if;
  return fQueryResult;
end ExecuteQuery;

---------
function ExecuteQuery
( aQuery        varchar2
, aParams       Util.TStrs := null
, aMacros       Util.TStrs := null
, aBinds        Util.TStrs := null
, aExactFetch   boolean    := true
) return Util.TStrs
is
begin
  return ExecuteQuery('', '', aQuery, aParams, aMacros, aBinds, aExactFetch);
end ExecuteQuery;




---------
procedure DropDependentTypes(aType varchar2)
is
begin
  for cTyp in
  ( select name from user_dependencies
      where referenced_name = upper(aType)
       and 'TYPE' = all (type, referenced_type)
       and referenced_owner = user
  ) loop
    DropDependentTypes(cTyp.name);
    Execute('drop type "%s"', Util.TStrs(cTyp.name), aIgnoreErrors=>Util.TInts(-4043));
  end loop;
end DropDependentTypes;


---------
procedure ExecuteAsJob
( aSrc          varchar2
, aSubsrc       varchar2
, aStatement    varchar2
, aJobLabel     varchar2 := null
, aJobStartDate date     := null
)
is
  fJob int;
  fJobLabel varchar2(100)   := case when aJobLabel is not null then '<<'||aJobLabel||'>>' end;
  fJobBody  varchar2(32767) := case when aStatement like '%;' then aStatement else 'execute immediate '||Quotes(aStatement, aNeedComma=>false) || ';' end;
  --
  procedure Out(aAction varchar2)
  is
    fMsg varchar2(32767) := 'Job ' || aAction || ': ' || coalesce(fJobLabel, chr(10) || aStatement);
  begin
    OutLines(fMsg);
    if aSrc is not null or aSubsrc is not null then
      LogWork.Notify(aSrc, aSubsrc, fMsg);
    end if;
  end Out;
  --
begin
  for cJob in (select * from user_jobs where what like nvl(fJobLabel, fJobBody) || '%') loop
    dbms_job.broken(cJob.job, false, nvl(aJobStartDate, sysdate));
    if cJob.what <> fJobLabel || fJobBody then
      dbms_job.what(cJob.job, fJobLabel || fJobBody);
      Out('updated');
      return;
    end if;
    Out('is up to date');
    return;
  end loop;
  dbms_job.submit(fJob, fJobLabel || fJobBody, next_date => nvl(aJobStartDate, sysdate));
  Out('added');
end ExecuteAsJob;

---------
procedure RunJob(aJobLabel varchar2, aJobBody varchar2, aJobStartDate date := null)
is
begin
  ExecuteAsJob('', '', aJobBody, aJobLabel, aJobStartDate);
end RunJob;

---------
procedure ActivateJob
( aExecProc               varchar2
, aPeriod                 varchar2 := 'sysdate+1'
, aAutonomousTransaction  boolean  := true
, aSilently               boolean  := false  
)
is
  Pn2$ constant varchar2(30) := 'ActivateJob';
  --
  procedure UpdJob
  is
    fJob int;
  begin
    for cJob in
    ( select job, broken, next_date, interval
        from user_jobs
        where what = aExecProc
        for update
    ) loop
      if not aSilently then 
        LogWork.NotifyFmt(Pn1$, Pn2$, '- found job #%d', cJob.job);
      end if;
      if cJob.broken = 'Y' then
        if cJob.interval <> aPeriod then
          LogWork.NotifyFmt(Pn1$, Pn2$, '- %s: set interval = %s', aExecProc, aPeriod);
          dbms_job.change(cJob.job, aExecProc, cJob.next_date, aPeriod);
        end if;
        dbms_job.broken(cJob.job, false, sysdate);
        if not aSilently then 
          LogWork.Notify(Pn1$, Pn2$, '- wake up');
        end if;
      else
        if not regexp_like(aExecProc, '\WBROKEN\W', 'i') and cJob.next_date > sysdate + interval '5' second then
          -- задание не использует broken и запустится нескоро
          dbms_job.next_date(cJob.job, sysdate);
          LogWork.NotifyFmt(Pn1$, Pn2$, '- %s: forced to start now', aExecProc);
        else
          if not aSilently then 
            LogWork.NotifyFmt(Pn1$, Pn2$, '- next start %s', to_char(cJob.next_date, 'dd.mm.yyyy hh24:mi:ss'));
          end if;
        end if;
      end if;
      return;
    end loop;

    select min(job) into fJob
      from
      ( select column_value as job from table(Util.Pivot(9999))
        minus
        select job from user_jobs
      );
    if fJob is not null then
      dbms_job.isubmit(fJob, aExecProc, sysdate, aPeriod);
    else
      dbms_job.submit (fJob, aExecProc, sysdate, aPeriod);
    end if;
    LogWork.NotifyFmt(Pn1$, Pn2$, '- %s: submitted job %d', aExecProc, fJob);
  end UpdJob;
  --
  procedure UpdJobAuto
  is
    pragma autonomous_transaction;
  begin
    UpdJob;
    commit;
  end UpdJobAuto;
begin
  if not aSilently then 
    LogWork.NotifyFmt(Pn1$, Pn2$, '-=> %s, autonomously=%s', aExecProc, Util.BOOl(aAutonomousTransaction));
  end if;
  if aAutonomousTransaction then
    UpdJobAuto;
  else
    UpdJob;
  end if;
end ActivateJob;

-- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

procedure UpperValue(aData in out nocopy Util.TStrs)
is
begin
  if aData is not null and aData.count > 0 then
    for i in aData.first .. aData.last loop
      if aData.exists(i) then
        aData(i) := upper(aData(i));
      end if;
    end loop;
  end if;
end UpperValue;

---------
function GetProcedures
( aProcName           varchar2
, aAllowOrdinality    boolean  := false
, aDefaultOrder       int      := null
, aExcludedPackagesRE varchar2 := null
) return Util.TStrs
is
  fProcs Util.TStrs;
  fAllowOrdinality varchar2(1) := Util.BOOL(aAllowOrdinality);
begin
  select '"'||object_name||'"."'||procedure_name||'"'
    bulk collect into fProcs
    from user_procedures
    where regexp_like(procedure_name, '^' || aProcName || case when fAllowOrdinality = Util.YES then '\d*' end || '$', 'i')
      and (aExcludedPackagesRE is null or not regexp_like(object_name, aExcludedPackagesRE, 'i'))
    order by nvl(to_number(regexp_substr(procedure_name, '\d+$')), aDefaultOrder), procedure_name
  ;
  return fProcs;
end GetProcedures;

---------
function GetColumns
( aTable            varchar2
, aIncludedColumns  Util.TStrs := null
, aExcludedColumns  Util.TStrs := null
) return Util.TStrs
is
  fIncludedColumns Util.TStrs;
  fExcludedColumns Util.TStrs;
  fColumns Util.TStrs;
begin
  select column_name bulk collect into fColumns
    from user_tab_cols
      where table_name      in ( upper(aTable)
                               , ( select s.table_name
                                     from user_synonyms s
                                     where s.synonym_name = upper(aTable)
                                       and s.table_owner = sys_context('userenv', 'current_schema')/*!! Administration.GetSchemaOwner() - unnecessary dependency !!*/
                                 )
                               )
        and hidden_column   = 'NO'
        and virtual_column  = 'NO'
      order by column_id;
  fIncludedColumns := coalesce(aIncludedColumns, fColumns);
  fExcludedColumns := coalesce(aExcludedColumns, Util.TStrs());
  UpperValue(fIncludedColumns);
  UpperValue(fExcludedColumns);
  return fColumns multiset intersect fIncludedColumns multiset except fExcludedColumns;
end GetColumns;

---------
function Trg_GetColumns
( aTable            varchar2
, aIncludedColumns  Util.TStrs := null
, aExcludedColumns  Util.TStrs := null
, aMode           int := 1
) return varchar2
is
  fResult varchar2(32767);
  fColumns Util.TStrs := GetColumns(aTable, aIncludedColumns, aExcludedColumns);
begin
  for i in 1 .. fColumns.count loop
    fResult :=
        fResult
      ||case when fResult is not null then
            chr(10)
          ||case aMode
              when 1 then 'and '
              when 2 then ', '
            end
        else
          case aMode
            when 1 then '    '
            when 2 then '  '
          end
        end
      ||case aMode
          when 1 then replace('((:new.@ = :old.@) or (:new.@ is null and :old.@ is null))', '@', lower(fColumns(i)))
          when 2 then lower(fColumns(i))
        end
      ;
  end loop;

  return fResult;
end Trg_GetColumns;

---------
function Trg_GetColumnsUnchanged
( aTable            varchar2
, aIncludedColumns  Util.TStrs := null
, aExcludedColumns  Util.TStrs := null
) return varchar2
is
begin
  return Trg_GetColumns(aTable, aIncludedColumns, aExcludedColumns);
end Trg_GetColumnsUnchanged;

---------
function Trg_GetColumnsChangedList
( aTable            varchar2
, aIncludedColumns  Util.TStrs := null
, aExcludedColumns  Util.TStrs := null
) return varchar2
is
begin
  return Trg_GetColumns(aTable, aIncludedColumns, aExcludedColumns, aMode=>2);
end Trg_GetColumnsChangedList;

-------
function GetColumnDataType(aTableName varchar2, aColumnName varchar2) return varchar2
is
begin
  for cCur in
  ( select
        t1.data_type ||
        decode
        ( regexp_replace(t1.data_type, '^(N?(|VAR)CHAR2?|RAW)$', '#')
        , 'NUMBER', case when t1.data_scale is not null then
                      '(' || nvl(t1.data_precision, 38)
                          || case when t1.data_scale <> 0 then ',' || t1.data_scale end
                          || ')'
                    end
        , 'FLOAT',  case when t1.data_precision is not null then '(' || t1.data_precision || ')' end
        , '#', case when t1.data_length is not null then
                 '(' || case when t1.char_used = 'C' then to_char(t1.char_length) else to_char(t1.data_length) end || ')'
               end
        ) as data_type
      from user_tab_cols t1
      where t1.table_name = upper(aTableName)
        and t1.hidden_column = 'NO'
        and t1.column_name = upper(aColumnName)
  ) loop
    return cCur.data_type;
  end loop;
  Util.RaiseErr('Поле "%s" в таблице "%s" не найдено', aColumnName, aTableName);
end GetColumnDataType;

---------
procedure AlterColumnsDataType(aColumnList TColumnList, aType varchar2, aExpr varchar2 := null, aDropFKCons boolean := false)
is
  Pn2$ constant varchar2(30) := 'AlterColumnDataTypes';
  i int;
  fIsNotNull boolean;
  fTempColumnName varchar2(30);
  fLongOpId pls_integer := dbms_application_info.set_session_longops_nohint;
  fLongOpData pls_integer;
  fIsTableAltered boolean;
  fColumnType varchar2(30);
  --
  procedure SetSessionLongops(aIdx integer)
  is
  begin
    dbms_application_info.set_session_longops
    ( fLongOpId
    , fLongOpData
    , op_name=>'Alter data types'
    , sofar=>aIdx
    , totalwork=>aColumnList.count
    , target_desc=>'Update acounts and banks'
    , units=>'tables'
    );
    --dbms_lock.sleep(10);
  end;
  --
  procedure Notify(aMsg varchar2)
  is
  begin
    OutLines(aMsg);
    LogWork.Notify(Pn2$, Pn1$, aMsg);
  end Notify;
  --
begin
  for i in 1 .. aColumnList.count loop
    SetSessionLongops(i-1);
    --
    fColumnType := GetColumnDataType(aColumnList(i).table_name, aColumnList(i).column_name);
    fIsTableAltered := upper(fColumnType) = upper(aType);
    --
    for cCur in
    ( select column_name, nullable
        from user_tab_cols
        where table_name = upper(aColumnList(i).table_name)
          and hidden_column = 'NO'
    ) loop
      if upper(cCur.column_name) = upper(aColumnList(i).column_name) then
         fIsNotNull := cCur.nullable = 'N';
      end if;
      if upper(cCur.column_name) = upper(substr(aColumnList(i).column_name, 1, 29)||'!') then
        fIsNotNull := true;
        fIsTableAltered := false;
        exit;
      end if;
      if upper(cCur.column_name) = upper(substr(aColumnList(i).column_name, 1, 29)||'^') then
        fIsTableAltered := false;
      end if;
    end loop;
    fTempColumnName := substr(aColumnList(i).column_name, 1, 29) || case when fIsNotNull then '!' else '^' end;
    --
    if fIsTableAltered then
      Notify(Util.Format('Column %30s.%-30s already altered.', aColumnList(i).table_name, aColumnList(i).column_name));
    else
      Notify('======================================================');
      Notify(Util.Format('Altering column %30s.%-30s ...', aColumnList(i).table_name, aColumnList(i).column_name));
      UtilSql.Execute
      ('alter table !Table! disable all triggers'
      , aMacros=>Util.TStrs('!Table!',    aColumnList(i).table_name)
      );
      if aDropFKCons then
        for cCons in
        ( select cl.constraint_name
            from user_constraints c, user_cons_columns cl
            where cl.table_name = upper(aColumnList(i).table_name)
              and cl.column_name = upper(aColumnList(i).column_name)
              and c.table_name = cl.table_name
              and c.constraint_name = cl.constraint_name
              and c.constraint_type = 'R'
        ) loop
          UtilSql.Execute
          ( 'alter table !Table! drop constraint !Constraint!'
          , aMacros=>Util.TStrs
            ( '!Table!',    aColumnList(i).table_name
            , '!Constraint!',   cCons.constraint_name
            )
          );
        end loop;
      end if;
      --
      if fIsNotNull then
        UtilSql.Execute
        ( 'alter table !Table! modify !Column! null'
        , aMacros=>Util.TStrs
          ( '!Table!',    aColumnList(i).table_name
          , '!Column!',   aColumnList(i).column_name
          )
        , aIgnoreErrors=>Util.TInts(-01451)
        );
      end if;
      --
      UtilSql.Execute
      ( 'alter table !Table! add "!ColumnTemp!" !ColumnType!'
      , aIgnoreErrors=>Util.TInts(-01430)
      , aMacros=>Util.TStrs
        ( '!Table!',    aColumnList(i).table_name
        , '!ColumnTemp!', fTempColumnName
        , '!ColumnType!', fColumnType
        )
      );
      --
      UtilSql.Execute
      ( 'update !Table! set "!ColumnTemp!" = !Column!, !Column! = null where "!ColumnTemp!" is null and !Column! is not null'
      , aMacros=>Util.TStrs
        ( '!Table!',    aColumnList(i).table_name
        , '!Column!',   aColumnList(i).column_name
        , '!ColumnTemp!', fTempColumnName
        )
      );
      --
      UtilSql.Execute
      ( 'alter table !Table! modify !Column! !Type!'
      , aMacros=>Util.TStrs
        ( '!Table!',    aColumnList(i).table_name
        , '!Column!',   aColumnList(i).column_name
        , '!Type!',     aType
        )
      );
      --
      UtilSql.Execute
      ( 'update !Table! set !Column! = !ColumnTempExpr! where !Column! is null and "!ColumnTemp!" is not null'
      , aMacros=>Util.TStrs
        ( '!Table!',      aColumnList(i).table_name
        , '!Column!',     aColumnList(i).column_name
        , '!ColumnTempExpr!', Util.ReplaceMacros(nvl(aExpr, '%column%'), Util.TStrs('%column%', '"'||fTempColumnName||'"'))
        , '!ColumnTemp!', fTempColumnName
        )
      );
      --
      UtilSql.Execute
      ( 'alter table !Table! drop column "!ColumnTemp!"'
      , aMacros=>Util.TStrs
        ( '!Table!',      aColumnList(i).table_name
        , '!ColumnTemp!', fTempColumnName
        )
      );
      --
      if fIsNotNull then
        UtilSql.Execute
        ( 'alter table !Table! modify !Column! not null'
        , aMacros=>Util.TStrs
          ( '!Table!',    aColumnList(i).table_name
          , '!Column!',   aColumnList(i).column_name
          )
        );
      end if;
      UtilSql.Execute
      ('alter table !Table! enable all triggers'
      , aMacros=>Util.TStrs('!Table!',    aColumnList(i).table_name)
      );
      Notify('-----');
    end if;
  end loop;
  if aColumnList.count > 0 then
    SetSessionLongops(aColumnList.count);
  end if;
exception
  when others then
    LogWork.NotifyException(Pn1$, Pn2$);
    raise;
end AlterColumnsDataType;

---------
end UtilSql;

/
show err

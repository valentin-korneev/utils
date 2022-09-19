------------------------------------------------------------------------------------------
-- 22.08.2007 11:33:28 Elic - created
--------

prompt create or replace package body UtilLock

create or replace package body UtilLock
is
Pn1$ constant varchar2(30) := 'UtilLock';

gOwner constant varchar2(30) := sys_context('userenv', 'current_schema');

type TLocks is table of varchar2(128) index by varchar2(128);
gLocks TLocks;


---------
function GetLockHandle(aLockName varchar2, aKey varchar2 := null) return varchar2
is
  pragma autonomous_transaction;
  Pn2$ constant varchar2(30) := 'GetLockId';
  fFullLockName varchar2(128);
begin
  fFullLockName := rtrim(gOwner || '$' || aLockName || '$' || aKey, '$');
  if not gLocks.exists(fFullLockName) then
    dbms_lock.allocate_unique(fFullLockName, gLocks(fFullLockName));
  end if;
  return gLocks(fFullLockName);
exception
  when others then
    LogWork.NotifyException(Pn1$, Pn2$, aLockName);
    raise;
end GetLockHandle;

---------
function GetLockName(aLockHandle varchar2) return varchar2
is
  i varchar2(128);
begin
  i := gLocks.first;
  while i is not null loop
    if gLocks(i) = aLockHandle then
      return i;
    end if;
    i := gLocks.next(i);
  end loop;
  return aLockHandle;
end GetLockName;

---------
procedure Request(aLockHandle varchar2, aLockMode int := dbms_lock.x_mode, aTimeout int := dbms_lock.maxwait, aReleaseOnCommit boolean := true
, aRaiseTimedOutException boolean := false
)
is
  fLockStatus int;
begin
  fLockStatus := dbms_lock.request(aLockHandle, lockmode=>aLockMode, timeout=>aTimeout, release_on_commit=>aReleaseOnCommit);
  if aRaiseTimedOutException and fLockStatus = 1 then
    raise eTimedOut;
  end if;
  if fLockStatus not in (0, 4) then
    Util.RaiseErr('Returned %d while requesting lock %s', fLockStatus, GetLockName(aLockHandle));
  end if;
end Request;

---------
procedure Release(aLockHandle varchar2)
is
  fLockStatus int;
begin
  fLockStatus := dbms_lock.release(aLockHandle);
  if fLockStatus <> 0 then
    Util.RaiseErr('Returned %d while releasing lock %s', fLockStatus, GetLockName(aLockHandle));
  end if;
end Release;


---------
end UtilLock;
/
show err

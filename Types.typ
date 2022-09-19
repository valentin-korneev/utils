
set echo on

-- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

create or replace type tp_varchar2_100_table force is table of varchar2(100);
/

create or replace type tp_varchar2_4000_table force is table of varchar2(4000);
/

create or replace type tp_int_table force is table of int;
/

create or replace type tp_num_table force is table of number;
/

create or replace type tp_date_table force is table of date;
/
create or replace type tp_clob_table force is table of clob;
/

-- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

create or replace type tp_fio force as object
( surname               varchar2(30)
, first_name            varchar2(30)
, patronymic            varchar2(30)
-------------
, constructor function tp_fio
  ( self in out nocopy tp_fio
  , surname             varchar2 := ''
  , first_name          varchar2 := ''
  , patronymic          varchar2 := ''
  ) return self as result
);
/
show err
create or replace type body tp_fio
as
-------------
  constructor function tp_fio
  ( self in out nocopy tp_fio
  , surname             varchar2 := ''
  , first_name          varchar2 := ''
  , patronymic          varchar2 := ''
  ) return self as result
  is
  begin
    self.surname    := surname;
    self.first_name := first_name;
    self.patronymic := patronymic;
    return;
  end;
end;
/
show err

-- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

create or replace type tp_address force as object
( country               number(3)
, postcode              varchar2(10)
, region                varchar2(30)
, city_type             varchar2(50)
, city                  varchar2(30)
, street_type           varchar2(50)
, street                varchar2(50)
, house                 varchar2(10)
, building              varchar2(10)
, apartment             varchar2(10)
, district              varchar2(30)
-------------
, constructor function tp_address
  ( self in out nocopy tp_address
  , country             number   := null
  , postcode            varchar2 := ''
  , region              varchar2 := ''
  , city_type           varchar2 := ''
  , city                varchar2 := ''
  , street_type         varchar2 := ''
  , street              varchar2 := ''
  , house               varchar2 := ''
  , building            varchar2 := ''
  , apartment           varchar2 := ''
  , district            varchar2 := ''
  ) return self as result
-------------
, member function DataInitialized(self in tp_address) return boolean
);
/
show err

create or replace type body tp_address
as
-------------
  constructor function tp_address
  ( self in out nocopy tp_address
  , country             number   := null
  , postcode            varchar2 := ''
  , region              varchar2 := ''
  , city_type           varchar2 := ''
  , city                varchar2 := ''
  , street_type         varchar2 := ''
  , street              varchar2 := ''
  , house               varchar2 := ''
  , building            varchar2 := ''
  , apartment           varchar2 := ''
  , district            varchar2 := ''
  ) return self as result
  is
  begin
    self.country     := country;
    self.postcode    := postcode;
    self.region      := region;
    self.city_type   := city_type;
    self.city        := city;
    self.street_type := street_type;
    self.street      := street;
    self.house       := house;
    self.building    := building;
    self.apartment   := apartment;
    self.district    := district;
    return;
  end;
-------------
  member function DataInitialized(self in tp_address) return boolean
  is
  begin
    return    country     is not null
           or postcode    is not null
           or region      is not null
           or city_type   is not null
           or city        is not null
           or street_type is not null
           or street      is not null
           or house       is not null
           or building    is not null
           or apartment   is not null
           or district    is not null
    ;
  end DataInitialized;
end;
/
show err

-- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

---------------------------------------------
create or replace type tp_document force as object
( type                  int
, no                    varchar2(30)
, issued_since          date
, issued_by             varchar2(255)
, issued_country        varchar2(2)
, expired               date
---------------------------------------------
, constructor function tp_document
  ( self in out nocopy tp_document
  , type                int            := null
  , no                  varchar2       := null
  , issued_since        date           := null
  , issued_by           varchar2       := null
  , issued_country      varchar2       := null
  , expired             date           := null
  ) return self as result
);
/
show err

create or replace type body tp_document
as
---------------------------------------------
  constructor function tp_document
  ( self in out nocopy tp_document
  , type                int            := null
  , no                  varchar2       := null
  , issued_since        date           := null
  , issued_by           varchar2       := null
  , issued_country      varchar2       := null
  , expired             date           := null
  ) return self as result
  is
  begin
    self.type           := type;
    self.no             := no;
    self.issued_since   := issued_since;
    self.issued_by      := issued_by;
    self.issued_country := issued_country;
    self.expired        := expired;
    return;
  end;
end;
/
show err

-- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

create or replace type tp_lookup_item force as object
( code                  varchar2(99)
, name                  varchar2(99)
, icon                  varchar2(100)
-------------
, constructor function tp_lookup_item
  ( self in out nocopy tp_lookup_item
  , code                varchar2
  , name                varchar2 := ''
  , icon                varchar2 := ''
  ) return self as result
);
/
show err

create or replace type body tp_lookup_item
as
-------------
  constructor function tp_lookup_item
  ( self in out nocopy tp_lookup_item
  , code                varchar2
  , name                varchar2 := ''
  , icon                varchar2 := ''
  ) return self as result
  is
  begin
    self.code := code;
    self.name := substr(name, 1, 99);
    self.icon := icon;
    return;
  end tp_lookup_item;
end;
/
show err

create or replace type tp_lookup_items force is table of tp_lookup_item;
/
show err

create or replace type tp_lookup force as object
( items                 tp_lookup_items
, editable              varchar2(1) -- Y/N - допускается ли ввод значений не из списка
, hidden                varchar2(1) -- Y/N - не визуализировать lookup (использовать только для проверки на допустимость значения)
-------------
, constructor function tp_lookup
  ( self in out nocopy tp_lookup
  , items               tp_lookup_items := tp_lookup_items()
  , editable            varchar2 := 'N'
  , hidden              varchar2 := 'N'
  ) return self as result
-------------
, constructor function tp_lookup
  ( self in out nocopy tp_lookup
  , ref_cursor          sys_refcursor
  , editable            varchar2 := 'N'
  , is_tree             boolean  := false
  ) return self as result
-------------
, member procedure AddItem
  ( self in out nocopy tp_lookup
  , code                varchar2
  , name                varchar2 := ''
  , icon                varchar2 := ''
  )
-------------
, member function ItemCount(self in tp_lookup) return int
-------------
, member function Lookup    (self in tp_lookup, aCode varchar2, aErrorText varchar2 := '') return varchar2
, member function LookupCode(self in tp_lookup, aName varchar2, aErrorText varchar2 := '') return varchar2
);
/
show err

create or replace type body tp_lookup
as
-------------
  constructor function tp_lookup
  ( self in out nocopy tp_lookup
  , items               tp_lookup_items := tp_lookup_items()
  , editable            varchar2 := 'N'
  , hidden              varchar2 := 'N'
  ) return self as result
  is
  begin
    self.items    := items;
    self.editable := editable;
    self.hidden   := hidden;
    return;
  end tp_lookup;
-------------
  constructor function tp_lookup
  ( self in out nocopy tp_lookup
  , ref_cursor          sys_refcursor
  , editable            varchar2 := 'N'
  , is_tree             boolean  := false
  ) return self as result
  is
    fKeyColumnPos    int := 1;
    fResultColumnPos int := case when is_tree then 5 else 2 end;
  begin
    declare
      fCursor  int;
      fLookup  sys_refcursor := ref_cursor;
      fCode    dbms_sql.VARCHAR2_TABLE;
      fValue   dbms_sql.VARCHAR2_TABLE;
      fRows    int;
      fMaxRows int := 10000;
    begin
      fCursor := dbms_sql.to_cursor_number(fLookup);
      dbms_sql.define_array(fCursor, fKeyColumnPos   , fCode , fMaxRows, 1);
      dbms_sql.define_array(fCursor, fResultColumnPos, fValue, fMaxRows, 1);

      loop
        fRows := dbms_sql.fetch_rows(fCursor);
        exit when fRows = 0;

        dbms_sql.column_value(fCursor, fKeyColumnPos   , fCode);
        dbms_sql.column_value(fCursor, fResultColumnPos, fValue);
        for i in fCode.first .. fCode.last loop
          if not is_tree or fCode(i) is not null then
            if items is null then
              items := tp_lookup_items();
            end if;
            items.extend;
            items(items.last) := tp_lookup_item(substr(fCode(i), 1, 99), substr(fValue(i), 1, 99));
          end if;
        end loop;
        exit when fRows < fMaxRows;
      end loop;
      dbms_sql.close_cursor(fCursor);
    end;
    self.editable := editable;
    self.hidden   := 'N';
    return;
  end tp_lookup;
-------------
  member procedure AddItem
  ( self in out nocopy tp_lookup
  , code                varchar2
  , name                varchar2 := ''
  , icon                varchar2 := ''
  )
  is
  begin
    if items is null then
      items := tp_lookup_items();
    end if;
    items.extend;
    items(items.last) := tp_lookup_item(code, nvl(name, code), icon);
  end AddItem;
-------------
  member function ItemCount(self in tp_lookup) return int
  is
  begin
    return case when items is null then 0 else items.count end;
  end ItemCount;
-------------
  member function Lookup(self in tp_lookup, aCode varchar2, aErrorText varchar2 := '') return varchar2
  is
  begin
    for i in 1 .. ItemCount loop
      if items(i).code = aCode or items(i).code is null and aCode is null then
        return items(i).name;
      end if;
    end loop;
    if aErrorText is not null then
      raise_application_error(-20000, regexp_replace(aErrorText, '%s', aCode, 1, 1));
    end if;
    return null;
  end Lookup;
-------------
  member function LookupCode(self in tp_lookup, aName varchar2, aErrorText varchar2 := '') return varchar2
  is
  begin
    for i in 1 .. ItemCount loop
      if items(i).name = aName or items(i).name is null and aName is null then
        return items(i).code;
      end if;
    end loop;
    if aErrorText is not null then
      raise_application_error(-20000, regexp_replace(aErrorText, '%s', aName, 1, 1));
    end if;
    return null;
  end LookupCode;
end;
/
show err

set echo off

set feed off
exec dbms_session.reset_package
set serveroutput on
set feed on

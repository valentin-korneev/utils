-------------------------------------------------------------------
--
--  Script: row_len_distr.sql
--  Purpose: to calculate Distribution of Row Lengths in table
--
--  Copyright:  Vladimir Demkin
--  Author:  Vladimir Demkin
--
--  Comment: only works for tables with column datatypes:
--  CHAR, NCHAR, VARCHAR2, NVARCHAR2, NUMBER, RAW, DATE, ROWID
--
-------------------------------------------------------------------
--  Ported to Oracle 7.3 by Elic
-------------------------------------------------------------------

prompt
accept TABLE_NAME prompt "Enter table name: "
accept WHERE prompt "Enter WHERE condition (default 1=1): "
set serveroutput on

prompt

DECLARE
  sql_text VARCHAR2(32767);
  CURSOR desc_cur IS SELECT column_name FROM user_tab_columns WHERE
      table_name=UPPER('&TABLE_NAME')
      ORDER BY column_id;
  TYPE desc_table_type IS TABLE OF desc_cur%rowtype
      INDEX BY BINARY_INTEGER;
  desc_table desc_table_type;
  column_count BINARY_INTEGER:=0;
  ExeCursor INTEGER;
  Perc INTEGER;
  Len  INTEGER;
  Ignore NUMBER;
  WhereCond VARCHAR2(2048):='&WHERE';
BEGIN
  IF WhereCond IS NULL THEN
    WhereCond:='1=1';
  END IF;
  FOR desc_rec IN desc_cur
  LOOP
      column_count:=column_count+1;
      desc_table(column_count):=desc_rec;
  END LOOP;
  sql_text:='SELECT CEIL(t.item/n.row_num*20)*5 prec, MAX(row_length) length from ';
  sql_text:=sql_text||' (SELECT rownum item,row_length FROM (select row_length from(SELECT ';
  FOR I IN 1..COLUMN_COUNT
  LOOP
    IF I>1 THEN
      sql_text:=sql_text||'+';
    END IF;
    sql_text:=sql_text||'(NVL(VSIZE('||desc_table(I).column_name||'),0)+DECODE(TRUNC(NVL(VSIZE('||
    desc_table(I).column_name||')/250,0)),0,1,3))';
    sql_text:=sql_text||'*DECODE(';
    FOR J in I..column_count
    LOOP
        IF J>I THEN
          sql_text:=sql_text||'*';
        END IF;
        sql_text:=sql_text||'decode('||desc_table(J).column_name||',null,1,0)';
    END LOOP;
    sql_text:=sql_text||',0,1,0)';
  END LOOP;
  sql_text:=sql_text||'+3 row_length FROM &TABLE_NAME WHERE '||WhereCond||') group by row_length,rownum)) t,';
  sql_text:=sql_text||'(SELECT COUNT(*) row_num FROM &TABLE_NAME WHERE '||WhereCond||') n ';
  sql_text:=sql_text||'GROUP BY CEIL(t.item/n.row_num*20)*5';
  ExeCursor:=DBMS_SQL.OPEN_CURSOR;
  DBMS_SQL.PARSE(ExeCursor,sql_text,DBMS_SQL.native);
  DBMS_SQL.DEFINE_COLUMN(ExeCursor,1,Perc);
  DBMS_SQL.DEFINE_COLUMN(ExeCursor,2,Len);
  Ignore:=DBMS_SQL.EXECUTE(ExeCursor);
  DBMS_OUTPUT.PUT_LINE('Distribution of Row Lengths');
  DBMS_OUTPUT.PUT_LINE('TABLE: '||UPPER('&TABLE_NAME'));
  DBMS_OUTPUT.PUT_LINE('WHERE: '||WhereCond);
  DBMS_OUTPUT.PUT_LINE('---------------------------------');
  LOOP
    EXIT WHEN DBMS_SQL.FETCH_ROWS(ExeCursor)=0;
    DBMS_SQL.COLUMN_VALUE(ExeCursor,1,Perc);
    DBMS_SQL.COLUMN_VALUE(ExeCursor,2,Len);
    DBMS_OUTPUT.PUT_LINE('|'||TO_CHAR(Perc,'999')||'% of rows >= '||TO_CHAR(Len,'999999')||' bytes |');
  END LOOP;
  DBMS_OUTPUT.PUT_LINE('---------------------------------');
  DBMS_SQL.CLOSE_CURSOR(ExeCursor);
end;
/

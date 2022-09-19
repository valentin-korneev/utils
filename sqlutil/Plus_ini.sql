set show off
set ver off
set pagesize 25
set num 13
set serveroutput on size unlimited
set line 1000
set array 14
set long 10000
set longchunksize 1000
set trimspool on
clear break
clear column
ttitle off
set tab off

col line/col for a8 hea 'Line/Col'
col error for a89 wor hea 'Error Message'

-- Defaults for SET AUTOTRACE EXPLAIN report
column id_plus_exp format 990 heading i
column parent_id_plus_exp format 990 heading p
column plan_plus_exp format a100
column object_node_plus_exp format a8
column other_tag_plus_exp format a29
column other_plus_exp format a44

col status for 90 hea 'Stat'
col currency for 999 hea '$-$'
col comments for a20 hea 'Comments' tru

col error_text for a30

set termout off heading off
col db_name noprint new_v dbname
select initcap(sys_context('USERENV', 'DB_NAME')) db_name from dual;
col db_name cle

define srv_host=?
define srv_ip=x.x.x.x
col machine noprint new_v srv_host
col ip      noprint new_v srv_ip
select utl_inaddr.get_host_address() as ip, utl_inaddr.get_host_name() as machine from dual;
col machine cle
col ip noprint cle

define prompt_usr=?
define prompt_inf=?
col user_name noprint new_v prompt_usr
col info      noprint new_v prompt_inf
select
    chr(10)||initcap(to_char(sysdate,'fmdayfm dd.mm.yyyy hh24:mi:ss', 'nls_date_language=russian'))
    ||', User: '||user||'@&_CONNECT_IDENTIFIER, DB: &dbname@&srv_host(&srv_ip)'||chr(10) info,
    regexp_replace(initcap(regexp_replace(user, '^OWN(ER)?_'))
    || '@' || regexp_replace('&_CONNECT_IDENTIFIER', '^\d{1,3}\.\d{1,3}\.(\d{1,3}\.\d{1,3})', '…\1'), '^(.{47})..+$', '\1…') user_name
  from dual
;
col user_name cle
col info cle

set termout on
prompt &prompt_inf
--set sqlprompt "&prompt_usr@&dbname> "
set sqlprompt "&prompt_usr> "
undefine dbname
undefine prompt_inf
undefine prompt_usr

set sqlnumber off
set heading on

set termout off
alter session set nls_date_format='dd.mm.rr hh24:mi:ss';
set termout on



col direction for 90 hea 'Dir'
col payer for 999999990 hea 'Payer'
col payee for 999999999990 hea 'Payee'
col payee_bank for 990 hea 'PeBnk'
col terminal for 00000000 hea 'Terminal'
col operation_count for 99990 hea 'Op##'
col PAYEE_NAME for a15 tru
col DESTINATION for a80
col source_doc_type for 0 hea 'SrcT'
col source_doc_isn for 9999990 hea 'SrcIsn'
col operation_code for 90 hea 'Op'
col operation_result for 990 hea 'OpRes'
col code for 999999990
col issuer for 99999990 hea 'Issuer'
col acquirer for 99999990 hea 'Aquirer'
col approval_source hea '}'
col action for 990 hea 'Actn'
col terminal_local_time hea 'TerminalLocalTime'
col REVERSAL_REASON for 990 hea 'Revers'
col operation_no for 9999990 hea 'Op#'

col abonent for 00000000 hea 'Abonent'
col address for a20 hea 'Address' tru
col mti for 9990
col transport_error for 990 hea 'TErr'

col id for 9999999990

col fee_amount for 9999999D99 hea 'FeeAmnt'
col service_no for 999990 hea 'Serv#'

col card_number for 9999999999999999

col fee_count hea "FeeCnt" for 9990

col description for a50 tru hea "Description"

col extra_info for a30

col DIRECTORY_PATH for a100
col EXTERNAL_NAME for a100
col filename for a30

col VALUE_COL_PLUS_SHOW_PARAM for a100

col options  for XXXXXXXX
col features for XXXXXXX

col reqcomments for a50
col inventory_name for a20


col ORA_ERR_MESG$ for a30
col ORA_ERR_ROWID$ for a15
col ORA_ERR_TAG$ for a10

SET RECSEP off

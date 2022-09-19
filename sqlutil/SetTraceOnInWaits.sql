--exec sys.dbms_system.set_sql_trace_in_session(&1,&2,true)
exec sys.dbms_system.set_ev(&1,&2,10046,8,'');

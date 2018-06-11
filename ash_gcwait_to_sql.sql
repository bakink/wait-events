--https://www.hhutzler.de/blog/ash_gcwait_to_sql-sql/
col event format a30
col sample_time format a25
set linesize 180
set pagesize 100 
/*
define wait_threshold=10
*/

prompt -> Find waits grouped by  Instance,SessioniID,SQLID,Event
select inst_id,  session_id, sql_id,event, count(*) CNT 
  from gv$active_session_history
    where user_id = ( select USER_ID from dba_users where USERNAME = 'SCOTT' ) and sql_id is  not null
      and sample_time between (sysdate -(4/24) ) and  sysdate    
   group by inst_id,  session_id,sql_id, event having count(*) > &wait_threshold 
   order by inst_id,  session_id, sql_id, CNT;

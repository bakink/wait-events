--https://andreynikolaev.wordpress.com/scripts/mutexes/mutex_ash_waits-sql/

/*
     This file is part of demos for "Mutex Internals" seminar v.04.04.2011
     Andrey S. Nikolaev (Andrey.Nikolaev@rdtex.ru) 
     https://andreynikolaev.wordpress.com 
 
     Sessions waited for mutexes from v$active_session_history
     Some columns were not printed to fit linesize 80. You can adjust this.
     BLKS - Blocking SID
     LOC  - mutex sleep Location_ID
     RFC  - mutex RefCount
 
     usage: @mutex_ash_waits
*/
col sample_id noprint format 9999999
col sample_time format a8
col session_id heading "SID" format 9999
col session_serial# noprint format 9999
col event format a19
col blocking_sid heading "BLKS" format 9999
col shared_refcount noprint heading "RFC" format 99
col location_id heading "LOC" format 99
col sleeps  noprint format 99999
col mutex_object format a15
set pagesize 50000
set wrap off
 
SELECT sample_id,to_char(sample_time,'hh24:mi:ss') sample_time,session_id,session_serial#,sql_id,event,p1 IDN,
            FLOOR (p2/POWER(2,4*ws)) blocking_sid,MOD (p2,POWER(2,4*ws)) shared_refcount,
            FLOOR (p3/POWER (2,4*ws)) location_id,MOD (p3,POWER(2,4*ws)) sleeps,
            CASE WHEN (event LIKE 'library cache:%' AND p1 <= power(2,17)) THEN  'library cache bucket: '||p1 
                    ELSE  (SELECT kglnaobj FROM x$kglob WHERE kglnahsh=p1 AND (kglhdadr = kglhdpar) and rownum=1) END mutex_object
       FROM (SELECT DECODE (INSTR (banner, '64'), 0, '4', '8') ws FROM v$version WHERE ROWNUM = 1) wordsize, 
                  v$active_session_history 
       WHERE p1text='idn' AND session_state='WAITING'
       ORDER BY sample_id;
/* 
SQL> @mutex_ash_waits
 
SAMPLE_T   SID SQL_ID        EVENT                       P1  BLKS LOC MUTEX_OBJE
-------- ----- ------------- ------------------- ---------- ----- --- ----------
18:16:45   135               cursor: pin S       3222383532    13   9 select 1 f
18:16:42   135 47z9gc7013axc cursor: pin S       3222383532    13   3 select 1 f
18:16:38   135 47z9gc7013axc cursor: pin S       3222383532    13   3 select 1 f
18:16:37   135 47z9gc7013axc cursor: pin S       3222383532    13   3 select 1 f
18:16:36   135 47z9gc7013axc cursor: pin S       3222383532     0   3 select 1 f
18:16:33    13 47z9gc7013axc cursor: pin S       3222383532   135   3 select 1 f
...
*/

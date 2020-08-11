
--http://allappsdba.blogspot.com.tr/2012/04/to-check-library-cache-lock-contention.html
--http://albertdba.com/?p=1865#more-1865

Note:
Library Cache contention is a serious issue. In most cases it would be good to analyze what is holding the library cache lock and killing it will resolve the issue. Library cache events can even bring the database to a hang state. It's a good idea to identify and kill appropriately as early as possible. But do not kill any mandatory processes or sessions as it may lead to an outage. Contact Oracle support for critical issues.

Library cache resource types waited for over the life of the instance

set linesize 152
column average_wait format 9999990.00

select substr(e.event, 1, 40) event,
e.time_waited,
e.time_waited / decode(
e.event,
'latch free', e.total_waits,
decode(e.total_waits - e.total_timeouts,0, 1,e.total_waits - e.total_timeouts)) average_wait
from sys.v$system_event e,
sys.v$instance i
where e.event like '%library cache%';

Detect sessions waiting for a Library Cache Locks

select sid Waiter, p1raw,
substr(rawtohex(p1),1,30) Handle,
substr(rawtohex(p2),1,30) Pin_addr
from v$session_wait where wait_time=0 and event like '%library cache%';

Sessions waiting for lib cache in RAC

select a.sid Waiter,b.SERIAL#,a.event,a.p1raw,
substr(rawtohex(a.p1),1,30) Handle,
substr(rawtohex(a.p2),1,30) Pin_addr
from v$session_wait a,v$session b where a.sid=b.sid
and a.wait_time=0 and a.event like 'library cache%';

Objects locked by Library Cache based on sessions detected above

select to_char(SESSION_ID,'999') sid ,
substr(LOCK_TYPE,1,30) Type,
substr(lock_id1,1,23) Object_Name,
substr(mode_held,1,4) HELD, substr(mode_requested,1,4) REQ,
lock_id2 Lock_addr
from dba_lock_internal
where
mode_requested<>'None'
and mode_requested<>mode_held
and session_id in ( select sid
from v$session_wait where wait_time=0
and event like '%library cache%') ;

Detect Library Cache holders that sessions are waiting for

select sid Holder ,KGLPNUSE Sesion , KGLPNMOD Held, KGLPNREQ Req
from x$kglpn , v$session
where KGLPNHDL in (select p1raw from v$session_wait
where wait_time=0 and event like '%library cache%')
and KGLPNMOD <> 0
and v$session.saddr=x$kglpn.kglpnuse ;

Sessions holding the lib cache in RAC

select a.sid Holder ,a.SERIAL#,b.INST_ID,b.KGLPNUSE Sesion , b.KGLPNMOD Held, b.KGLPNREQ Req
from x$kglpn b , v$session a
where b.KGLPNHDL in (select p1raw from v$session_wait
where wait_time=0 and event like 'library cache%')
and b.KGLPNMOD <> 0
and a.saddr=b.kglpnuse ;

What are the holders waiting for?

select sid,substr(event,1,30),wait_time
from v$session_wait
where sid in (select sid from x$kglpn , v$session
where KGLPNHDL in (select p1raw from v$session_wait
where wait_time=0 and event like 'library cache%')
and KGLPNMOD <> 0
and v$session.saddr=x$kglpn.kglpnuse );

Note:
Sometimes using the library query below to identify the holding sessions can cause temp tablespace to run out of space….

ORA-01652: unable to extend temp segment by 256 in tablespace TEMP
Current SQL statement for this session:
select to_char(SESSION_ID,'999') sid ,
substr(LOCK_TYPE,1,30) Type,
substr(lock_id1,1,23) Object_Name,
substr(mode_held,1,4) HELD, substr(mode_requested,1,4) REQ,
lock_id2 Lock_addr
from dba_lock_internal
where
mode_requested<>'None'
and mode_requested<>mode_held
and session_id in ( select sid
from v$session_wait where wait_time=0
and event like 'library cache%')

Solution: Henceforth, Please use queries using x$kglob or x$kgllk or x$kglpn.. or tweak the following sql ( picked up from metalink) to gather lib cache lock event details

ReWritten SQL
select /*+ ordered */ w1.sid waiting_session,
h1.sid holding_session,
w.kgllktype lock_or_pin,
w.kgllkhdl address,
decode(h.kgllkmod, 0, 'None', 1, 'Null', 2, 'Share', 3, 'Exclusive',
'Unknown') mode_held,
decode(w.kgllkreq, 0, 'None', 1, 'Null', 2, 'Share', 3, 'Exclusive',
'Unknown') mode_requested
from dba_kgllock w, dba_kgllock h, v$session w1, v$session h1
where
(((h.kgllkmod != 0) and (h.kgllkmod != 1)
and ((h.kgllkreq = 0) or (h.kgllkreq = 1)))
and
(((w.kgllkmod = 0) or (w.kgllkmod= 1))
and ((w.kgllkreq != 0) and (w.kgllkreq != 1))))
and w.kgllktype = h.kgllktype
and w.kgllkhdl = h.kgllkhdl
and w.kgllkuse = w1.saddr
and h.kgllkuse = h1.saddr;

Library cache pin sessions
SELECT s.sid,
waiter.p1raw w_p1r,
holder.event h_wait,
holder.p1raw h_p1r,
holder.p2raw h_p2r,
holder.p3raw h_p2r,
count(s.sid) users_blocked,
sql.hash_value
FROM
v$sql sql,
v$session s,
x$kglpn p,
v$session_wait waiter,
v$session_wait holder
WHERE
s.sql_hash_value = sql.hash_value and
p.kglpnhdl=waiter.p1raw and
s.saddr=p.kglpnuse and
waiter.event like 'library cache pin' and
holder.sid=s.sid
GROUP BY
s.sid,
waiter.p1raw ,
holder.event ,
holder.p1raw ,
holder.p2raw ,
holder.p3raw ,
sql.hash_value;

Library Cache lock Query
select decode(lob.kglobtyp,
0, 'NEXT OBJECT ',
1, 'INDEX ',
2, 'TABLE ',
3, 'CLUSTER ',
4, 'VIEW ',
5, 'SYNONYM ',
6, 'SEQUENCE ',
7, 'PROCEDURE ',
8, 'FUNCTION ',
9, 'PACKAGE ',
11, 'PACKAGE BODY ',
12, 'TRIGGER ',
13, 'TYPE ',
14, 'TYPE BODY ',
19, 'TABLE PARTITION ',
20, 'INDEX PARTITION ',
21, 'LOB ',
22, 'LIBRARY ',
23, 'DIRECTORY ',
24, 'QUEUE ',
28, 'JAVA SOURCE ',
29, 'JAVA CLASS ',
30, 'JAVA RESOURCE ',
32, 'INDEXTYPE ',
33, 'OPERATOR ',
34, 'TABLE SUBPARTITION ',
35, 'INDEX SUBPARTITION ',
40, 'LOB PARTITION ',
41, 'LOB SUBPARTITION ',
42, 'MATERIALIZED VIEW ',
43, 'DIMENSION ',
44, 'CONTEXT ',
46, 'RULE SET ',
47, 'RESOURCE PLAN ',
48, 'CONSUMER GROUP ',
51, 'SUBSCRIPTION ',
52, 'LOCATION ',
55, 'XML SCHEMA ',
56, 'JAVA DATA ',
57, 'SECURITY PROFILE ',
59, 'RULE ',
62, 'EVALUATION CONTEXT ',
'UNDEFINED ') object_type,
lob.kglnaobj object_name,
pn.kglpnmod lock_mode_held,
pn.kglpnreq lock_mode_requested,
ses.sid,
ses.serial#,
ses.username
from sys.v$session_wait vsw,
sys.x$kglob lob,
sys.x$kglpn pn,
sys.v$session ses
where vsw.event = 'library cache lock '
and vsw.p1raw = lob.kglhdadr
and lob.kglhdadr = pn.kglpnhdl
and pn.kglpnmod != 0
and pn.kglpnuse = ses.saddr
/

Detect Library Cache holders that sessions are waiting for

set pagesize 40
select x$kglpn.inst_id,sid Holder ,KGLPNUSE Sesion , KGLPNMOD Held, KGLPNREQ Req
from x$kglpn , gv$session
where KGLPNHDL in (select p1raw from gv$session_wait
where wait_time=0 and event like 'library cache%')
and KGLPNMOD <> 0
and gv$session.saddr=x$kglpn.kglpnuse ;
PROMPT Detect Library Cache holders that sessions are waiting for

Detect sessions waiting for a Library Cache Locks

select sid Waiter, p1raw,
substr(rawtohex(p1),1,30) Handle,
substr(rawtohex(p2),1,30) Pin_addr
from gv$session_wait where wait_time=0 and event like 'library cache%';

Sessions waiting on Library Cache events

set pagesize 80
undefine spid
col spid for a8
col INST_ID for 99
col sid for 99999
set linesize 140
col action format a20
col logon_time format a15
col module format a13
col cli_process format a7
col cli_mach for a15
col status format a10
col username format a10
col event for a20
col program for a20
col "Last SQL" for a30
col last_call_et_hrs for 999.99
col sql_hash_value for 9999999999999
select p.INST_ID,p.spid,s.sid, s.serial#, s.status,s.last_call_et/3600 last_call_et_hrs ,
s.process cli_process,s.machine cli_mach,sw.event,
s.action,s.module,s.program,s.sql_hash_value,t.disk_reads,lpad(t.sql_text,30) "Last SQL"
from gv$session s, gv$sqlarea t,gv$process p,gv$session_wait sw
where s.sql_address =t.address and
s.sql_hash_value =t.hash_value and
p.addr=s.paddr and
s.sid=sw.sid and
sw.event like '%library cache%'
order by p.spid;

set lines 152
col sid for a9999999999999
col name for a40
select a.sid,b.name,a.value,b.class
from gv$sesstat a , gv$statname b
where a.statistic#=b.statistic#
and name like '%library cache%';

select sid
from gv$session_wait where wait_time=0
and event like 'library cache%';

Objects waiting for Library Cache lock

col type for a20
set linesize 150
set pagesize 80
col OBJECT_NAME for a20
col LOCK_ADDR for a20

select to_char(SESSION_ID,'999') sid ,
substr(LOCK_TYPE,1,30) Type,
substr(lock_id1,1,23) Object_Name,
substr(mode_held,1,4) HELD, substr(mode_requested,1,4) REQ,
lock_id2 Lock_addr
from dba_lock_internal
where
mode_requested<>'None'
and mode_requested<>mode_held
and session_id in ( select sid
from gv$session_wait where wait_time=0
and event like 'library cache%') ;
This script shows the Library cache resource types waited for over the life of the instance

set linesize 152
column average_wait format 9999990.00
col event for a30
col HANDLE for a20
col PIN_ADDR for a20
col TYPE for a20
col OBJECT_NAME for a35
col LOCK_ADDR for a30

select substr(e.event, 1, 40) event,
e.time_waited,
e.time_waited / decode(
e.event,
'latch free', e.total_waits,
decode(e.total_waits - e.total_timeouts,0, 1,e.total_waits - e.total_timeouts)) average_wait
from sys.v$system_event e,
sys.v$instance i
where e.event like 'library cache%';

Count of sessions waiting

select count(SESSION_ID) total_waiting_sessions
from dba_lock_internal
where
mode_requested<>'None'
and mode_requested<>mode_held
and session_id in ( select sid
from v$session_wait where wait_time=0
and event like 'library cache%') ;

What are the holders waiting for?

select sid,substr(event,1,30) event,wait_time
from v$session_wait
where sid in (select sid from x$kglpn , v$session
where KGLPNHDL in (select p1raw from v$session_wait
where wait_time=0 and event like 'library cache%')
and KGLPNMOD <> 0
and v$session.saddr=x$kglpn.kglpnuse );

Process ids/sid/pid

col spid for a6
col sid for 99999
set linesize 152
set pagesize 80
col action format a20
col logon_time format a15
col program for a10
col terminal for a10
col module format a13
col cli_process format a7
col cli_mach for a10
col status format a10
col username format a10
col last_call_et for 999.999
select a.sid ,
a.serial# ,
a.username ,
a.status ,
a.machine cli_mach,
a.terminal ,
a.program ,
a.module ,
a.action ,
a.sql_hash_value ,
to_char(a.logon_time,'DD-Mon-YYYY HH24:MI:SS') logon_time ,
round((a.last_call_et/60),2) last_call_et,
a.process cli_process,
b.spid spid,
b.event event,
b.state state
from gv$session a, gv$process b, gv$session_wait sw
where a.paddr=b.addr and a.inst_id=b.inst_id
and a.sid in (583,743,669,766
)
and a.inst_id=sw.inst_id
and a.sid=sw.sid;

Session details

set linesize 150
col action format a25
col logon_time format a16
col module format a13
col program for a15
col process format a7
col status format a10
col username format a10
col last_call_et for 9999.99
select s.sid,p.spid,s.program, s.serial#, s.status, s.username, s.action,
to_char(s.logon_time, 'DD-MON-YY, HH24:MI') logon_time,
s.module,s.last_call_et/3600 last_call_et,s.process
from gv$session s, gv$process p
where p.addr=s.paddr and s.sid= '&sid';

Last SQL
col username for a10
col "Last SQL" for a65
col process for a10
set pagesize 48
select s.username, s.sid,s.process, s.status,t.sql_text "Last SQL"
from gv$session s, gv$sqlarea t
where s.sql_address =t.address and
s.sql_hash_value =t.hash_value and
s.sid = '&sid';

Wait event

column seq# format 99999
column EVENT format a30
column p2 format 999999
column STATE format a10
column WAIT_T format 9999
select SID,SEQ#,EVENT,P1,P2,WAIT_TIME WAIT_T,SECONDS_IN_WAIT,STATE
from v$session_wait
where sid in (159,610);

Last SQL Multiple inputs
col username for a10
col "Last SQL" for a65
col process for a10
set pagesize 48
select s.username, s.sid,s.process, s.status,t.sql_text "Last SQL"
from gv$session s, gv$sqlarea t
where s.sql_address =t.address and
s.sql_hash_value =t.hash_value and
s.sid in (190,224,217,306);

Active transactions multiple inputs

select username,s.sid,
t.used_ublk,t.used_urec
from v$transaction t,v$session s
where t.addr=s.taddr and
s.sid in (159,610);

Session details thru server process id

undefine spid
col spid for a10
set linesize 150
col action format a10
col logon_time format a16
col module format a13
col cli_process format a7
col cli_mach for a15
col status format a10
col username format a10
col last_call_et for 9999.99
select p.spid,s.sid, s.serial#, s.status, s.username, s.action,
to_char(s.logon_time, 'DD-MON-YY, HH24:MI') logon_time,
s.module,s.last_call_et/3600 last_call_et,s.process cli_process,s.machine cli_mach
from gv$session s, gv$process p
where p.addr=s.paddr and p.spid= '&spid';

Session details thru Client process name

undefine spid
col spid for a6
col sid for 99999
set linesize 140
col action format a20
col logon_time format a15
col module format a13
col cli_process format a7
col cli_mach for a10
col status format a10
col username format a10
select p.spid,s.sid, s.serial#, s.status, s.username, s.action,
to_char(s.logon_time, 'DD-MON-YY, HH24:MI') logon_time,
s.module,s.last_call_et/3600,s.process cli_process,s.machine cli_mach
from gv$session s, gv$process p
where p.addr=s.paddr and s.process = '&cli_process';

Details thru multiple inputs of SIDs

undefine spid
col last_call_et for 9999999
set pagesize 40
col spid for a6
col sid for 99999
set linesize 150
col action format a20
col logon_time format a15
col module format a13
col cli_process format a7
col cli_mach for a10
col status format a10
col last_call_et for 999.99
col username format a10
select p.spid,s.sid, s.serial#, s.status, s.username, s.action,
to_char(s.logon_time, 'DD-MON-YY, HH24:MI') logon_time,
s.module,s.last_call_et/3600 last_call_et,s.process cli_process,s.machine cli_mach
from gv$session s, gv$process p
where p.addr=s.paddr and s.sid in (51,146,407,397,389,377,345,302,239,214)
order by sid;

This script points to the session that is holding a library cache lock for any object. A typical session will wait on a library cache lock when when it is trying to modify the object definition. The object may be a package/procedure or just a table or index definition

SELECT a.KGLPNMOD, a.KGLPNREQ, b.username, c.KGLNAOBJ, c.KGLOBTYP
FROM
x$kglpn a,
v$session b,
x$kglob c
WHERE
a.KGLPNUSE = b.saddr and
upper(c.KGLNAOBJ) like upper('%&obj_name%') and
a.KGLPNHDL = c.KGLHDADR
/
Exit

---https://redikx.wordpress.com/2009/09/25/library-cache-lock-find-locking-session/

Library cache lock – find locking session
Posted on September 25, 2009 by redikx
1.
select saddr from v$session where sid in (select sid from v$session_wait where event like ‘library cache lock’);

2. FIND BLOCKER:

SELECT SID,USERNAME,TERMINAL,PROGRAM FROM V$SESSION
WHERE SADDR in
(SELECT KGLLKSES FROM X$KGLLK LOCK_A
WHERE KGLLKREQ = 0
AND EXISTS (SELECT LOCK_B.KGLLKHDL FROM X$KGLLK LOCK_B
WHERE KGLLKSES = 'result_from_1' /* BLOCKED SESSION */
AND LOCK_A.KGLLKHDL = LOCK_B.KGLLKHDL
AND KGLLKREQ > 0)
);

3. FIND BLOCKED:

SELECT SID,USERNAME,TERMINAL,PROGRAM FROM V$SESSION
WHERE SADDR in
(SELECT KGLLKSES FROM X$KGLLK LOCK_A
WHERE KGLLKREQ > 0
AND EXISTS (SELECT LOCK_B.KGLLKHDL FROM X$KGLLK LOCK_B
WHERE KGLLKSES = 'saddr_from_v$session above' /* BLOCKING SESSION */
AND LOCK_A.KGLLKHDL = LOCK_B.KGLLKHDL
AND KGLLKREQ = 0)
);


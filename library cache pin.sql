--https://sites.google.com/site/embtdbo/wait-event-documentation/oracle-library-cache#TOC-library-cache-pin
--http://ksun-oracle.blogspot.com/2011/11/oracle-11gr2-single-session-library.html
--http://db-oriented.com/2017/12/05/ebr-part-2-changing-a-package-body-the-problems/
--Find the blocker
select
       waiter.sid   waiter,
       waiter.event wevent,
       to_char(blocker_event.sid)||','||to_char(blocker_session.serial#) blocker,
       substr(decode(blocker_event.wait_time,
                     0, blocker_event.event,
                    'ON CPU'),1,30) bevent
from
       x$kglpn p,
       gv$session      blocker_session,
       gv$session_wait waiter,
       gv$session_wait blocker_event
where
          p.kglpnuse=blocker_session.saddr
   and p.kglpnhdl=waiter.p1raw
   and waiter.event in ( 'library cache pin' , 
                                      'library cache lock' ,
                                      'library cache load lock')
   and blocker_event.sid=blocker_session.sid
   and waiter.sid != blocker_event.sid
order by
      waiter.p1raw,waiter.sid


*****************************************
--http://db-oriented.com/2017/12/05/ebr-part-2-changing-a-package-body-the-problems/

col action format a21
col event format a20
col blocker format a21
col object_type format a20
col object_name format a20
col mode_held format a10
col mode_requested format a10

break on action on event on blocker on blocked_duration skip 1

select s.action,
       s.event,
       b.action blocker,
       nvl2(b.sid,s.seconds_in_wait,null) blocked_duration,
       o.kglobtyd object_type,
       o.kglnaobj object_name,
       l.type,
       decode(l.mode_held, 1, 'null', 2, 'share', 3, 'exclusive') mode_held,
       decode(l.mode_requested, 1, 'null', 2, 'share', 3, 'exclusive') mode_requested
from   v$session        s,
       v$libcache_locks l,
       x$kglob          o,
       v$session        b
where  s.saddr = l.holding_user_session
and    o.kglhdadr = l.object_handle
and    o.kglnaown = 'DEMO5'
and    (l.mode_held in (2, 3) or l.mode_requested in (2, 3))
and    b.sid(+) = s.blocking_session
order  by action,
          object_type,
          object_name;
                                                      
                                                      
*****************************************    
--http://ksun-oracle.blogspot.com/2011/11/oracle-11gr2-single-session-library.html

                                                      select (select kglnaobj||'('||kglobtyd||')' 
          from x$kglob v 
         where kglhdadr = object_handle and rownum=1) kglobj_name
       ,v.*
from v$libcache_locks v
where v.holding_user_session  = 
         (select saddr from v$session 
           where event ='library cache pin' and rownum = 1)
  and object_handle in (select object_handle from v$libcache_locks where mode_requested !=0)
order by kglobj_name, holding_user_session, type, mode_held, mode_requested;

************************
Tanel Poders kglpn.sql (TPT_public.zip) 
************************
                                                      
                                                      

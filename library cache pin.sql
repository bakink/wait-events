--https://sites.google.com/site/embtdbo/wait-event-documentation/oracle-library-cache#TOC-library-cache-pin
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

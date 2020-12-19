--https://sites.google.com/site/embtdbo/wait-event-documentation/oracle-latch-cache-buffers-chains
--From ASH data this is fairly easy:

select 
      count(*), 
      sql_id, 
      nvl(o.object_name,ash.current_obj#) objn,
      substr(o.object_type,0,10) otype,
      CURRENT_FILE# fn,
      CURRENT_BLOCK# blockn
from  v$active_session_history ash
    , all_objects o
where event like 'latch: cache buffers chains'
  and o.object_id (+)= ash.CURRENT_OBJ#
group by sql_id, current_obj#, current_file#,
               current_block#, o.object_name,o.object_type
order by count(*)
/       

--We can investigate further to get more information by looking at P1, P2 and P3 for the CBC latch wait. How can we find out what P1, P2 and P3 mean? by looking them up in V$EVENT_NAME:

select * from v$event_name
where name = 'latch: cache buffers chains'

So  P1 is the address of the latch for the cbc latch wait. 
Now we can group the CBC latch waits by the address and find out what address had the most waits:

select
    count(*),
    lpad(replace(to_char(p1,'XXXXXXXXX'),' ','0'),16,0) laddr
from v$active_session_history
where event='latch: cache buffers chains'
group by p1
order by count(*);  

In this case, there is only one address that we had waits for, so now we can look up what blocks (headers actually) were at that address

select o.name, bh.dbarfil, bh.dbablk, bh.tch
from x$bh bh, obj$ o
where tch > 5
  and hladdr='00000004D8108330'
  and o.obj#=bh.obj
order by tch

n the case where the CBC latch contention is happening right now we can run all of this analysis in one query

select 
        name, file#, dbablk, obj, tch, hladdr 
from x$bh bh
    , obj$ o
 where 
       o.obj#(+)=bh.obj and
      hladdr in 
(
    select ltrim(to_char(p1,'XXXXXXXXXX') )
    from v$active_session_history 
    where event like 'latch: cache buffers chains'
    group by p1 
    having count(*) > 5
)
   and tch > 5
order by tch 

Using Tanel's ideas here's a script to get the objects that we have the most cbc latch waits on

col object_name for a35
col cnt for 99999

SELECT
  cnt, object_name, object_type,file#, dbablk, obj, tch, hladdr 
FROM (
  select count(*) cnt, rfile, block from (
    SELECT /*+ ORDERED USE_NL(l.x$ksuprlat) */ 
      --l.laddr, u.laddr, u.laddrx, u.laddrr,
      dbms_utility.data_block_address_file(to_number(object,'XXXXXXXX')) rfile,
      dbms_utility.data_block_address_block(to_number(object,'XXXXXXXX')) block
    FROM 
       (SELECT /*+ NO_MERGE */ 1 FROM DUAL CONNECT BY LEVEL <= 100000) s,
       (SELECT ksuprlnm LNAME, ksuprsid sid, ksuprlat laddr,
        TO_CHAR(ksulawhy,'XXXXXXXXXXXXXXXX') object
        FROM x$ksuprlat) l,
       (select  indx, kslednam from x$ksled ) e,
       (SELECT
                    indx
                  , ksusesqh     sqlhash
   , ksuseopc
   , ksusep1r laddr
             FROM x$ksuse) u
    WHERE LOWER(l.Lname) LIKE LOWER('%cache buffers chains%') 
     AND  u.laddr=l.laddr
     AND  u.ksuseopc=e.indx
     AND  e.kslednam like '%cache buffers chains%'
    )
   group by rfile, block
   ) objs, 
     x$bh bh,
     dba_objects o
WHERE 
      bh.file#=objs.rfile
 and  bh.dbablk=objs.block  
 and  o.object_id=bh.obj
order by cnt
;

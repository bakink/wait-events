https://sites.google.com/site/embtdbo/wait-event-documentation/oracle-buffer-busy-wait
How do we find the block class? With a quick query on the ASH data like:
select
       o.object_name obj,
       o.object_type otype,
       ash.SQL_ID,
       w.class
from v$active_session_history ash,
     ( select rownum class#, class from v$waitstat ) w,
      all_objects o
where event='buffer busy waits'
   and w.class#(+)=ash.p3
   and o.object_id (+)= ash.CURRENT_OBJ#
Order by sample_time;
-----
If we find that CLASS=datablock, then we will want more information to diagnose, such as the object type "OTYPE" , object name and what kind of tablespace the object is stored in. The following query provides that information:

set linesize 120
col block_type for a20
col objn for a25
col otype for a15
col filen for 9999
col blockn for 9999999
col obj for a20
col tbs for a10
select
       bbw.cnt,
       bbw.obj,
       bbw.otype,
       bbw.sql_id,
       bbw.block_type,
       nvl(tbs.name,to_char(bbw.p1)) TBS,
       tbs_defs.assm ASSM
from (
    select
       count(*) cnt,
       nvl(object_name,CURRENT_OBJ#) obj,
       o.object_type otype,
       ash.SQL_ID sql_id,
       nvl(w.class,'usn '||to_char(ceil((ash.p3-18)/2))||' '||
                    decode(mod(ash.p3,2),
                         1,'header',
                         0,'block')) block_type,
       --nvl(w.class,to_char(ash.p3)) block_type,
       ash.p1 p1
    from v$active_session_history ash,
        ( select rownum class#, class from v$waitstat ) w,
        all_objects o
    where event='buffer busy waits'
      and w.class#(+)=ash.p3
      and o.object_id (+)= ash.CURRENT_OBJ#
      and ash.session_state='WAITING'
      and ash.sample_time > sysdate - &minutes/(60*24)
      --and w.class# > 18
   group by o.object_name, ash.current_obj#, o.object_type,
         ash.sql_id, w.class, ash.p3, ash.p1
  ) bbw,
    (select   file_id, 
       tablespace_name name
  from dba_data_files
   ) tbs,
    (select
 tablespace_name    NAME,
        extent_management  LOCAL,
        allocation_type    EXTENTS,
        segment_space_management ASSM,
        initial_extent
     from dba_tablespaces 
   ) tbs_defs
  where tbs.file_id(+) = bbw.p1
    and tbs.name=tbs_defs.name
Order by bbw.cnt
/

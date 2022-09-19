break on owner

select
  substr(owner,1,15) owner,
  substr(db_link,1,20) db_link,
  substr(host,1,33) host,
  substr(username,1,15) username,
  created
from all_db_links
order by 1,2;

cle bre


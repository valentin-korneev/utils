prompt create or replace trigger util_ip_range_trg

create or replace trigger util_ip_range_trg
  before insert or update 
  on util_ip_range
  for each row
begin
  if updating('first_ip') or updating('last_ip') or (inserting and :new.first_ip is not null) then
    :new.first_ip_int := Util_IP.StrToInt(:new.first_ip);
    :new.last_ip_int := Util_IP.StrToInt(:new.last_ip);
  elsif updating('first_ip_int') or updating('last_ip') or (inserting and :new.first_ip_int is not null) then
    :new.first_ip := Util_IP.IntToStr(:new.first_ip_int);
    :new.last_ip := Util_IP.IntToStr(:new.last_ip_int);
  end if;
  :new.network_class := case when :new.last_ip_int-:new.first_ip_int < 256/*256^1*/       then 0
                             when :new.last_ip_int-:new.first_ip_int < 65536/*256^2*/     then 1
                             when :new.last_ip_int-:new.first_ip_int < 16777216/*256^3*/  then 2
                             else 3 end;
end;
/
show error
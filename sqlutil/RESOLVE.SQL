var schema        varchar2(20)
var part1         varchar2(20)
var part2         varchar2(20)
var dblink        varchar2(30)
var part1_type    number
var object_number number

exec dbms_utility.name_resolve(upper('&1'),1,:schema,:part1,:part2,:dblink,:part1_type,:object_number)

select
    substr(:schema,1,20) schema,
    substr(:part1,1,20)  part1,
    substr(:part2,1,20)  part2,
    :part1_type          part1_type,
    :object_number       object_number,
    :dblink              dblink
  from dual;

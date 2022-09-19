define extra_where="and (lower(program) like lower('%&1%') or lower(module) like lower('%&1%') or lower(action) like lower('%&1%') or lower(client_info) like lower('%&1%'))"
@Ses.sql

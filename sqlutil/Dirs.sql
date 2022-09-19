col DIRECTORY_PATH for a100
select * from all_directories order by regexp_replace(directory_path, '[\/]', '\');

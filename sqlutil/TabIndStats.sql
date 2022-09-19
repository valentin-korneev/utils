select table_name, num_rows, blocks, empty_blocks, avg_space, chain_cnt, avg_row_len,
  sample_size, last_analyzed,
  avg_space_freelist_blocks, num_freelist_blocks, global_stats, user_stats
from user_tables
order by 1;


select table_name, index_name, num_rows,
  blevel, leaf_blocks, distinct_keys, avg_leaf_blocks_per_key, avg_data_blocks_per_key, clustering_factor,
  sample_size, last_analyzed,
  global_stats, user_stats
from user_indexes
order by 1, 2;

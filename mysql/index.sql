SELECT database_name as schema_name,
    table_name,
    index_name,
    @@GLOBAL.innodb_page_size * stat_value AS size
FROM mysql.innodb_index_stats
WHERE stat_name = 'size'
ORDER BY size DESC;
SELECT table_schema AS schema_name,
    table_name,
    table_rows AS row_estimate,
    data_length AS table_size,
    avg_row_length AS avg_row_size,
    index_length AS index_size,
    engine,
    table_collation
FROM information_schema.tables
WHERE table_type != 'SYSTEM VIEW'
    AND table_schema NOT IN (
        'information_schema',
        'performance_schema',
        'sys',
        'mysql',
        'innodb'
    )
ORDER BY data_length DESC;
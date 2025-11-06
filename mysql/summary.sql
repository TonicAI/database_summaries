WITH
-- base tables with sizes
tables_agg AS (
  SELECT
    t.TABLE_SCHEMA,
    t.TABLE_NAME,
    COALESCE(t.DATA_LENGTH,0)                 AS data_bytes,
    COALESCE(t.INDEX_LENGTH,0)                AS index_bytes,
    COALESCE(t.DATA_LENGTH,0) + COALESCE(t.INDEX_LENGTH,0) AS total_bytes
  FROM information_schema.TABLES t
  WHERE t.TABLE_TYPE = 'BASE TABLE'
    AND t.TABLE_SCHEMA NOT IN ('mysql','information_schema','performance_schema','sys')
),

-- per-schema size & table counts
schema_sizes AS (
  SELECT
    TABLE_SCHEMA,
    COUNT(*)                         AS num_tables,
    SUM(total_bytes)                 AS total_size_bytes,
    SUM(index_bytes)                 AS total_index_bytes
  FROM tables_agg
  GROUP BY TABLE_SCHEMA
),

-- per-schema column counts
schema_columns AS (
  SELECT
    c.TABLE_SCHEMA,
    COUNT(*) AS num_columns
  FROM information_schema.COLUMNS c
  WHERE c.TABLE_SCHEMA NOT IN ('mysql','information_schema','performance_schema','sys')
  GROUP BY c.TABLE_SCHEMA
),

-- per-schema foreign key counts (one row per FK constraint)
schema_fks AS (
  SELECT
    rc.CONSTRAINT_SCHEMA AS TABLE_SCHEMA,
    COUNT(*)             AS num_foreign_keys
  FROM information_schema.REFERENTIAL_CONSTRAINTS rc
  WHERE rc.CONSTRAINT_SCHEMA NOT IN ('mysql','information_schema','performance_schema','sys')
  GROUP BY rc.CONSTRAINT_SCHEMA
),

-- per-schema index counts (count distinct index names per table, including PRIMARY)
schema_indexes AS (
  SELECT
    s.TABLE_SCHEMA,
    COUNT(DISTINCT CONCAT(s.TABLE_SCHEMA, '.', s.TABLE_NAME, '.', s.INDEX_NAME)) AS num_indexes
  FROM information_schema.STATISTICS s
  WHERE s.TABLE_SCHEMA NOT IN ('mysql','information_schema','performance_schema','sys')
  GROUP BY s.TABLE_SCHEMA
),

-- largest table per schema (by total_bytes)
largest_table AS (
  SELECT
    ta.TABLE_SCHEMA,
    ta.TABLE_NAME  AS largest_table,
    ta.total_bytes AS largest_table_bytes,
    ROW_NUMBER() OVER (PARTITION BY ta.TABLE_SCHEMA ORDER BY ta.total_bytes DESC) AS rn
  FROM tables_agg ta
)

SELECT
  sz.TABLE_SCHEMA                                      AS schema_name,
  ROUND(COALESCE(sz.total_size_bytes,0)/1024/1024, 2)  AS total_size_mb,
  ROUND(COALESCE(sz.total_index_bytes,0)/1024/1024,2)  AS total_index_size_mb,
  COALESCE(sz.num_tables,0)                            AS tables,
  COALESCE(sc.num_columns,0)                           AS columns,
  COALESCE(sf.num_foreign_keys,0)                      AS foreign_keys,
  COALESCE(si.num_indexes,0)                           AS indexes,
  lt.largest_table,
  ROUND(COALESCE(lt.largest_table_bytes,0)/1024/1024,2) AS largest_table_size_mb
FROM schema_sizes sz
LEFT JOIN schema_columns sc ON sc.TABLE_SCHEMA = sz.TABLE_SCHEMA
LEFT JOIN schema_fks     sf ON sf.TABLE_SCHEMA = sz.TABLE_SCHEMA
LEFT JOIN schema_indexes si ON si.TABLE_SCHEMA = sz.TABLE_SCHEMA
LEFT JOIN largest_table  lt ON lt.TABLE_SCHEMA = sz.TABLE_SCHEMA AND lt.rn = 1
ORDER BY sz.total_size_bytes DESC;

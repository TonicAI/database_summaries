WITH schemas AS (
  SELECT oid AS nspid, nspname
  FROM pg_namespace
  WHERE nspname NOT IN ('pg_toast','pg_catalog','information_schema')
),
tables AS (
  SELECT n.nspname, c.oid AS relid, c.relname
  FROM pg_class c
  JOIN pg_namespace n ON n.oid = c.relnamespace
  WHERE c.relkind IN ('r','p')                   -- ordinary + partitioned tables
    AND n.nspname NOT IN ('pg_toast','pg_catalog','information_schema')
),
agg AS (
  SELECT t.nspname,
         COUNT(*)                                  AS num_tables,
         SUM(pg_total_relation_size(t.relid))      AS total_size_bytes,
         SUM(pg_indexes_size(t.relid))             AS total_index_bytes,
         MAX(pg_total_relation_size(t.relid))      AS max_table_size_bytes
  FROM tables t
  GROUP BY t.nspname
),
cols AS (
  SELECT t.nspname,
         COUNT(*) AS num_columns
  FROM tables t
  JOIN pg_attribute a
    ON a.attrelid = t.relid
   AND a.attnum > 0
   AND NOT a.attisdropped
  GROUP BY t.nspname
),
fks AS (
  SELECT t.nspname,
         COUNT(*) AS num_foreign_keys
  FROM tables t
  JOIN pg_constraint c
    ON c.conrelid = t.relid
   AND c.contype = 'f'
  GROUP BY t.nspname
),
idxs AS (
  SELECT t.nspname,
         COUNT(DISTINCT i.indexrelid) AS num_indexes
  FROM tables t
  JOIN pg_index i
    ON i.indrelid = t.relid
  GROUP BY t.nspname
),
largest_table AS (
  SELECT DISTINCT ON (t.nspname)
         t.nspname,
         t.relname AS largest_table,
         pg_total_relation_size(t.relid) AS size_bytes
  FROM tables t
  ORDER BY t.nspname, size_bytes DESC
)
SELECT s.nspname                                        AS schema,
       pg_size_pretty(COALESCE(a.total_size_bytes,0))   AS total_size,
       pg_size_pretty(COALESCE(a.total_index_bytes,0))  AS total_index_size,
       pg_size_pretty(COALESCE(a.max_table_size_bytes,0)) AS largest_table_size,
       lt.largest_table,
       COALESCE(a.num_tables,0)                         AS tables,
       COALESCE(c.num_columns,0)                        AS columns,
       COALESCE(f.num_foreign_keys,0)                   AS foreign_keys,
       COALESCE(i.num_indexes,0)                        AS indexes
FROM schemas s
LEFT JOIN agg  a ON a.nspname = s.nspname
LEFT JOIN cols c ON c.nspname = s.nspname
LEFT JOIN fks  f ON f.nspname = s.nspname
LEFT JOIN idxs i ON i.nspname = s.nspname
LEFT JOIN largest_table lt ON lt.nspname = s.nspname
ORDER BY COALESCE(a.total_size_bytes,0) DESC;

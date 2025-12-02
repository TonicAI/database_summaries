/* Schema-level storage & relationship summary (Oracle) */
WITH
-- Table data bytes (handles non-partitioned + partitioned)
tbl_bytes AS (
  /* non-partitioned tables */
  SELECT t.owner, t.table_name, SUM(s.bytes) AS bytes
  FROM   dba_tables t
  JOIN   dba_segments s
         ON s.owner = t.owner
        AND s.segment_name = t.table_name
        AND s.segment_type = 'TABLE'
  GROUP BY t.owner, t.table_name
  UNION ALL
  /* partitioned tables (sum partitions/subpartitions) */
  SELECT p.table_owner AS owner, p.table_name, SUM(s.bytes) AS bytes
  FROM   dba_tab_partitions p
  JOIN   dba_segments s
         ON s.owner = p.table_owner
        AND s.segment_name = p.partition_name
        AND s.segment_type IN ('TABLE PARTITION','TABLE SUBPARTITION')
  GROUP BY p.table_owner, p.table_name
),
-- LOB data + LOB index bytes mapped to their base tables (handles partitions)
lob_bytes AS (
  /* LOB data segments */
  SELECT l.owner, l.table_name, SUM(s.bytes) AS bytes
  FROM   dba_lobs l
  JOIN   dba_segments s
         ON s.owner = l.owner
        AND s.segment_name = l.segment_name
        AND s.segment_type IN ('LOBSEGMENT','LOB PARTITION')
  GROUP BY l.owner, l.table_name
  UNION ALL
  /* LOB index segments */
  SELECT l.owner, l.table_name, SUM(s.bytes) AS bytes
  FROM   dba_lobs l
  JOIN   dba_segments s
         ON s.owner = l.owner
        AND s.segment_name = l.index_name
        AND s.segment_type IN ('LOBINDEX','LOBINDEX PARTITION')
  GROUP BY l.owner, l.table_name
),
-- Index bytes mapped back to base tables (handles partitioned indexes)
idx_bytes AS (
  SELECT i.table_owner AS owner, i.table_name, SUM(s.bytes) AS bytes
  FROM   dba_indexes i
  JOIN   dba_segments s
         ON s.owner = i.owner
        AND s.segment_name = i.index_name
        AND s.segment_type IN ('INDEX','INDEX PARTITION','INDEX SUBPARTITION')
  GROUP BY i.table_owner, i.table_name
),
-- Per-table total footprint = table data + LOBs + indexes
table_totals AS (
  SELECT
    t.owner,
    t.table_name,
    NVL(tb.bytes,0)
    + NVL(lb.bytes,0)
    + NVL(ib.bytes,0) AS total_bytes
  FROM  dba_tables t
  LEFT  JOIN (
    SELECT owner, table_name, SUM(bytes) AS bytes
    FROM   tbl_bytes
    GROUP  BY owner, table_name
  ) tb ON tb.owner = t.owner AND tb.table_name = t.table_name
  LEFT  JOIN (
    SELECT owner, table_name, SUM(bytes) AS bytes
    FROM   lob_bytes
    GROUP  BY owner, table_name
  ) lb ON lb.owner = t.owner AND lb.table_name = t.table_name
  LEFT  JOIN (
    SELECT owner, table_name, SUM(bytes) AS bytes
    FROM   idx_bytes
    GROUP  BY owner, table_name
  ) ib ON ib.owner = t.owner AND ib.table_name = t.table_name
),
-- Largest table per schema
largest_per_schema AS (
  SELECT owner,
         table_name AS largest_table,
         total_bytes,
         ROW_NUMBER() OVER (PARTITION BY owner ORDER BY total_bytes DESC NULLS LAST) AS rn
  FROM   table_totals
),
-- Aggregate counts/sizes per schema
schema_agg AS (
  SELECT
    t.owner,
    COUNT(*) AS num_tables,
    SUM(t.total_bytes) AS total_size_bytes
  FROM table_totals t
  GROUP BY t.owner
),
schema_cols AS (
  SELECT owner, COUNT(*) AS num_columns
  FROM   dba_tab_columns
  GROUP  BY owner
),
schema_fks AS (
  SELECT owner, COUNT(*) AS num_foreign_keys
  FROM   dba_constraints
  WHERE  constraint_type = 'R'
  GROUP  BY owner
),
schema_idxs AS (
  SELECT owner, COUNT(*) AS num_indexes
  FROM   dba_indexes
  GROUP  BY owner
),
schema_idx_bytes AS (
  SELECT i.table_owner AS owner, SUM(s.bytes) AS total_index_bytes
  FROM   dba_indexes i
  JOIN   dba_segments s
         ON s.owner = i.owner
        AND s.segment_name = i.index_name
        AND s.segment_type IN ('INDEX','INDEX PARTITION','INDEX SUBPARTITION')
  GROUP  BY i.table_owner
)
SELECT
  sa.owner                                      AS schema,
  -- total size includes table data + LOBs + indexes (sum of per-table totals)
  ROUND(NVL(sa.total_size_bytes,0)/1024/1024,2) AS total_size_mb,
  ROUND(NVL(sib.total_index_bytes,0)/1024/1024,2) AS total_index_size_mb,
  sa.num_tables                                 AS tables,
  NVL(sc.num_columns,0)                         AS columns,
  NVL(sf.num_foreign_keys,0)                    AS foreign_keys,
  NVL(si.num_indexes,0)                         AS indexes,
  lp.largest_table,
  ROUND(NVL(lp.total_bytes,0)/1024/1024,2)      AS largest_table_size_mb
FROM schema_agg sa
LEFT JOIN schema_cols sc      ON sc.owner = sa.owner
LEFT JOIN schema_fks  sf      ON sf.owner = sa.owner
LEFT JOIN schema_idxs si      ON si.owner = sa.owner
LEFT JOIN schema_idx_bytes sib ON sib.owner = sa.owner
LEFT JOIN (
  SELECT owner, largest_table, total_bytes
  FROM   largest_per_schema
  WHERE  rn = 1
) lp ON lp.owner = sa.owner
-- Optional: hide system schemas
WHERE sa.owner NOT IN ('SYS','SYSTEM','XDB','CTXSYS','MDSYS','ORDSYS','ORDDATA',
                       'DBSNMP','OUTLN','WMSYS','APPQOSSYS','ANONYMOUS','SI_INFORMTN_SCHEMA',
                       'GSMADMIN_INTERNAL','OJVMSYS','AUDSYS')
ORDER BY sa.total_size_bytes DESC NULLS LAST;

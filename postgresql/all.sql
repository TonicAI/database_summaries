WITH RECURSIVE pg_inherit(inhrelid, inhparent) AS (
    SELECT inhrelid,
        inhparent
    FROM pg_inherits
    UNION
    SELECT child.inhrelid,
        parent.inhparent
    FROM pg_inherit child,
        pg_inherits parent
    WHERE child.inhparent = parent.inhrelid
),
pg_inherit_short AS (
    SELECT *
    FROM pg_inherit
    WHERE inhparent NOT IN (
            SELECT inhrelid
            FROM pg_inherit
        )
)
SELECT schema,
    name,
    (
        SELECT CASE
                WHEN kind = 'r' THEN 'table'
                WHEN kind = 'i' THEN 'index'
                WHEN kind = 'S' THEN 'sequence'
                WHEN kind = 't' THEN 'TOAST table'
                WHEN kind = 'v' THEN 'view'
                WHEN kind = 'm' THEN 'materialized view'
                WHEN kind = 'c' THEN 'composite type'
                WHEN kind = 'f' THEN 'foreign table'
                WHEN kind = 'p' THEN 'partitioned table'
                WHEN kind = 'I' THEN 'partitioned index'
                ELSE 'Unexpected relkind ' || kind
            END
    ) AS kind,
    row_estimate,
    pg_size_pretty(total_bytes) AS total,
    pg_size_pretty(index_bytes) AS INDEX,
    pg_size_pretty(toast_bytes) AS toast,
    pg_size_pretty(table_bytes) AS "self",
    (
        SELECT CASE
                WHEN row_estimate = 0 THEN '-'
                ELSE pg_size_pretty(ceil(total_bytes / row_estimate)::bigint)
            END
    ) AS "avg_row_size"
FROM (
        SELECT *,
            total_bytes - index_bytes - COALESCE(toast_bytes, 0) AS table_bytes
        FROM (
                SELECT c.oid,
                    nspname AS schema,
                    relname AS name,
                    relkind AS kind,
                    SUM(c.reltuples) OVER (PARTITION BY parent) AS row_estimate,
                    SUM(pg_total_relation_size(c.oid)) OVER (PARTITION BY parent) AS total_bytes,
                    SUM(pg_indexes_size(c.oid)) OVER (PARTITION BY parent) AS index_bytes,
                    SUM(pg_total_relation_size(reltoastrelid)) OVER (PARTITION BY parent) AS toast_bytes,
                    parent
                FROM (
                        SELECT pg_class.oid,
                            reltuples,
                            relname,
                            relnamespace,
                            relkind,
                            pg_class.reltoastrelid,
                            COALESCE(inhparent, pg_class.oid) parent
                        FROM pg_class
                            LEFT JOIN pg_inherit_short ON inhrelid = oid
                    ) c
                    LEFT JOIN pg_namespace n ON n.oid = c.relnamespace
            ) a
        WHERE oid = parent
            AND schema NOT IN ('information_schema', 'repack', 'aiven_extras')
            AND schema NOT LIKE 'aws_%'
            AND schema NOT LIKE 'pg_%'
    ) a
ORDER BY total_bytes DESC,
    schema,
    name;
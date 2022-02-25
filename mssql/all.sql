SELECT [schema_name] = s.[name],
    [table_name] = t.[name],
    [index_name] = IIF(i.[type] IN (0, 1, 5), NULL, i.[name]) -- 0=Heap; 1=Clustered; 5=Clustered Columnstore
,
    [object_type] = IIF(i.[type] IN (0, 1, 5), 'TABLE', 'INDEX'),
    [index_type] = i.[type_desc],
    [partition_count] = p.partition_count,
    [row_count] = p.[rows],
    [avg_row_size] = (
        SELECT IIF(
                p.[rows] = 0,
                0,
                au.used_pages * (8 * 1024) / p.[rows]
            )
    ),
    [data_compression] = IIF(
        p.data_compression_cnt > 1,
        'Mixed',
        (
            SELECT DISTINCT p.data_compression_desc
            FROM sys.partitions p
            WHERE i.[object_id] = p.[object_id]
                AND i.index_id = p.index_id
        )
    ),
    [total_space] = au.total_pages * (8 * 1024),
    [used_space] = au.used_pages * (8 * 1024),
    [unused_space] = (au.total_pages - au.used_pages) * (8 * 1024)
FROM sys.schemas s
    JOIN sys.tables t ON s.schema_id = t.schema_id
    JOIN sys.indexes i ON t.object_id = i.object_id
    JOIN (
        SELECT [object_id],
            index_id,
            partition_count = COUNT(*),
            [rows] = sum([rows]),
            data_compression_cnt = COUNT(DISTINCT [data_compression])
        FROM sys.partitions
        GROUP BY [object_id],
            [index_id]
    ) p ON i.[object_id] = p.[object_id]
    AND i.[index_id] = p.[index_id]
    JOIN (
        SELECT p.[object_id],
            p.[index_id],
            total_pages = sum(a.total_pages),
            used_pages = sum(a.used_pages),
            data_pages = sum(a.data_pages)
        FROM sys.partitions p
            JOIN sys.allocation_units a ON p.[partition_id] = a.[container_id]
        GROUP BY p.[object_id],
            p.[index_id]
    ) au ON i.[object_id] = au.[object_id]
    AND i.[index_id] = au.[index_id]
WHERE t.is_ms_shipped = 0 -- Not a system table
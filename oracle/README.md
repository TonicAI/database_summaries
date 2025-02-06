# README: Oracle Database Schema Table Size Query

## Overview
This SQL query calculates the total storage size (in gigabytes) used by tables and related segments within each schema in an Oracle database. It aggregates the storage consumption of various segment types to provide a comprehensive view of the schema sizes.

## Usage
- Run this query in an Oracle database as a user with access to `DBA_SEGMENTS` and `DBA_LOBS`.

## Expected Output
```plaintext
| SCHEMA_NAME | TABLE_SIZE (GB) |
|-------------|----------------|
| HR          | 12.3           |
| FINANCE     | 45.8           |
| SALES       | 89.2           |
```

## Notes
- The query may require DBA privileges to access the `DBA_SEGMENTS` and `DBA_LOBS` views.
- For finer granularity, consider modifying the query to show storage at the table level rather than the schema level.



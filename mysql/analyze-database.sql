SET @old_innodb_stats_on_metadata = @@global.innodb_stats_on_metadata;
SET GLOBAL innodb_stats_on_metadata = 'ON';
SHOW TABLE STATUS;
SET GLOBAL innodb_stats_on_metadata = @old_innodb_stats_on_metadata;
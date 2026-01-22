# PGD/BDR Configuration

## BDR Group Configuration

### Creating a BDR Group

#### First Node (Bootstrap)

```sql
SELECT bdr.bdr_group_create(
    local_node_name := 'node1',
    node_external_dsn := 'host=node1.example.com port=5432 dbname=mydb user=bdr_user password=pass'
);
```

**Parameters:**
- `local_node_name`: Unique name for this node
- `node_external_dsn`: Connection string other nodes use to connect

#### Adding Nodes to Group

```sql
SELECT bdr.bdr_group_join(
    local_node_name := 'node2',
    node_external_dsn := 'host=node2.example.com port=5432 dbname=mydb user=bdr_user password=pass',
    join_using_dsn := 'host=node1.example.com port=5432 dbname=mydb user=bdr_user password=pass'
);
```

**Parameters:**
- `local_node_name`: Unique name for new node
- `node_external_dsn`: Connection string for new node
- `join_using_dsn`: Connection string to existing node

## Table Replication Configuration

### Enable Replication for Tables

By default, tables are **not** automatically replicated. You must explicitly add them:

```sql
-- Add a single table
SELECT bdr.table_add('schema_name.table_name');

-- Add all tables in a schema
SELECT bdr.schema_add('schema_name');

-- Add all tables in database (use with caution)
SELECT bdr.database_add();
```

### Exclude Tables from Replication

```sql
-- Remove table from replication
SELECT bdr.table_remove('schema_name.table_name');
```

### Check Replicated Tables

```sql
-- List all replicated tables
SELECT * FROM bdr.bdr_replication_sets;

-- Check table replication status
SELECT schemaname, tablename, replicate 
FROM bdr.bdr_tables;
```

## Replication Configuration Options

### Asynchronous Replication (Default)

No additional configuration needed. Writes commit locally first.

### Synchronous Replication

Configure synchronous commit:

```sql
-- Set synchronous replication
ALTER SYSTEM SET synchronous_commit = 'on';
ALTER SYSTEM SET synchronous_standby_names = 'ANY 2 (node2, node3)';

-- Reload configuration
SELECT pg_reload_conf();
```

**Options:**
- `ANY N (node1, node2, ...)`: Wait for N nodes from list
- `FIRST N (node1, node2, ...)`: Wait for first N nodes in order

## Conflict Resolution Configuration

### Set Conflict Resolution Policy

```sql
-- Set policy for a table
SELECT bdr.table_set_conflict_resolution(
    'schema_name.table_name',
    'last_update_wins'  -- or 'first_update_wins', 'accept_local', 'accept_remote'
);
```

### Available Policies

1. **last_update_wins**: Most recent timestamp wins
   - Requires timestamp column
   - Default: `updated_at` or `last_modified`

2. **first_update_wins**: First update wins (opposite of last_update_wins)

3. **accept_local**: Local changes always win

4. **accept_remote**: Remote changes always win

5. **custom**: Write custom conflict handler function

### Custom Conflict Handler

```sql
CREATE OR REPLACE FUNCTION my_conflict_handler(
    local_tuple RECORD,
    remote_tuple RECORD,
    conflict_type TEXT
) RETURNS RECORD AS $$
BEGIN
    -- Custom logic here
    -- Return the tuple to keep
    RETURN local_tuple;  -- or remote_tuple
END;
$$ LANGUAGE plpgsql;

-- Apply custom handler
SELECT bdr.table_set_conflict_resolution(
    'schema_name.table_name',
    'custom',
    'my_conflict_handler'
);
```

## DDL Replication Configuration

DDL replication is enabled by default. Configure what gets replicated:

```sql
-- Enable/disable DDL replication globally
ALTER SYSTEM SET bdr.ddl_replication = 'on';  -- or 'off'

-- Reload configuration
SELECT pg_reload_conf();
```

### DDL Replication Scope

- **Enabled by default**: CREATE, ALTER, DROP for tables, indexes, views
- **Automatic**: Schema changes propagate to all nodes
- **Ordered**: DDL changes applied in same order on all nodes

## Performance Tuning

### Replication Workers

```sql
-- Increase replication workers
ALTER SYSTEM SET max_worker_processes = 20;
ALTER SYSTEM SET max_logical_replication_workers = 10;

-- Reload
SELECT pg_reload_conf();
```

### WAL Settings

```sql
-- Increase WAL size (reduce checkpoints)
ALTER SYSTEM SET max_wal_size = '2GB';
ALTER SYSTEM SET min_wal_size = '1GB';

-- WAL compression (reduce network traffic)
ALTER SYSTEM SET wal_compression = 'on';
```

### Network Optimization

```sql
-- Enable compression for replication
ALTER SYSTEM SET bdr.replication_compression = 'on';
```

## Monitoring Configuration

### Enable Conflict Logging

```sql
-- Log all conflicts
ALTER SYSTEM SET bdr.log_conflicts = 'on';

-- View conflict log
SELECT * FROM bdr.bdr_conflict_history;
```

### Replication Lag Monitoring

```sql
-- Check replication lag per node
SELECT 
    node_name,
    replication_lag,
    replication_lag_bytes
FROM bdr.bdr_node_status();
```

## Security Configuration

### SSL/TLS for Replication

Configure SSL in `postgresql.conf`:

```ini
ssl = on
ssl_cert_file = 'server.crt'
ssl_key_file = 'server.key'
ssl_ca_file = 'ca.crt'
```

Update connection strings to use SSL:

```sql
-- Update node DSN with SSL
SELECT bdr.bdr_node_set_dsn(
    'node2',
    'host=node2.example.com port=5432 dbname=mydb user=bdr_user sslmode=require'
);
```

## Maintenance Configuration

### Vacuum and Analyze

Configure automatic maintenance:

```sql
-- Enable autovacuum (recommended)
ALTER SYSTEM SET autovacuum = 'on';

-- Tune autovacuum for replication
ALTER SYSTEM SET autovacuum_max_workers = 4;
```

### Backup Configuration

BDR works with standard PostgreSQL backup tools:

- **pg_basebackup**: Physical backup
- **pg_dump**: Logical backup
- **Continuous archiving**: WAL archiving

## Configuration Best Practices

1. **Start with async**: Use asynchronous replication initially
2. **Add sync selectively**: Enable sync only where needed
3. **Monitor conflicts**: Enable conflict logging
4. **Tune workers**: Adjust based on workload
5. **Use compression**: Reduce network traffic
6. **SSL for production**: Always use SSL in production
7. **Regular backups**: Backup all nodes regularly

## Next Steps

- **Topic 05**: Conflict resolution in detail
- **Topic 06**: Monitoring and troubleshooting


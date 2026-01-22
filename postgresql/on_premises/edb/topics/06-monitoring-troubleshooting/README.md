# Monitoring and Troubleshooting PGD/BDR

## Monitoring BDR Status

### Check Node Status

```sql
-- View all nodes in BDR group
SELECT 
    node_name,
    node_status,
    node_dsn,
    node_group_name
FROM bdr.bdr_nodes;

-- Detailed node status
SELECT * FROM bdr.bdr_node_status();
```

### Check Replication Status

```sql
-- Replication slots status
SELECT 
    slot_name,
    plugin,
    slot_type,
    active,
    restart_lsn,
    confirmed_flush_lsn
FROM pg_replication_slots;

-- BDR-specific replication info
SELECT * FROM bdr.bdr_replication_slots;
```

### Monitor Replication Lag

```sql
-- Replication lag per node
SELECT 
    node_name,
    replication_lag,
    replication_lag_bytes,
    replication_lag_time
FROM bdr.bdr_node_status();

-- Detailed lag information
SELECT 
    slot_name,
    pg_size_pretty(pg_wal_lsn_diff(pg_current_wal_lsn(), restart_lsn)) AS lag_bytes,
    EXTRACT(EPOCH FROM (now() - pg_last_xact_replay_timestamp())) AS lag_seconds
FROM pg_replication_slots;
```

## Monitoring Conflicts

### View Conflict History

```sql
-- Recent conflicts
SELECT 
    conflict_time,
    table_name,
    conflict_type,
    local_tuple,
    remote_tuple,
    resolution
FROM bdr.bdr_conflict_history
ORDER BY conflict_time DESC
LIMIT 50;

-- Conflict count by table
SELECT 
    table_name,
    COUNT(*) AS conflict_count
FROM bdr.bdr_conflict_history
WHERE conflict_time > NOW() - INTERVAL '24 hours'
GROUP BY table_name
ORDER BY conflict_count DESC;
```

### Conflict Rate Monitoring

```sql
-- Conflicts per hour
SELECT 
    DATE_TRUNC('hour', conflict_time) AS hour,
    COUNT(*) AS conflicts
FROM bdr.bdr_conflict_history
WHERE conflict_time > NOW() - INTERVAL '7 days'
GROUP BY hour
ORDER BY hour DESC;
```

## Performance Monitoring

### Replication Worker Status

```sql
-- Active replication workers
SELECT 
    pid,
    usename,
    application_name,
    state,
    sync_state,
    sync_priority
FROM pg_stat_replication;
```

### WAL Statistics

```sql
-- WAL generation rate
SELECT 
    pg_size_pretty(pg_wal_lsn_diff(pg_current_wal_lsn(), '0/0')) AS total_wal_size;

-- Check WAL disk usage
SELECT 
    pg_size_pretty(sum(size)) AS total_size
FROM pg_ls_waldir();
```

### Table Replication Status

```sql
-- Check which tables are replicated
SELECT 
    schemaname,
    tablename,
    replicate
FROM bdr.bdr_tables
ORDER BY schemaname, tablename;
```

## Common Issues and Troubleshooting

### Issue 1: Replication Lag

**Symptoms:**
- High `replication_lag` values
- Data not appearing on remote nodes
- Increasing lag over time

**Diagnosis:**
```sql
-- Check lag
SELECT * FROM bdr.bdr_node_status();

-- Check worker status
SELECT * FROM pg_stat_replication;

-- Check for stuck transactions
SELECT * FROM pg_stat_activity WHERE state = 'active';
```

**Solutions:**
1. **Increase workers:**
   ```sql
   ALTER SYSTEM SET max_logical_replication_workers = 10;
   SELECT pg_reload_conf();
   ```

2. **Check network:**
   ```bash
   # Test connectivity
   telnet remote_node 5432
   ```

3. **Check disk I/O:**
   ```sql
   -- Check for I/O wait
   SELECT * FROM pg_stat_database;
   ```

### Issue 2: Replication Slot Lag

**Symptoms:**
- WAL files accumulating
- Disk space issues
- Replication slots not advancing

**Diagnosis:**
```sql
-- Check slot lag
SELECT 
    slot_name,
    pg_size_pretty(pg_wal_lsn_diff(pg_current_wal_lsn(), restart_lsn)) AS lag
FROM pg_replication_slots;
```

**Solutions:**
1. **Check if slot is active:**
   ```sql
   SELECT slot_name, active FROM pg_replication_slots;
   ```

2. **Restart replication:**
   - May need to restart PostgreSQL
   - Or drop and recreate slot (careful!)

3. **Increase WAL retention:**
   ```sql
   ALTER SYSTEM SET max_wal_size = '4GB';
   ```

### Issue 3: Conflicts Not Resolving

**Symptoms:**
- Conflicts in conflict log
- Data inconsistencies
- Application errors

**Diagnosis:**
```sql
-- Check conflict resolution policy
SELECT 
    schemaname,
    tablename,
    conflict_resolution
FROM bdr.bdr_tables
WHERE replicate = true;

-- Check recent conflicts
SELECT * FROM bdr.bdr_conflict_history
ORDER BY conflict_time DESC
LIMIT 20;
```

**Solutions:**
1. **Verify policy is set:**
   ```sql
   SELECT bdr.table_set_conflict_resolution('schema.table', 'last_update_wins');
   ```

2. **Check timestamp column:**
   ```sql
   -- Ensure updated_at is being updated
   SELECT column_name, data_type 
   FROM information_schema.columns 
   WHERE table_name = 'your_table';
   ```

3. **Review conflict patterns:**
   - Identify which tables have most conflicts
   - Consider data partitioning
   - Adjust conflict resolution policy

### Issue 4: Node Cannot Join Group

**Symptoms:**
- `bdr_group_join` fails
- Connection errors
- Authentication failures

**Diagnosis:**
```bash
# Test connectivity
psql -h remote_node -U bdr_user -d mydb

# Check PostgreSQL logs
tail -f /var/log/postgresql/postgresql.log
```

**Solutions:**
1. **Verify network connectivity:**
   ```bash
   telnet remote_node 5432
   ```

2. **Check pg_hba.conf:**
   ```
   host    replication     bdr_user     node_ip/32    md5
   ```

3. **Verify user exists:**
   ```sql
   SELECT usename FROM pg_user WHERE usename = 'bdr_user';
   ```

4. **Check PostgreSQL is running:**
   ```bash
   systemctl status postgresql
   ```

### Issue 5: DDL Not Replicating

**Symptoms:**
- Schema changes on one node don't appear on others
- Table structure differs between nodes

**Diagnosis:**
```sql
-- Check DDL replication setting
SHOW bdr.ddl_replication;

-- Compare table structures
\d+ schema.table_name  -- On each node
```

**Solutions:**
1. **Enable DDL replication:**
   ```sql
   ALTER SYSTEM SET bdr.ddl_replication = 'on';
   SELECT pg_reload_conf();
   ```

2. **Manually apply DDL:**
   - If DDL replication was off, apply manually to all nodes
   - Keep nodes in sync

## Monitoring Queries

### Health Check Query

```sql
-- Comprehensive health check
SELECT 
    'Nodes' AS check_type,
    COUNT(*) AS count,
    COUNT(*) FILTER (WHERE node_status = 'active') AS active
FROM bdr.bdr_nodes
UNION ALL
SELECT 
    'Replication Slots',
    COUNT(*),
    COUNT(*) FILTER (WHERE active = true)
FROM pg_replication_slots
UNION ALL
SELECT 
    'Conflicts (24h)',
    COUNT(*),
    NULL
FROM bdr.bdr_conflict_history
WHERE conflict_time > NOW() - INTERVAL '24 hours';
```

### Alert Queries

```sql
-- High replication lag alert (> 1 minute)
SELECT 
    node_name,
    replication_lag_time
FROM bdr.bdr_node_status()
WHERE replication_lag_time > INTERVAL '1 minute';

-- High conflict rate alert (> 10/hour)
SELECT 
    table_name,
    COUNT(*) AS conflicts
FROM bdr.bdr_conflict_history
WHERE conflict_time > NOW() - INTERVAL '1 hour'
GROUP BY table_name
HAVING COUNT(*) > 10;
```

## Logging Configuration

### Enable Detailed Logging

```postgresql
# postgresql.conf
log_min_messages = 'info'
log_line_prefix = '%t [%p]: [%l-1] user=%u,db=%d,app=%a,client=%h '
log_checkpoints = on
log_connections = on
log_disconnections = on
log_duration = on
log_statement = 'ddl'  # Log DDL statements
```

### BDR-Specific Logging

```sql
-- Enable conflict logging
ALTER SYSTEM SET bdr.log_conflicts = 'on';

-- Enable replication logging
ALTER SYSTEM SET log_replication_commands = 'on';
```

## Performance Tuning

### Identify Slow Replication

```sql
-- Check replication apply time
SELECT 
    pid,
    now() - state_change AS duration,
    query
FROM pg_stat_activity
WHERE application_name LIKE 'bdr%';
```

### Optimize Replication

1. **Increase workers:**
   ```sql
   ALTER SYSTEM SET max_logical_replication_workers = 20;
   ```

2. **Enable compression:**
   ```sql
   ALTER SYSTEM SET bdr.replication_compression = 'on';
   ```

3. **Tune WAL:**
   ```sql
   ALTER SYSTEM SET max_wal_size = '4GB';
   ALTER SYSTEM SET wal_compression = 'on';
   ```

## Next Steps

- **Topic 07**: High availability and failover procedures
- **Topic 08**: Best practices and recommendations


-- BDR Status Monitoring Queries

-- 1. Node Status
SELECT 
    node_name,
    node_status,
    node_dsn,
    node_group_name
FROM bdr.bdr_nodes
ORDER BY node_name;

-- 2. Detailed Node Status
SELECT 
    node_name,
    replication_lag,
    replication_lag_bytes,
    replication_lag_time,
    node_status
FROM bdr.bdr_node_status()
ORDER BY node_name;

-- 3. Replication Slots
SELECT 
    slot_name,
    plugin,
    slot_type,
    active,
    restart_lsn,
    confirmed_flush_lsn,
    pg_size_pretty(pg_wal_lsn_diff(pg_current_wal_lsn(), restart_lsn)) AS lag_bytes
FROM pg_replication_slots
ORDER BY slot_name;

-- 4. Replicated Tables
SELECT 
    schemaname,
    tablename,
    replicate,
    conflict_resolution
FROM bdr.bdr_tables
WHERE replicate = true
ORDER BY schemaname, tablename;

-- 5. Recent Conflicts (last 24 hours)
SELECT 
    conflict_time,
    table_name,
    conflict_type,
    resolution
FROM bdr.bdr_conflict_history
WHERE conflict_time > NOW() - INTERVAL '24 hours'
ORDER BY conflict_time DESC
LIMIT 50;

-- 6. Conflict Summary by Table
SELECT 
    table_name,
    COUNT(*) AS conflict_count,
    MAX(conflict_time) AS last_conflict
FROM bdr.bdr_conflict_history
WHERE conflict_time > NOW() - INTERVAL '7 days'
GROUP BY table_name
ORDER BY conflict_count DESC;

-- 7. Replication Workers
SELECT 
    pid,
    usename,
    application_name,
    state,
    sync_state,
    sync_priority,
    client_addr
FROM pg_stat_replication
ORDER BY application_name;

-- 8. Health Check Summary
SELECT 
    'Nodes' AS metric,
    COUNT(*)::TEXT AS value
FROM bdr.bdr_nodes
WHERE node_status = 'active'
UNION ALL
SELECT 
    'Replication Slots',
    COUNT(*)::TEXT
FROM pg_replication_slots
WHERE active = true
UNION ALL
SELECT 
    'Max Replication Lag (seconds)',
    COALESCE(EXTRACT(EPOCH FROM MAX(replication_lag_time))::TEXT, '0')
FROM bdr.bdr_node_status()
UNION ALL
SELECT 
    'Conflicts (last 24h)',
    COUNT(*)::TEXT
FROM bdr.bdr_conflict_history
WHERE conflict_time > NOW() - INTERVAL '24 hours';


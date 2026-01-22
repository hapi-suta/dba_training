# Best Practices for PGD/BDR

## Design Best Practices

### 1. Data Partitioning

**Partition writes by node to minimize conflicts:**

```sql
-- Example: Partition users by region
-- Node 1: US users (user_id % 4 = 0, 1)
-- Node 2: EU users (user_id % 4 = 2)
-- Node 3: Asia users (user_id % 4 = 3)

-- Application routing
def get_node_for_user(user_id):
    region = get_user_region(user_id)
    return region_to_node[region]
```

**Benefits:**
- Reduces conflicts
- Better performance
- Clearer data ownership

### 2. Use Appropriate Data Types

**Primary Keys:**
- Use UUIDs or sequences (not timestamps)
- Avoid conflicts on inserts

**Timestamps:**
- Always include `updated_at` for `last_update_wins`
- Use `DEFAULT NOW()` and triggers

```sql
CREATE TABLE users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    email TEXT UNIQUE,
    name TEXT,
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW()
);

-- Auto-update trigger
CREATE TRIGGER update_updated_at
    BEFORE UPDATE ON users
    FOR EACH ROW
    EXECUTE FUNCTION update_timestamp();
```

### 3. Schema Design

**Avoid:**
- Tables that change frequently on multiple nodes
- High-conflict scenarios
- Complex foreign key relationships across nodes

**Prefer:**
- Denormalization where appropriate
- Local foreign keys
- Clear data ownership

## Configuration Best Practices

### 1. Start Simple

**Initial Setup:**
- Start with 2-3 nodes
- Use asynchronous replication
- Use `last_update_wins` for most tables
- Monitor and adjust

### 2. Gradual Complexity

**Add complexity as needed:**
1. Start with async replication
2. Add sync replication only where needed
3. Custom conflict handlers only when necessary
4. Optimize based on monitoring

### 3. Network Configuration

**Requirements:**
- Low latency between nodes (< 50ms ideal)
- Sufficient bandwidth
- Reliable connections
- SSL/TLS in production

```sql
-- Use SSL for replication
-- In connection strings:
'sslmode=require'
```

## Conflict Resolution Best Practices

### 1. Default Policy

**Use `last_update_wins` for most tables:**
```sql
-- Apply to all tables by default
DO $$
DECLARE
    tbl RECORD;
BEGIN
    FOR tbl IN 
        SELECT schemaname, tablename 
        FROM bdr.bdr_tables 
        WHERE replicate = true
    LOOP
        BEGIN
            EXECUTE format(
                'SELECT bdr.table_set_conflict_resolution(%L, %L)',
                tbl.schemaname || '.' || tbl.tablename,
                'last_update_wins'
            );
        EXCEPTION WHEN OTHERS THEN
            -- Log error, continue
            RAISE NOTICE 'Failed to set policy for %: %', 
                tbl.tablename, SQLERRM;
        END;
    END LOOP;
END $$;
```

### 2. Timestamp Management

**Always update timestamps:**
```sql
CREATE OR REPLACE FUNCTION update_timestamp()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Apply to all tables
CREATE TRIGGER update_timestamp_trigger
    BEFORE UPDATE ON your_table
    FOR EACH ROW
    EXECUTE FUNCTION update_timestamp();
```

### 3. Conflict Monitoring

**Regular monitoring:**
```sql
-- Daily conflict report
SELECT 
    DATE(conflict_time) AS date,
    table_name,
    COUNT(*) AS conflicts
FROM bdr.bdr_conflict_history
WHERE conflict_time > NOW() - INTERVAL '7 days'
GROUP BY DATE(conflict_time), table_name
ORDER BY date DESC, conflicts DESC;
```

## Performance Best Practices

### 1. Replication Workers

**Tune based on workload:**
```sql
-- Start with defaults, increase if needed
ALTER SYSTEM SET max_logical_replication_workers = 10;
ALTER SYSTEM SET max_worker_processes = 20;
```

### 2. WAL Management

**Optimize WAL settings:**
```sql
-- Increase WAL size to reduce checkpoints
ALTER SYSTEM SET max_wal_size = '4GB';
ALTER SYSTEM SET min_wal_size = '1GB';

-- Enable compression
ALTER SYSTEM SET wal_compression = 'on';
```

### 3. Network Optimization

**Enable compression:**
```sql
ALTER SYSTEM SET bdr.replication_compression = 'on';
```

### 4. Index Management

**Indexes are replicated automatically:**
- Create indexes during low-traffic periods
- Monitor index creation impact
- Use `CREATE INDEX CONCURRENTLY` when possible

## Operational Best Practices

### 1. Monitoring

**Essential metrics:**
- Replication lag
- Conflict rate
- Node status
- Disk space
- WAL usage

**Set up automated checks:**
```sql
-- Create monitoring view
CREATE VIEW bdr_health AS
SELECT 
    (SELECT COUNT(*) FROM bdr.bdr_nodes WHERE node_status = 'active') AS active_nodes,
    (SELECT MAX(replication_lag_time) FROM bdr.bdr_node_status()) AS max_lag,
    (SELECT COUNT(*) FROM bdr.bdr_conflict_history 
     WHERE conflict_time > NOW() - INTERVAL '1 hour') AS conflicts_1h;
```

### 2. Backups

**Backup strategy:**
- Backup all nodes (at least daily)
- Backup most recent node more frequently
- Test restore procedures monthly
- Store backups off-site

### 3. Documentation

**Maintain:**
- Architecture diagrams
- Configuration details
- Runbooks for common tasks
- Recovery procedures
- Contact information

### 4. Testing

**Regular testing:**
- Failover procedures
- Conflict scenarios
- Recovery procedures
- Performance under load

## Security Best Practices

### 1. Authentication

**Use strong passwords:**
```sql
-- Create replication user with strong password
CREATE USER bdr_user WITH REPLICATION PASSWORD 'strong_password_here';
```

### 2. Network Security

**Use SSL/TLS:**
```ini
# postgresql.conf
ssl = on
ssl_cert_file = 'server.crt'
ssl_key_file = 'server.key'
```

**Firewall rules:**
- Only allow replication from known nodes
- Use VPN for cross-region replication

### 3. Access Control

**Limit permissions:**
```sql
-- Replication user only needs replication privilege
GRANT REPLICATION TO bdr_user;

-- Don't grant unnecessary permissions
```

## Application Best Practices

### 1. Connection Management

**Use connection pooling:**
- PgBouncer or similar
- Separate pools for reads/writes
- Monitor connection counts

### 2. Write Routing

**Route writes intelligently:**
```python
def get_write_node(user_id):
    # Route based on data ownership
    region = get_user_region(user_id)
    return region_to_node[region]

def get_read_node():
    # Can read from any node
    return random.choice(active_nodes)
```

### 3. Error Handling

**Handle replication lag:**
```python
# After write, allow time for replication
time.sleep(0.1)  # Or use synchronous replication

# For critical reads, read from same node as write
```

### 4. Conflict Awareness

**Design for conflicts:**
- Understand conflict resolution policies
- Test conflict scenarios
- Monitor conflict rates
- Adjust design if conflicts are high

## Migration Best Practices

### 1. Planning

**Before migration:**
- Understand data access patterns
- Identify high-conflict scenarios
- Plan data partitioning
- Test in staging

### 2. Gradual Rollout

**Phased approach:**
1. Set up BDR cluster
2. Migrate read-only workloads
3. Migrate low-conflict writes
4. Migrate remaining workloads

### 3. Monitoring During Migration

**Watch for:**
- Increased conflicts
- Performance degradation
- Replication lag
- Application errors

## Common Pitfalls to Avoid

### 1. Over-Configuration

**Don't:**
- Enable sync replication everywhere
- Use custom conflict handlers unnecessarily
- Over-complicate initial setup

**Do:**
- Start simple
- Add complexity as needed
- Monitor and adjust

### 2. Ignoring Conflicts

**Don't:**
- Ignore conflict logs
- Assume conflicts won't happen
- Skip conflict resolution setup

**Do:**
- Monitor conflicts regularly
- Set appropriate policies
- Design to minimize conflicts

### 3. Insufficient Monitoring

**Don't:**
- Set and forget
- Ignore replication lag
- Skip health checks

**Do:**
- Set up comprehensive monitoring
- Set up alerts
- Regular health checks

### 4. Poor Network Planning

**Don't:**
- Use high-latency connections
- Ignore bandwidth requirements
- Skip SSL in production

**Do:**
- Ensure low latency (< 50ms)
- Plan for bandwidth
- Use SSL/TLS

## Summary Checklist

### Setup
- [ ] Appropriate number of nodes (minimum 2-3)
- [ ] Network connectivity verified
- [ ] SSL/TLS configured
- [ ] Replication user created
- [ ] BDR group created

### Configuration
- [ ] Tables added to replication
- [ ] Conflict resolution policies set
- [ ] Timestamp columns and triggers configured
- [ ] Monitoring enabled

### Operations
- [ ] Monitoring and alerts configured
- [ ] Backup strategy in place
- [ ] Documentation maintained
- [ ] Regular testing scheduled

### Application
- [ ] Write routing implemented
- [ ] Connection pooling configured
- [ ] Error handling in place
- [ ] Conflict awareness built in

## Next Steps

- Review exercises in `exercises/` directory
- Build projects in `projects/` directory
- Refer to notes in `notes/` directory


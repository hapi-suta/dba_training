# High Availability with PGD/BDR

## HA Architecture Patterns

### Pattern 1: Active-Active Multi-Region

```
Region 1: Node A (Active) ←→ Region 2: Node B (Active)
   ↕                              ↕
Region 3: Node C (Active) ←→ Region 4: Node D (Active)
```

**Characteristics:**
- All nodes accept writes
- Geographic distribution
- Low latency per region
- High availability

### Pattern 2: Active-Active with Standby

```
Node A (Active) ←→ Node B (Active)
   ↕                    ↕
Standby 1          Standby 2
```

**Characteristics:**
- Active nodes handle writes
- Standby nodes for read scaling
- Can promote standby to active
- Disaster recovery ready

### Pattern 3: Hub and Spoke

```
         Hub Node (Primary)
        ↙    ↓    ↘
Spoke 1    Spoke 2    Spoke 3
```

**Characteristics:**
- Central hub coordinates
- Spokes replicate to hub
- Hub replicates to spokes
- Less mesh complexity

## Failover Scenarios

### Scenario 1: Single Node Failure

**What happens:**
- Other nodes continue operating
- Failed node's writes are lost if not replicated
- Remaining nodes continue replication

**Recovery:**
```sql
-- On remaining nodes, check status
SELECT * FROM bdr.bdr_nodes;

-- Node will show as inactive
-- Once node is recovered, rejoin:
SELECT bdr.bdr_group_join(
    local_node_name := 'recovered_node',
    node_external_dsn := 'host=recovered_node port=5432 dbname=mydb user=bdr_user',
    join_using_dsn := 'host=active_node port=5432 dbname=mydb user=bdr_user'
);
```

### Scenario 2: Network Partition (Split-Brain)

**Problem:**
- Network splits cluster into two groups
- Both groups continue accepting writes
- Data divergence occurs

**Prevention:**
- Use witness nodes for quorum
- Configure minimum node count
- Use synchronous replication for critical data

**Detection:**
```sql
-- Check if all nodes are reachable
SELECT 
    node_name,
    node_status,
    CASE 
        WHEN node_status = 'active' THEN 'OK'
        ELSE 'ISSUE'
    END AS health
FROM bdr.bdr_nodes;
```

**Resolution:**
1. Identify which partition has majority
2. Stop writes on minority partition
3. Resolve conflicts after network heals
4. Rejoin nodes

### Scenario 3: Complete Cluster Failure

**Recovery Steps:**

1. **Identify most recent node:**
   ```sql
   -- On each node, check last transaction
   SELECT pg_last_xact_replay_timestamp();
   ```

2. **Start with most recent node:**
   ```bash
   # Start PostgreSQL on most recent node
   systemctl start postgresql
   ```

3. **Recreate BDR group:**
   ```sql
   SELECT bdr.bdr_group_create(
       local_node_name := 'node1',
       node_external_dsn := 'host=node1 port=5432 dbname=mydb user=bdr_user'
   );
   ```

4. **Join other nodes:**
   ```sql
   -- On each other node
   SELECT bdr.bdr_group_join(
       local_node_name := 'node2',
       node_external_dsn := 'host=node2 port=5432 dbname=mydb user=bdr_user',
       join_using_dsn := 'host=node1 port=5432 dbname=mydb user=bdr_user'
   );
   ```

## Standby Nodes

### Creating a Standby Node

```sql
-- On standby node, create physical replica first
-- Then convert to logical standby if needed

-- Or create read-only BDR node
SELECT bdr.bdr_group_join(
    local_node_name := 'standby1',
    node_external_dsn := 'host=standby1 port=5432 dbname=mydb user=bdr_user',
    join_using_dsn := 'host=active_node port=5432 dbname=mydb user=bdr_user',
    node_kind := 'standby'  -- If supported
);
```

### Promoting Standby to Active

```sql
-- On standby node
SELECT bdr.bdr_node_promote('standby1');
```

## Disaster Recovery

### Backup Strategy

**Per-Node Backups:**
```bash
# Physical backup
pg_basebackup -h node1 -D /backup/node1 -U backup_user

# Logical backup
pg_dump -h node1 -U backup_user -Fc mydb > /backup/node1.dump
```

**Backup Best Practices:**
1. Backup all nodes regularly
2. Backup most recent node more frequently
3. Test restore procedures
4. Store backups off-site

### Point-in-Time Recovery

```bash
# Restore from backup
pg_restore -d mydb /backup/node1.dump

# Point-in-time recovery (if using WAL archiving)
# Configure continuous archiving
# Restore to specific time
```

### Geographic Distribution

**Multi-Region Setup:**
```
US-East: Node 1 ←→ EU-West: Node 2
   ↕                    ↕
US-West: Node 3 ←→ Asia-Pacific: Node 4
```

**Benefits:**
- Disaster recovery
- Low latency per region
- Regulatory compliance
- Data locality

## Rolling Upgrades

### Zero-Downtime Upgrade Process

1. **Prepare:**
   - Verify new version compatibility
   - Test upgrade on non-production
   - Plan upgrade order

2. **Upgrade First Node:**
   ```bash
   # Stop PostgreSQL
   systemctl stop postgresql
   
   # Upgrade EDB software
   # (Follow EDB upgrade documentation)
   
   # Start PostgreSQL
   systemctl start postgresql
   ```

3. **Verify Replication:**
   ```sql
   SELECT * FROM bdr.bdr_node_status();
   ```

4. **Upgrade Remaining Nodes:**
   - Repeat for each node
   - One at a time
   - Verify after each

### Upgrade Best Practices

- Upgrade during low-traffic periods
- Have rollback plan ready
- Test on staging first
- Monitor replication during upgrade
- Keep backups before upgrade

## Monitoring for HA

### Health Checks

```sql
-- Automated health check
CREATE OR REPLACE FUNCTION bdr_health_check()
RETURNS TABLE (
    check_name TEXT,
    status TEXT,
    details TEXT
) AS $$
BEGIN
    -- Check node count
    RETURN QUERY
    SELECT 
        'Node Count'::TEXT,
        CASE WHEN COUNT(*) >= 2 THEN 'OK' ELSE 'WARNING' END,
        COUNT(*)::TEXT || ' nodes active'
    FROM bdr.bdr_nodes
    WHERE node_status = 'active';
    
    -- Check replication lag
    RETURN QUERY
    SELECT 
        'Replication Lag'::TEXT,
        CASE WHEN MAX(replication_lag_time) < INTERVAL '1 minute' 
             THEN 'OK' ELSE 'WARNING' END,
        MAX(replication_lag_time)::TEXT
    FROM bdr.bdr_node_status();
    
    -- Check conflicts
    RETURN QUERY
    SELECT 
        'Conflicts (1h)'::TEXT,
        CASE WHEN COUNT(*) < 10 THEN 'OK' ELSE 'WARNING' END,
        COUNT(*)::TEXT || ' conflicts'
    FROM bdr.bdr_conflict_history
    WHERE conflict_time > NOW() - INTERVAL '1 hour';
END;
$$ LANGUAGE plpgsql;

-- Run health check
SELECT * FROM bdr_health_check();
```

### Alerting

Set up alerts for:
- Node failures
- High replication lag (> 1 minute)
- High conflict rate
- Disk space issues
- WAL accumulation

## Load Balancing

### Application-Level Load Balancing

```python
# Example: Round-robin node selection
nodes = ['node1', 'node2', 'node3']
current_node = 0

def get_node():
    global current_node
    node = nodes[current_node]
    current_node = (current_node + 1) % len(nodes)
    return node
```

### Read/Write Splitting

- **Writes**: Route to specific node (or round-robin)
- **Reads**: Can read from any node
- **Consistency**: Consider replication lag for reads

## Best Practices for HA

1. **Minimum 3 Nodes:**
   - Prevents split-brain
   - Better fault tolerance

2. **Geographic Distribution:**
   - Multiple regions
   - Disaster recovery

3. **Regular Backups:**
   - All nodes
   - Test restores

4. **Monitoring:**
   - Automated health checks
   - Alerting on issues

5. **Documentation:**
   - Runbooks for common scenarios
   - Recovery procedures
   - Contact information

6. **Testing:**
   - Regular failover tests
   - Disaster recovery drills
   - Performance testing

## Next Steps

- **Topic 08**: Best practices and design patterns
- **Exercises**: Practice HA scenarios


# PGD/BDR Setup and Installation

## Prerequisites

### 1. EDB Postgres Advanced Server
- EDB Postgres Advanced Server installed on all nodes
- Same major version across all nodes (recommended)
- Compatible PostgreSQL versions if using community PostgreSQL with BDR extension

### 2. Network Requirements
- All nodes must be able to connect to each other
- TCP/IP connectivity on PostgreSQL port (default 5432)
- Replication port accessible (if different)
- Firewall rules configured

### 3. System Requirements
- Sufficient disk space for WAL
- Adequate memory for replication processes
- Network bandwidth for replication traffic

### 4. PostgreSQL Configuration
- `wal_level = logical` (required for logical replication)
- `max_replication_slots` (sufficient for all nodes)
- `max_wal_senders` (sufficient for all nodes)
- `shared_preload_libraries` (include pglogical/BDR extensions)

## Installation Steps

### Step 1: Install EDB Postgres Advanced Server

On each node, install EDB Postgres Advanced Server:

```bash
# Example for Linux (adjust for your OS)
# Download EDB installer or use package manager
# Follow EDB installation documentation
```

### Step 2: Configure PostgreSQL

Edit `postgresql.conf`:

```ini
# Enable logical replication
wal_level = logical

# Increase replication slots (one per remote node + overhead)
max_replication_slots = 20

# Increase WAL senders (one per remote node)
max_wal_senders = 20

# Preload required extensions
shared_preload_libraries = 'pglogical,bdr'

# Optional: Tune for replication
max_worker_processes = 20
```

### Step 3: Configure pg_hba.conf

Add replication entries for all nodes:

```
# Allow replication from other nodes
host    replication     bdr_user     node1_ip/32    md5
host    replication     bdr_user     node2_ip/32    md5
host    replication     bdr_user     node3_ip/32    md5
```

### Step 4: Create Replication User

On each node, create a replication user:

```sql
CREATE USER bdr_user WITH REPLICATION PASSWORD 'secure_password';
GRANT ALL ON DATABASE your_database TO bdr_user;
```

### Step 5: Install BDR Extension

On each node, in your database:

```sql
CREATE EXTENSION IF NOT EXISTS pglogical;
CREATE EXTENSION IF NOT EXISTS bdr;
```

### Step 6: Restart PostgreSQL

Restart PostgreSQL on all nodes to apply configuration:

```bash
# Systemd example
sudo systemctl restart postgresql
# or
sudo systemctl restart edb-as-<version>
```

## Initial BDR Group Setup

### Option 1: Create First Node (Bootstrap)

On the first node:

```sql
-- Create BDR group
SELECT bdr.bdr_group_create(
    local_node_name := 'node1',
    node_external_dsn := 'host=node1.example.com port=5432 dbname=mydb user=bdr_user'
);
```

### Option 2: Join Additional Nodes

On each additional node:

```sql
-- Join existing BDR group
SELECT bdr.bdr_group_join(
    local_node_name := 'node2',
    node_external_dsn := 'host=node2.example.com port=5432 dbname=mydb user=bdr_user',
    join_using_dsn := 'host=node1.example.com port=5432 dbname=mydb user=bdr_user'
);
```

## Verification

### Check BDR Status

```sql
-- List all nodes in BDR group
SELECT * FROM bdr.bdr_nodes;

-- Check replication status
SELECT * FROM bdr.bdr_replication_slots;

-- Check node status
SELECT * FROM bdr.bdr_node_status();
```

### Test Replication

On Node 1:
```sql
CREATE TABLE test_table (id SERIAL PRIMARY KEY, data TEXT);
INSERT INTO test_table (data) VALUES ('test from node1');
```

On Node 2:
```sql
SELECT * FROM test_table;  -- Should see the row
INSERT INTO test_table (data) VALUES ('test from node2');
```

On Node 1:
```sql
SELECT * FROM test_table;  -- Should see both rows
```

## Common Installation Issues

### Issue 1: Extension Not Found
**Error**: `extension "bdr" does not exist`

**Solution**:
- Verify EDB Postgres Advanced Server is installed
- Check that BDR extension is available in your distribution
- Ensure `shared_preload_libraries` includes 'bdr'

### Issue 2: Cannot Connect to Remote Node
**Error**: Connection refused or authentication failed

**Solution**:
- Verify network connectivity: `telnet node2.example.com 5432`
- Check `pg_hba.conf` replication entries
- Verify user credentials
- Check firewall rules

### Issue 3: WAL Level Insufficient
**Error**: `wal_level must be set to "logical"`

**Solution**:
- Set `wal_level = logical` in `postgresql.conf`
- Restart PostgreSQL

### Issue 4: Insufficient Replication Slots
**Error**: `could not create replication slot`

**Solution**:
- Increase `max_replication_slots` in `postgresql.conf`
- Restart PostgreSQL

## Post-Installation Checklist

- [ ] All nodes can connect to each other
- [ ] BDR extension installed on all nodes
- [ ] Replication user created on all nodes
- [ ] BDR group created or nodes joined
- [ ] Test replication works (insert on one node, verify on others)
- [ ] Monitor replication lag
- [ ] Configure conflict resolution policies
- [ ] Set up monitoring and alerts

## Next Steps

- **Topic 04**: Detailed configuration and BDR group management
- **Topic 05**: Conflict resolution setup


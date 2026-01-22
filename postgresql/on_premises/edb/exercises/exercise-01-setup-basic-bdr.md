# Exercise 1: Setup Basic BDR Cluster

## Objective
Set up a basic 2-node BDR cluster and verify replication works.

## Prerequisites
- Two PostgreSQL/EDB servers with network connectivity
- EDB Postgres Advanced Server installed on both nodes
- Basic PostgreSQL administration knowledge

## Steps

### Step 1: Prepare Node 1

1. **Configure PostgreSQL:**
   ```bash
   # Edit postgresql.conf
   wal_level = logical
   max_replication_slots = 10
   max_wal_senders = 10
   shared_preload_libraries = 'pglogical,bdr'
   ```

2. **Configure pg_hba.conf:**
   ```
   host    replication     bdr_user     node2_ip/32    md5
   ```

3. **Create replication user:**
   ```sql
   CREATE USER bdr_user WITH REPLICATION PASSWORD 'secure_password';
   GRANT ALL ON DATABASE mydb TO bdr_user;
   ```

4. **Install extensions:**
   ```sql
   CREATE EXTENSION IF NOT EXISTS pglogical;
   CREATE EXTENSION IF NOT EXISTS bdr;
   ```

5. **Restart PostgreSQL:**
   ```bash
   systemctl restart postgresql
   ```

### Step 2: Prepare Node 2

Repeat Step 1 on Node 2, but in pg_hba.conf allow Node 1:
```
host    replication     bdr_user     node1_ip/32    md5
```

### Step 3: Create BDR Group

On Node 1:
```sql
SELECT bdr.bdr_group_create(
    local_node_name := 'node1',
    node_external_dsn := 'host=node1.example.com port=5432 dbname=mydb user=bdr_user password=secure_password'
);
```

### Step 4: Join Node 2

On Node 2:
```sql
SELECT bdr.bdr_group_join(
    local_node_name := 'node2',
    node_external_dsn := 'host=node2.example.com port=5432 dbname=mydb user=bdr_user password=secure_password',
    join_using_dsn := 'host=node1.example.com port=5432 dbname=mydb user=bdr_user password=secure_password'
);
```

### Step 5: Verify Setup

```sql
-- Check nodes
SELECT * FROM bdr.bdr_nodes;

-- Check replication slots
SELECT * FROM pg_replication_slots;

-- Check node status
SELECT * FROM bdr.bdr_node_status();
```

### Step 6: Test Replication

1. **Create a table on Node 1:**
   ```sql
   CREATE TABLE test_table (
       id SERIAL PRIMARY KEY,
       data TEXT,
       created_at TIMESTAMP DEFAULT NOW()
   );
   ```

2. **Add table to replication:**
   ```sql
   SELECT bdr.table_add('public.test_table');
   ```

3. **Insert data on Node 1:**
   ```sql
   INSERT INTO test_table (data) VALUES ('Test from node1');
   ```

4. **Verify on Node 2:**
   ```sql
   SELECT * FROM test_table;
   ```

5. **Insert data on Node 2:**
   ```sql
   INSERT INTO test_table (data) VALUES ('Test from node2');
   ```

6. **Verify on Node 1:**
   ```sql
   SELECT * FROM test_table;
   ```

## Expected Results

- Both nodes show in `bdr.bdr_nodes`
- Replication slots are active
- Data inserted on one node appears on the other
- Both nodes can accept writes

## Troubleshooting

- **Connection errors**: Check network, firewall, pg_hba.conf
- **Extension errors**: Verify EDB installation, shared_preload_libraries
- **Replication not working**: Check WAL level, replication slots

## Next Exercise

- Exercise 2: Configure conflict resolution


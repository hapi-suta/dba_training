-- Setup script for BDR node
-- Run this on each node before creating/joining BDR group

-- Step 1: Create replication user
CREATE USER bdr_user WITH REPLICATION PASSWORD 'CHANGE_THIS_PASSWORD';

-- Step 2: Grant permissions
GRANT ALL ON DATABASE current_database() TO bdr_user;

-- Step 3: Install required extensions
CREATE EXTENSION IF NOT EXISTS pglogical;
CREATE EXTENSION IF NOT EXISTS bdr;

-- Step 4: Verify extensions
SELECT extname, extversion 
FROM pg_extension 
WHERE extname IN ('pglogical', 'bdr');

-- Step 5: Check configuration
SHOW wal_level;  -- Should be 'logical'
SHOW max_replication_slots;  -- Should be >= number of nodes
SHOW max_wal_senders;  -- Should be >= number of nodes

-- Note: Update postgresql.conf and pg_hba.conf before running this script
-- postgresql.conf:
--   wal_level = logical
--   max_replication_slots = 10
--   max_wal_senders = 10
--   shared_preload_libraries = 'pglogical,bdr'
--
-- pg_hba.conf:
--   host    replication     bdr_user     <other_node_ip>/32    md5


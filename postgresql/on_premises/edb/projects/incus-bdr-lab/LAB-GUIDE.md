# PostgreSQL Bi-Directional Replication Lab Guide

A complete step-by-step guide to setting up a PostgreSQL bi-directional replication lab environment using Lima, nerdctl (containerd), and pglogical.

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Lab Architecture](#lab-architecture)
3. [Step 1: Create Lima VM](#step-1-create-lima-vm)
4. [Step 2: Create PostgreSQL Containers](#step-2-create-postgresql-containers)
5. [Step 3: Install pglogical](#step-3-install-pglogical)
6. [Step 4: Configure PostgreSQL](#step-4-configure-postgresql)
7. [Step 5: Set Up Replication](#step-5-set-up-replication)
8. [Step 6: Test Bi-Directional Replication](#step-6-test-bi-directional-replication)
9. [Key Concepts Learned](#key-concepts-learned)
10. [Troubleshooting](#troubleshooting)
11. [Cleanup](#cleanup)

---

## Prerequisites

- macOS with Homebrew installed
- Lima installed (`brew install lima`)
- At least 8GB RAM available
- 50GB disk space

### Verify Lima Installation

```bash
lima --version
# Output: limactl version 1.0.3
```

---

## Lab Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                     Lima VM (incus-lab)                     │
│                     Ubuntu 24.04 / 4 CPU / 8GB RAM          │
│                                                             │
│  ┌─────────────────────────────────────────────────────┐   │
│  │              Docker Network: pgnet                   │   │
│  │              Subnet: 172.20.0.0/24                   │   │
│  │                                                      │   │
│  │  ┌──────────────┐  ┌──────────────┐  ┌────────────┐ │   │
│  │  │  pg-node1    │  │  pg-node2    │  │  pg-node3  │ │   │
│  │  │ 172.20.0.11  │  │ 172.20.0.12  │  │ 172.20.0.13│ │   │
│  │  │ PostgreSQL   │  │ PostgreSQL   │  │ PostgreSQL │ │   │
│  │  │ 16 + pglog   │  │ 16 + pglog   │  │ 16         │ │   │
│  │  │              │  │              │  │            │ │   │
│  │  │ Odd IDs      │  │ Even IDs     │  │ (spare)    │ │   │
│  │  │ (1,3,5...)   │  │ (2,4,6...)   │  │            │ │   │
│  │  └──────┬───────┘  └──────┬───────┘  └────────────┘ │   │
│  │         │                 │                          │   │
│  │         └────────┬────────┘                          │   │
│  │                  │                                   │   │
│  │         Bi-directional Replication                   │   │
│  │              (pglogical)                             │   │
│  └─────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
```

---

## Step 1: Create Lima VM

### 1.1 Create Lima Configuration File

Create `incus.yaml`:

```yaml
# Lima configuration for PostgreSQL lab environment
images:
  - location: "https://cloud-images.ubuntu.com/releases/24.04/release/ubuntu-24.04-server-cloudimg-arm64.img"
    arch: "aarch64"
  - location: "https://cloud-images.ubuntu.com/releases/24.04/release/ubuntu-24.04-server-cloudimg-amd64.img"
    arch: "x86_64"

cpus: 4
memory: "8GiB"
disk: "50GiB"

mounts:
  - location: "~/Desktop/dba_training"
    writable: true

message: |
  Lab VM is ready!
  Run: limactl shell incus-lab
```

### 1.2 Create and Start the VM

```bash
# Create the VM (downloads Ubuntu image ~700MB)
limactl create --name=incus-lab incus.yaml

# Start the VM
limactl start incus-lab
```

**Expected output:**
```
Downloading the image (ubuntu-24.04-server-cloudimg-arm64.img)
...
READY. Run `limactl shell incus-lab` to open the shell.
```

### 1.3 Verify VM is Running

```bash
limactl list
```

**Expected output:**
```
NAME         STATUS     SSH                CPUS    MEMORY    DISK
incus-lab    Running    127.0.0.1:50183    4       8GiB      50GiB
```

---

## Step 2: Create PostgreSQL Containers

### 2.1 Enter the Lima VM

```bash
limactl shell incus-lab
```

### 2.2 Start Containerd Service

```bash
sudo systemctl start containerd
sudo systemctl status containerd
```

### 2.3 Create Dedicated Network

```bash
sudo nerdctl network create pgnet --subnet 172.20.0.0/24
```

### 2.4 Create PostgreSQL Containers

```bash
# Create 3 PostgreSQL containers with static IPs
sudo nerdctl run -d \
  --name pg-node1 \
  --hostname pg-node1 \
  --network pgnet \
  --ip 172.20.0.11 \
  -e POSTGRES_PASSWORD=postgres \
  -e POSTGRES_HOST_AUTH_METHOD=trust \
  postgres:16

sudo nerdctl run -d \
  --name pg-node2 \
  --hostname pg-node2 \
  --network pgnet \
  --ip 172.20.0.12 \
  -e POSTGRES_PASSWORD=postgres \
  -e POSTGRES_HOST_AUTH_METHOD=trust \
  postgres:16

sudo nerdctl run -d \
  --name pg-node3 \
  --hostname pg-node3 \
  --network pgnet \
  --ip 172.20.0.13 \
  -e POSTGRES_PASSWORD=postgres \
  -e POSTGRES_HOST_AUTH_METHOD=trust \
  postgres:16
```

### 2.5 Verify Containers are Running

```bash
sudo nerdctl ps
```

**Expected output:**
```
CONTAINER ID    IMAGE                            COMMAND         STATUS    NAMES
692c3c16cc7b    docker.io/library/postgres:16    "docker-..."    Up        pg-node3
5e80bf6f616c    docker.io/library/postgres:16    "docker-..."    Up        pg-node2
167ac6178978    docker.io/library/postgres:16    "docker-..."    Up        pg-node1
```

### 2.6 Test Connectivity Between Containers

```bash
# Install netcat and test connectivity
sudo nerdctl exec pg-node1 bash -c "apt-get update && apt-get install -y netcat-openbsd"
sudo nerdctl exec pg-node1 nc -zv 172.20.0.12 5432
```

**Expected output:**
```
Connection to 172.20.0.12 5432 port [tcp/postgresql] succeeded!
```

---

## Step 3: Install pglogical

### 3.1 Install pglogical Extension on All Nodes

```bash
for node in pg-node1 pg-node2 pg-node3; do
  echo "Installing pglogical on $node..."
  sudo nerdctl exec $node bash -c "apt-get update && apt-get install -y postgresql-16-pglogical"
done
```

**Expected output:**
```
Installing pglogical on pg-node1...
...
Setting up postgresql-16-pglogical (2.4.6-1.pgdg13+1) ...
Installing pglogical on pg-node2...
...
Installing pglogical on pg-node3...
...
```

---

## Step 4: Configure PostgreSQL

### 4.1 Configure PostgreSQL Settings on All Nodes

Use `ALTER SYSTEM` to configure PostgreSQL for logical replication:

```bash
for node in pg-node1 pg-node2 pg-node3; do
  echo "Configuring $node..."
  sudo nerdctl exec $node psql -U postgres -c "ALTER SYSTEM SET wal_level = logical;"
  sudo nerdctl exec $node psql -U postgres -c "ALTER SYSTEM SET max_replication_slots = 10;"
  sudo nerdctl exec $node psql -U postgres -c "ALTER SYSTEM SET max_wal_senders = 10;"
  sudo nerdctl exec $node psql -U postgres -c "ALTER SYSTEM SET max_worker_processes = 10;"
  sudo nerdctl exec $node psql -U postgres -c "ALTER SYSTEM SET shared_preload_libraries = 'pglogical';"
done
```

### 4.2 Configure pg_hba.conf for Network Access

```bash
for node in pg-node1 pg-node2 pg-node3; do
  sudo nerdctl exec $node bash -c "echo 'host all all 172.20.0.0/24 trust' >> /var/lib/postgresql/data/pg_hba.conf"
  sudo nerdctl exec $node bash -c "echo 'host replication all 172.20.0.0/24 trust' >> /var/lib/postgresql/data/pg_hba.conf"
done
```

### 4.3 Restart All Containers

```bash
for node in pg-node1 pg-node2 pg-node3; do
  sudo nerdctl restart $node
done
sleep 5
```

### 4.4 Verify Configuration

```bash
sudo nerdctl exec pg-node1 psql -U postgres -c "SHOW wal_level;"
sudo nerdctl exec pg-node1 psql -U postgres -c "SHOW shared_preload_libraries;"
```

**Expected output:**
```
 wal_level 
-----------
 logical
(1 row)

 shared_preload_libraries 
--------------------------
 pglogical
(1 row)
```

---

## Step 5: Set Up Replication

### 5.1 Create Practice Database

```bash
for node in pg-node1 pg-node2; do
  sudo nerdctl exec $node psql -U postgres -c "CREATE DATABASE practice;"
  sudo nerdctl exec $node psql -U postgres -d practice -c "CREATE EXTENSION pglogical;"
done
```

### 5.2 Create pglogical Nodes

```bash
# Create node on pg-node1
sudo nerdctl exec pg-node1 psql -U postgres -d practice -c "
  SELECT pglogical.create_node(
    node_name := 'node1',
    dsn := 'host=172.20.0.11 port=5432 dbname=practice user=postgres'
  );
"

# Create node on pg-node2
sudo nerdctl exec pg-node2 psql -U postgres -d practice -c "
  SELECT pglogical.create_node(
    node_name := 'node2',
    dsn := 'host=172.20.0.12 port=5432 dbname=practice user=postgres'
  );
"
```

### 5.3 Create Sample Table on Both Nodes

```bash
for node in pg-node1 pg-node2; do
  sudo nerdctl exec $node psql -U postgres -d practice -c "
    CREATE TABLE users (
      id SERIAL PRIMARY KEY,
      name TEXT NOT NULL,
      email TEXT,
      created_at TIMESTAMP DEFAULT NOW(),
      updated_at TIMESTAMP DEFAULT NOW()
    );
  "
  
  # Add table to replication set
  sudo nerdctl exec $node psql -U postgres -d practice -c "
    SELECT pglogical.replication_set_add_table('default', 'users', true);
  "
done
```

### 5.4 Create Bi-Directional Subscriptions

```bash
# Node2 subscribes to Node1
sudo nerdctl exec pg-node2 psql -U postgres -d practice -c "
  SELECT pglogical.create_subscription(
    subscription_name := 'sub_node1_to_node2',
    provider_dsn := 'host=172.20.0.11 port=5432 dbname=practice user=postgres',
    synchronize_data := false
  );
"

# Node1 subscribes to Node2
sudo nerdctl exec pg-node1 psql -U postgres -d practice -c "
  SELECT pglogical.create_subscription(
    subscription_name := 'sub_node2_to_node1',
    provider_dsn := 'host=172.20.0.12 port=5432 dbname=practice user=postgres',
    synchronize_data := false
  );
"
```

### 5.5 Configure Sequences to Avoid Conflicts

**Important:** In bi-directional replication, both nodes generate IDs. To avoid primary key conflicts, configure different sequence ranges:

```bash
# Node1: generates odd IDs (1, 3, 5, ...)
sudo nerdctl exec pg-node1 psql -U postgres -d practice -c "
  ALTER SEQUENCE users_id_seq INCREMENT BY 2 RESTART WITH 1;
"

# Node2: generates even IDs (2, 4, 6, ...)
sudo nerdctl exec pg-node2 psql -U postgres -d practice -c "
  ALTER SEQUENCE users_id_seq INCREMENT BY 2 RESTART WITH 2;
"
```

---

## Step 6: Test Bi-Directional Replication

### 6.1 Insert Data on Node1

```bash
sudo nerdctl exec pg-node1 psql -U postgres -d practice -c "
  INSERT INTO users (name, email) VALUES ('Alice', 'alice@example.com');
"
```

### 6.2 Verify Replication to Node2

```bash
# Wait for replication
sleep 2

# Check Node2
sudo nerdctl exec pg-node2 psql -U postgres -d practice -c "SELECT * FROM users;"
```

**Expected output:**
```
 id | name  |       email       |         created_at         |         updated_at         
----+-------+-------------------+----------------------------+----------------------------
  1 | Alice | alice@example.com | 2026-01-22 02:16:51.369039 | 2026-01-22 02:16:51.369039
(1 row)
```

### 6.3 Insert Data on Node2

```bash
sudo nerdctl exec pg-node2 psql -U postgres -d practice -c "
  INSERT INTO users (name, email) VALUES ('Bob', 'bob@example.com');
"
```

### 6.4 Verify Replication to Node1

```bash
sleep 2

# Check Node1 - should have both Alice and Bob
sudo nerdctl exec pg-node1 psql -U postgres -d practice -c "SELECT * FROM users ORDER BY id;"
```

**Expected output:**
```
 id | name  |       email       |         created_at         |         updated_at         
----+-------+-------------------+----------------------------+----------------------------
  1 | Alice | alice@example.com | 2026-01-22 02:16:51.369039 | 2026-01-22 02:16:51.369039
  2 | Bob   | bob@example.com   | 2026-01-22 02:17:06.395486 | 2026-01-22 02:17:06.395486
(2 rows)
```

### 6.5 Continue Testing

```bash
# Insert more data on both nodes
sudo nerdctl exec pg-node1 psql -U postgres -d practice -c "
  INSERT INTO users (name, email) VALUES ('Charlie', 'charlie@example.com');
"

sudo nerdctl exec pg-node2 psql -U postgres -d practice -c "
  INSERT INTO users (name, email) VALUES ('Diana', 'diana@example.com');
"

sleep 2

# Final state on both nodes
echo "=== Node1 ==="
sudo nerdctl exec pg-node1 psql -U postgres -d practice -c "SELECT * FROM users ORDER BY id;"

echo "=== Node2 ==="
sudo nerdctl exec pg-node2 psql -U postgres -d practice -c "SELECT * FROM users ORDER BY id;"
```

**Expected final output (both nodes identical):**
```
 id |  name   |        email        |         created_at         |         updated_at         
----+---------+---------------------+----------------------------+----------------------------
  1 | Alice   | alice@example.com   | 2026-01-22 02:16:51.369039 | 2026-01-22 02:16:51.369039
  2 | Bob     | bob@example.com     | 2026-01-22 02:17:06.395486 | 2026-01-22 02:17:06.395486
  3 | Charlie | charlie@example.com | 2026-01-22 02:17:20.316935 | 2026-01-22 02:17:20.316935
  4 | Diana   | diana@example.com   | 2026-01-22 02:17:22.389129 | 2026-01-22 02:17:22.389129
(4 rows)
```

---

## Key Concepts Learned

### 1. Bi-Directional Replication
- Changes made on either node automatically replicate to the other
- Both nodes are read/write (active-active)
- Uses logical replication (row-level changes)

### 2. pglogical Components
- **Node**: A PostgreSQL instance participating in replication
- **Replication Set**: Collection of tables to replicate
- **Subscription**: Connection from subscriber to provider

### 3. Sequence Conflict Prevention
- Each node uses different ID ranges
- Node1: odd IDs (INCREMENT BY 2, START 1)
- Node2: even IDs (INCREMENT BY 2, START 2)
- Alternatively, use UUIDs for primary keys

### 4. Configuration Requirements
- `wal_level = logical` - Enable logical WAL decoding
- `max_replication_slots` - Slots for replication connections
- `max_wal_senders` - WAL sender processes
- `shared_preload_libraries = 'pglogical'` - Load extension

### 5. EDB BDR vs pglogical
| Feature | pglogical | EDB BDR |
|---------|-----------|---------|
| Bi-directional | ✅ Manual setup | ✅ Built-in |
| Conflict resolution | ❌ Limited | ✅ Advanced policies |
| DDL replication | ❌ No | ✅ Yes |
| Mesh topology | ❌ Manual | ✅ Automatic |
| Commercial support | ❌ | ✅ |

---

## Troubleshooting

### Container Won't Start
```bash
# Check logs
sudo nerdctl logs pg-node1

# Common issues:
# - Configuration syntax errors
# - Extension not found (need to install before configuring)
```

### Replication Not Working
```bash
# Check subscription status
sudo nerdctl exec pg-node1 psql -U postgres -d practice -c "
  SELECT * FROM pglogical.subscription;
"

# Check for errors in logs
sudo nerdctl logs pg-node1 2>&1 | grep -i error
```

### Primary Key Conflicts
```bash
# Check current sequence values
sudo nerdctl exec pg-node1 psql -U postgres -d practice -c "
  SELECT last_value, increment_by FROM users_id_seq;
"

# Reset sequence if needed
sudo nerdctl exec pg-node1 psql -U postgres -d practice -c "
  ALTER SEQUENCE users_id_seq RESTART WITH <next_odd_value>;
"
```

### Network Connectivity Issues
```bash
# Test connectivity between containers
sudo nerdctl exec pg-node1 nc -zv 172.20.0.12 5432

# Check network
sudo nerdctl network inspect pgnet
```

---

## Cleanup

### Stop and Remove Containers
```bash
sudo nerdctl stop pg-node1 pg-node2 pg-node3
sudo nerdctl rm pg-node1 pg-node2 pg-node3
sudo nerdctl network rm pgnet
```

### Stop Lima VM
```bash
exit  # Exit from Lima shell
limactl stop incus-lab
```

### Delete Lima VM (optional)
```bash
limactl delete incus-lab
```

---

## Quick Reference Commands

```bash
# Enter Lima VM
limactl shell incus-lab

# List containers
sudo nerdctl ps

# Connect to PostgreSQL
sudo nerdctl exec -it pg-node1 psql -U postgres -d practice
sudo nerdctl exec -it pg-node2 psql -U postgres -d practice

# Check replication status
SELECT * FROM pglogical.subscription;
SELECT * FROM pglogical.node;
SELECT * FROM pglogical.replication_set;

# View container logs
sudo nerdctl logs pg-node1
sudo nerdctl logs pg-node2
```

---

## Next Steps

1. **Add Node3** to create a 3-node mesh topology
2. **Test update conflicts** - Update same row on both nodes
3. **Practice failover** - Stop one node and verify the other continues
4. **Explore conflict resolution** with custom handlers
5. **Try EDB Postgres Distributed** for production-grade features

---

*Lab created: January 22, 2026*
*PostgreSQL Version: 16.11*
*pglogical Version: 2.4.6*


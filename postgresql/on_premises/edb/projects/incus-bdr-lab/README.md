# PostgreSQL Bi-Directional Replication Lab

This project sets up a local lab environment using Lima and containerd/nerdctl to practice PostgreSQL bi-directional replication with pglogical (similar concepts to EDB Postgres Distributed/BDR).

## Files

- **LAB-GUIDE.md** - Complete step-by-step guide with explanations
- **setup-bdr-lab.sh** - Automated setup script
- **incus.yaml** - Lima VM configuration

## Prerequisites

- macOS with Lima installed (`brew install lima`)
- At least 8GB RAM available for the VM
- 50GB disk space

## Quick Start

### Option 1: Automated Setup

```bash
# 1. Create and start the Lima VM
cd ~/Desktop/dba_training/postgresql/on_premises/edb/projects/incus-bdr-lab
limactl create --name=incus-lab incus.yaml
limactl start incus-lab

# 2. Enter the VM and run setup script
limactl shell incus-lab
cd /tmp/lima/Desktop/dba_training/postgresql/on_premises/edb/projects/incus-bdr-lab
chmod +x setup-bdr-lab.sh
./setup-bdr-lab.sh
```

### Option 2: Manual Setup

Follow the detailed instructions in **LAB-GUIDE.md**

## Lab Architecture

```
┌─────────────────────────────────────────────────┐
│              Lima VM (incus-lab)                │
│                                                 │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────┐ │
│  │  pg-node1   │  │  pg-node2   │  │pg-node3 │ │
│  │ 172.20.0.11 │  │ 172.20.0.12 │  │  .13    │ │
│  │ PostgreSQL  │←→│ PostgreSQL  │  │ (spare) │ │
│  │ Odd IDs     │  │ Even IDs    │  │         │ │
│  └─────────────┘  └─────────────┘  └─────────┘ │
│                                                 │
│         Bi-directional Replication              │
│              (pglogical)                        │
└─────────────────────────────────────────────────┘
```

## Quick Commands

```bash
# Enter Lima VM
limactl shell incus-lab

# List containers
sudo nerdctl ps

# Connect to PostgreSQL
sudo nerdctl exec -it pg-node1 psql -U postgres -d practice
sudo nerdctl exec -it pg-node2 psql -U postgres -d practice

# Insert test data
sudo nerdctl exec pg-node1 psql -U postgres -d practice -c \
  "INSERT INTO users (name, email) VALUES ('Test', 'test@example.com');"

# Check replication
sudo nerdctl exec pg-node2 psql -U postgres -d practice -c \
  "SELECT * FROM users;"
```

## What You'll Learn

1. **Bi-Directional Replication** - Active-active PostgreSQL setup
2. **pglogical** - Logical replication extension
3. **Conflict Prevention** - Using sequence partitioning
4. **Similar to EDB BDR** - Core concepts apply to enterprise solutions

## Cleanup

```bash
# Stop containers
sudo nerdctl stop pg-node1 pg-node2 pg-node3
sudo nerdctl rm pg-node1 pg-node2 pg-node3

# Exit and stop VM
exit
limactl stop incus-lab

# Delete VM (optional)
limactl delete incus-lab
```

## Next Steps

- Read **LAB-GUIDE.md** for detailed explanations
- Add Node3 to create a 3-node mesh
- Test update conflicts
- Explore EDB Postgres Distributed for production features


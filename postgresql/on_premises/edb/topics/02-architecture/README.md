# PGD/BDR Architecture

## Overview

EDB Postgres Distributed uses a **mesh topology** where each node connects directly to every other node in the BDR group. This enables true multi-master replication.

## Architecture Components

### 1. BDR Group
A **BDR Group** is a collection of PostgreSQL nodes that replicate data to each other.

```
Node A ←→ Node B
  ↕        ↕
Node C ←→ Node D
```

**Characteristics:**
- Each node can accept writes
- All nodes replicate to all other nodes
- Direct connections between all nodes (mesh)
- Shared replication metadata

### 2. Replication Flow

#### Write Process
1. **Client writes to Node A**
   - Transaction commits locally on Node A
   - Returns success to client immediately (async mode)

2. **Replication to Other Nodes**
   - Node A captures changes via logical replication
   - Changes queued for replication
   - Sent to Node B, Node C, Node D in parallel

3. **Apply on Remote Nodes**
   - Each remote node receives changes
   - Applies changes via logical replication apply process
   - Conflict detection occurs during apply

#### Mesh Topology Benefits
- **No single bottleneck**: Direct connections
- **Fault tolerance**: If one node fails, others continue
- **Parallel replication**: Changes sent to all nodes simultaneously

### 3. Logical Replication Foundation

BDR builds on PostgreSQL's **logical replication** (pglogical):

- **Publication**: Defines what to replicate (tables, columns)
- **Subscription**: Receives and applies changes
- **Replication slots**: Track replication progress
- **WAL decoding**: Converts WAL to logical changes

**Key Difference:**
- Standard logical replication: One-way (master → replica)
- BDR: Bi-directional (all nodes ↔ all nodes)

### 4. Conflict Detection and Resolution

#### When Conflicts Occur
- Same row updated on different nodes simultaneously
- Primary key violations
- Unique constraint violations
- Foreign key constraint violations

#### Conflict Resolution Process
1. **Detection**: During apply on remote node
2. **Policy Check**: Apply configured resolution policy
3. **Resolution**: Execute policy (last_wins, first_wins, etc.)
4. **Logging**: Record conflict in conflict log

### 5. DDL Replication

Schema changes are automatically replicated:

- **CREATE TABLE/INDEX/VIEW**
- **ALTER TABLE** (add/drop columns, constraints)
- **DROP TABLE/INDEX/VIEW**
- **GRANT/REVOKE** permissions

**Process:**
1. DDL executed on one node
2. Captured and queued for replication
3. Applied to all other nodes in order
4. Maintains schema consistency

## Node Types

### 1. BDR Node (Full Member)
- Accepts writes
- Replicates to all other nodes
- Receives replication from all nodes
- Participates in conflict resolution

### 2. Standby Node
- Read-only replica
- Can be promoted to BDR node
- Useful for disaster recovery
- Reduces load on primary nodes

### 3. Witness Node
- Lightweight node for quorum
- Helps with split-brain prevention
- Doesn't store full data

## Replication Modes

### Asynchronous (Default)
- **Commit locally first**: Returns success immediately
- **Replicate later**: Changes queued and sent
- **Lower latency**: Better write performance
- **Eventual consistency**: Nodes may be briefly out of sync

### Synchronous
- **Wait for replication**: Commit waits for N nodes
- **Stronger consistency**: All nodes in sync
- **Higher latency**: Slower writes
- **Better durability**: Data on multiple nodes before commit

## Data Flow Example

```
Time    Node A          Node B          Node C
----    ------          ------          ------
T1      INSERT row1     -               -
T2      COMMIT          -               -
T3      (replicate)     RECEIVE row1    RECEIVE row1
T4      -               APPLY row1      APPLY row1
T5      -               COMMIT          COMMIT
```

## Network Requirements

### Connectivity
- **All nodes must connect to all nodes**
- TCP/IP connections on replication port
- Firewall rules for inter-node communication

### Bandwidth
- Replication traffic = write traffic × (nodes - 1)
- Consider network capacity
- Compression available to reduce bandwidth

### Latency
- Affects replication lag
- Geographic distribution increases latency
- Synchronous mode more sensitive to latency

## Storage Considerations

### WAL (Write-Ahead Log)
- Logical replication reads from WAL
- WAL retention important for replication
- Monitor WAL disk usage

### Replication Slots
- Track replication progress
- Prevent WAL cleanup
- Monitor slot lag

## Performance Characteristics

### Write Performance
- **Local writes**: Fast (no network wait in async mode)
- **Replication overhead**: CPU and network for each write
- **Scales with**: Node count affects overhead

### Read Performance
- **Excellent**: Can read from any node
- **Scales linearly**: Add nodes for more read capacity
- **Local reads**: Fastest (no replication lag)

### Conflict Impact
- **Detection overhead**: Minimal
- **Resolution overhead**: Depends on policy
- **Logging overhead**: Conflict logs maintained

## Next Steps

- **Topic 03**: Setup and installation
- **Topic 04**: Configuration and BDR group creation


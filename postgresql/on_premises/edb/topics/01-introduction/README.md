# Introduction to EDB Postgres Distributed (PGD) and Bi-Directional Replication (BDR)

## What is EDB Postgres Distributed (PGD)?

**EDB Postgres Distributed (PGD)** is a PostgreSQL distribution from EnterpriseDB that extends community PostgreSQL with:

- **Multi-master replication** capabilities
- **Bi-Directional Replication (BDR)** for write-active nodes
- **Conflict detection and resolution** mechanisms
- **DDL replication** for schema changes
- **High availability** and fault tolerance features
- **Operational tools** for distributed database management

## What is Bi-Directional Replication (BDR)?

**BDR (Bi-Directional Replication)** is the core component that enables:

- **Multi-master writes**: Any node in a BDR group can accept writes
- **Row-level replication**: Changes propagate row-by-row to all nodes
- **Mesh topology**: Each node connects directly to every other node
- **Asynchronous replication**: Writes commit locally first, then forward (synchronous options available)

## Key Features

### 1. Multi-Master Architecture
- Write to any node in the cluster
- No single point of failure for writes
- Geographic distribution support

### 2. Logical Replication
- Built on PostgreSQL's logical replication / pglogical
- Replicates at the logical level (not block/physical)
- More flexible than physical replication

### 3. DDL Replication
- Schema changes automatically propagate
- CREATE, ALTER, DROP statements replicated
- Maintains schema consistency

### 4. Conflict Resolution
- Detects conflicting writes automatically
- Configurable resolution policies
- Supports custom conflict handlers

### 5. High Availability
- Standby nodes support
- Rolling upgrades
- Automatic recovery after node failures

## Use Cases

1. **Geographic Distribution**
   - Multi-region deployments
   - Low-latency writes in each region
   - Disaster recovery

2. **High Availability**
   - Eliminate single point of failure
   - Active-active configurations
   - Zero-downtime maintenance

3. **Read/Write Scaling**
   - Distribute write load across nodes
   - Scale reads from multiple locations
   - Reduce latency for global applications

4. **Disaster Recovery**
   - Multiple active sites
   - Automatic failover capabilities
   - Data redundancy

## Comparison with Core PostgreSQL Logical Replication

| Feature | Core PostgreSQL Logical Replication | EDB PGD + BDR |
|---------|--------------------------------------|---------------|
| Multi-master | ❌ One-way only | ✅ Bi-directional |
| DDL Replication | ❌ Manual | ✅ Automatic |
| Conflict Resolution | ❌ Minimal | ✅ Built-in policies |
| Mesh Topology | ❌ Master-slave only | ✅ Full mesh |
| Write Scaling | ❌ Single master | ✅ Multi-master |

## Limitations and Trade-offs

### 1. Latency and Consistency
- **Asynchronous by default**: Nodes may be out of sync briefly
- **Synchronous options**: Available but impact performance
- **Eventual consistency**: Acceptable for many use cases

### 2. Write Throughput
- Writes replicated to all nodes
- Network and CPU overhead increases with node count
- Read performance scales well

### 3. Conflict Complexity
- Must handle write conflicts
- Requires careful data modeling
- Partitioning helps avoid conflicts

### 4. Compatibility
- Some features EDB-specific
- May require EDB distribution or extended servers
- Not available in vanilla PostgreSQL

## When to Use PGD/BDR

✅ **Good fit for:**
- Multi-region applications
- Active-active high availability
- Applications with partitioned write sets
- Geographic distribution requirements

❌ **Not ideal for:**
- Simple single-region deployments
- Applications with high conflict rates
- Tight consistency requirements (without sync replication)
- Budget constraints (EDB licensing)

## Next Steps

- **Topic 02**: Architecture and how replication works
- **Topic 03**: Setup and installation
- **Topic 04**: Configuration and BDR group setup


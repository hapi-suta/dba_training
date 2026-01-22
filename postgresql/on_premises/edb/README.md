# EDB Postgres Advanced Server Learning

This directory contains learning materials for EnterpriseDB Postgres Advanced Server and EDB Postgres Distributed (PGD).

## EDB Postgres Distributed (PGD) with Bi-Directional Replication (BDR)

**EDB Postgres Distributed (PGD)** is a PostgreSQL distribution that adds extensions for distributed, multi-master replication, conflict resolution, and operational features.

**Bi-Directional Replication (BDR)** is the core component enabling multi-master replication where any node can accept writes.

## Directory Structure

- **topics/** - Structured learning materials
  - `01-introduction/` - What is PGD/BDR, use cases, comparison with core PostgreSQL
  - `02-architecture/` - Architecture, mesh topology, how replication works
  - `03-setup-installation/` - Installation, initial setup, prerequisites
  - `04-configuration/` - BDR group setup, replication configuration
  - `05-conflict-resolution/` - Conflict detection and resolution policies
  - `06-monitoring-troubleshooting/` - Monitoring, performance, troubleshooting
  - `07-high-availability/` - HA setup, failover, disaster recovery
  - `08-best-practices/` - Best practices, design patterns, recommendations

- **exercises/** - Hands-on practice exercises
- **projects/** - Real-world project implementations
- **notes/** - Personal notes and summaries
- **scripts/** - Setup scripts, configuration examples, utilities

## Key Concepts

### Multi-Master Replication
- Any node in a BDR group can accept writes
- Changes propagate row-by-row to all other nodes
- Asynchronous by default (synchronous options available)

### Mesh Topology
- Each node connects directly to every other node
- Changes are sent/received through direct connections

### Conflict Resolution
- Configurable policies: last_wins, first_wins, accept_remote, etc.
- Critical for multi-master environments

### DDL Replication
- Schema changes (CREATE/ALTER/DROP) are automatically propagated
- Maintains schema consistency across nodes

## Getting Started

1. Start with `topics/01-introduction/` to understand the fundamentals
2. Follow the numbered topics in sequence
3. Practice with exercises in `exercises/`
4. Build projects in `projects/` to apply your knowledge


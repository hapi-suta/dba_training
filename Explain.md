# PostgreSQL EXPLAIN / EXPLAIN ANALYZE - Complete Practice Lab & Runbook

## Interview Prep for Senior DBA - Healthcare SaaS Platform

---

## Table of Contents

1. [Lab Setup Instructions](#1-lab-setup-instructions)
2. [EXPLAIN Options - Complete Reference](#2-explain-options---complete-reference)
3. [Reading Execution Plans - Node by Node](#3-reading-execution-plans---node-by-node)
4. [Key Metrics & Red Flags](#4-key-metrics--red-flags)
5. [Progressive Exercises (Easy to Hard)](#5-progressive-exercises)
6. [HypoPG Workflow Exercises](#6-hypopg-workflow-exercises)
7. [Anti-Patterns & Interview Gotchas](#7-anti-patterns--interview-gotchas)
8. [Speed Drills (Timed Interview Simulations)](#8-speed-drills)
9. [SQL Server DBA Talking Points](#9-sql-server-dba-talking-points)

---

## 1. Lab Setup Instructions

### Prerequisites
- PostgreSQL 15 or 16
- HypoPG extension installed at the system level
- At least 4GB RAM allocated to PostgreSQL
- Recommended: `shared_buffers = 1GB`, `work_mem = 64MB`, `effective_cache_size = 3GB`

### Recommended postgresql.conf Tuning for Lab

```
shared_buffers = 1GB
work_mem = 64MB
effective_cache_size = 3GB
random_page_cost = 1.1          # SSD assumed
default_statistics_target = 100  # Default; we'll change per-column later
jit = off                       # Disable JIT to keep plans readable
```

### Load Order

```bash
psql -U postgres -f 01_schema_and_data.sql    # ~5-10 minutes
psql -U postgres -d explain_lab -f 02_hypopg_setup.sql
```

### Verify Load

```sql
\c explain_lab
SELECT relname, n_live_tup FROM pg_stat_user_tables ORDER BY n_live_tup DESC;
```

Expected:
| Table | Approximate Rows |
|-------|-----------------|
| audit_log | 15,000,000 |
| appointments | 10,000,000 |
| patients | 2,000,000 |
| shifts | 1,000,000 |
| referrals | 500,000 |
| schedule_templates | ~10,000 |
| providers | 5,000 |
| departments | 200 |
| facilities | 50 |

---

## 2. EXPLAIN Options - Complete Reference

### The Options Matrix

| Command | Executes Query? | Shows Actual Times? | Shows Buffers? | Use When |
|---------|:-:|:-:|:-:|----------|
| `EXPLAIN` | No | No | No | Quick plan check, won't touch data |
| `EXPLAIN ANALYZE` | **YES** | Yes | No | Need actual vs estimated comparison |
| `EXPLAIN (ANALYZE, BUFFERS)` | **YES** | Yes | Yes | **Your default for performance work** |
| `EXPLAIN (ANALYZE, BUFFERS, TIMING)` | **YES** | Yes (explicit) | Yes | Same as above (TIMING is on by default with ANALYZE) |
| `EXPLAIN (ANALYZE, BUFFERS, TIMING OFF)` | **YES** | No | Yes | High-frequency loops where timing overhead is significant |
| `EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON)` | **YES** | Yes | Yes | Feed into pgAdmin, explain.dalibo.com, or auto-analysis tools |
| `EXPLAIN (ANALYZE, BUFFERS, FORMAT YAML)` | **YES** | Yes | Yes | Human-readable structured output |
| `EXPLAIN (VERBOSE)` | No | No | No | See output columns, schema-qualified names, exact target lists |
| `EXPLAIN (SETTINGS)` | No | No | No | Show non-default GUC settings that affect planning |
| `EXPLAIN (WAL)` | **YES** | No | No | See WAL bytes generated (useful for write-heavy queries) |
| `EXPLAIN (ANALYZE, SUMMARY)` | **YES** | Yes | No | Adds planning time + execution time summary (on by default with ANALYZE) |

### When to Use What - Decision Tree

```
Is this a SELECT? (read-only, safe to execute)
  |-- YES --> EXPLAIN (ANALYZE, BUFFERS) -- your bread and butter
  |-- NO (INSERT/UPDATE/DELETE)
       |-- Safe to execute in a transaction?
       |    |-- YES --> BEGIN; EXPLAIN (ANALYZE, BUFFERS) ...; ROLLBACK;
       |    |-- NO --> EXPLAIN only (plan without execution)
       |
       |-- Need WAL impact? --> EXPLAIN (ANALYZE, WAL, BUFFERS) inside BEGIN/ROLLBACK

Need to share the plan with someone?
  --> EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON) then paste into explain.dalibo.com

Getting weird plans you can't explain?
  --> EXPLAIN (VERBOSE, SETTINGS) to see what's happening under the hood

Dealing with queries that have 1000s of loop iterations?
  --> EXPLAIN (ANALYZE, BUFFERS, TIMING OFF) to reduce measurement overhead
```

### CRITICAL: EXPLAIN vs EXPLAIN ANALYZE

```sql
-- EXPLAIN: Shows what the planner THINKS will happen
-- Does NOT execute the query. Safe for anything. Shows ESTIMATES only.
EXPLAIN SELECT * FROM appointments WHERE appointment_date = '2024-06-15';

-- EXPLAIN ANALYZE: Shows what ACTUALLY happened
-- EXECUTES the query. Shows actual rows, actual time, loops.
-- WRAP DML IN A TRANSACTION IF YOU DON'T WANT SIDE EFFECTS!
BEGIN;
EXPLAIN ANALYZE DELETE FROM audit_log WHERE performed_at < '2023-01-01';
ROLLBACK;  -- Undo the delete but still see the plan
```

### Reading the Cost Numbers

```
Seq Scan on appointments  (cost=0.00..289543.00 rows=100 width=256)
                                ^        ^       ^        ^
                          startup cost  total   estimated  avg row
                          (before 1st   cost    rows       width in
                           row returned)         returned   bytes
```

- **startup cost**: Work before the first row can be returned (e.g., sort must finish before returning)
- **total cost**: Estimated total cost in arbitrary "cost units" (seq_page_cost = 1.0 by default)
- **rows**: Planner's estimate of rows returned (compare to actual in ANALYZE)
- **width**: Average row width in bytes

### The Buffer Output (Most Important for I/O Analysis)

```
Buffers: shared hit=45230 read=12500 dirtied=0 written=0
         ^              ^            ^          ^
         from cache     from disk    pages      pages written
                                     dirtied    to disk during
                                     by query   query
```

- **shared hit**: Pages found in shared_buffers (fast, from memory)
- **shared read**: Pages read from OS/disk (slow, I/O bound)
- **dirtied**: Pages the query modified
- **written**: Pages actually flushed to disk during this query

**Interview insight**: A high `read` to `hit` ratio means the working set doesn't fit in shared_buffers or the data was cold. After a second run, `read` should drop as data is cached.

---

## 3. Reading Execution Plans - Node by Node

Plans are read **bottom-up, inside-out**. The deepest indented nodes execute first. Each node is like a function that produces rows for its parent.

### Scan Nodes (Leaf Nodes - Where Data Comes From)

#### Seq Scan (Sequential Scan)

```sql
EXPLAIN (ANALYZE, BUFFERS) 
SELECT * FROM audit_log WHERE table_name = 'appointments';
```

```
Seq Scan on audit_log  (cost=0.00..512345.00 rows=5000000 width=280)
                        (actual time=0.045..3250.123 rows=5004521 loops=1)
  Filter: (table_name = 'appointments'::text)
  Rows Removed by Filter: 9995479
  Buffers: shared hit=12000 read=250345
```

**What it means**: Reading the entire table from beginning to end, applying a filter.

**When PostgreSQL chooses it**:
- No suitable index exists
- Query returns a large percentage of the table (usually >5-10%)
- Table is very small (cheaper to scan than look up index)
- `random_page_cost` is set high, making index scans look expensive

**Red flags**:
- "Rows Removed by Filter" is much larger than actual rows (filtering late)
- High `shared read` (reading from disk, not cache)
- Used on a large table for a selective query = missing index

**For SQL Server audience**: Equivalent to a Clustered Index Scan or Table Scan.


#### Index Scan

```sql
-- First, let's see what happens WITH the existing index
EXPLAIN (ANALYZE, BUFFERS) 
SELECT * FROM appointments WHERE patient_id = 42;
```

```
Index Scan using idx_appointments_patient_id on appointments
  (cost=0.43..58.50 rows=5 width=256)
  (actual time=0.025..0.142 rows=5 loops=1)
  Index Cond: (patient_id = 42)
  Buffers: shared hit=8
```

**What it means**: Uses the index to find matching rows, then fetches the full row from the heap (table).

**When chosen**: Selective queries returning a small fraction of the table.

**Key detail**: TWO I/O operations per row: index lookup + heap fetch. This is why it's not always faster than Seq Scan for large result sets.

**For SQL Server audience**: Like a Nonclustered Index Seek + Key Lookup (RID Lookup).


#### Index Only Scan

```sql
-- If the index covers all needed columns, no heap fetch needed
EXPLAIN (ANALYZE, BUFFERS) 
SELECT patient_id FROM appointments WHERE patient_id = 42;
```

```
Index Only Scan using idx_appointments_patient_id on appointments
  (cost=0.43..4.50 rows=5 width=4)
  (actual time=0.020..0.025 rows=5 loops=1)
  Index Cond: (patient_id = 42)
  Heap Fetches: 0
  Buffers: shared hit=4
```

**What it means**: All needed data is IN the index itself. No heap (table) access needed.

**Critical detail - Heap Fetches**: Even in an Index Only Scan, PostgreSQL may need to check the visibility map. If `Heap Fetches` > 0, the table has un-VACUUMed dead tuples, forcing heap checks.

**Red flag**: `Heap Fetches` close to total rows means the visibility map is outdated. Run `VACUUM` on the table.

**For SQL Server audience**: Like a Covering Index Scan/Seek - same concept, but PostgreSQL's MVCC means the visibility map check is an extra step SQL Server doesn't need.


#### Bitmap Index Scan + Bitmap Heap Scan

```sql
-- This pattern appears when result set is "medium" sized
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM appointments 
WHERE appointment_date BETWEEN '2024-01-01' AND '2024-01-31';
-- (Assuming we add an index for this demo)
```

```
Bitmap Heap Scan on appointments
  (cost=5432.10..98765.43 rows=280000 width=256)
  (actual time=45.123..890.456 rows=278543 loops=1)
  Recheck Cond: (appointment_date >= '2024-01-01' AND appointment_date <= '2024-01-31')
  Rows Removed by Recheck: 0
  Heap Blocks: exact=65432
  -> Bitmap Index Scan on idx_appointments_date
       (cost=0.00..5362.10 rows=280000 width=0)
       (actual time=38.234..38.234 rows=278543 loops=1)
       Index Cond: (appointment_date >= '2024-01-01' AND appointment_date <= '2024-01-31')
  Buffers: shared hit=40000 read=25432
```

**Two-phase operation**:
1. **Bitmap Index Scan**: Scans the index, builds a bitmap of which heap pages contain matching rows
2. **Bitmap Heap Scan**: Reads those heap pages in physical order (sequential I/O, much faster than random)

**When chosen**: Too many rows for Index Scan (random I/O too expensive) but too few for Seq Scan.

**Recheck Cond**: When the bitmap gets too large for `work_mem`, it becomes "lossy" - it tracks pages instead of individual tuples. The recheck applies the filter again to each tuple on those pages.

**Red flag**: `Rows Removed by Recheck` > 0 means the bitmap went lossy. Consider increasing `work_mem`.

**For SQL Server audience**: No direct equivalent - this is unique to PostgreSQL. Closest conceptually is a combination of Index Seek + RID Lookup but batched and sorted by page.


### Join Nodes

#### Nested Loop Join

```sql
EXPLAIN (ANALYZE, BUFFERS)
SELECT a.appointment_id, p.first_name, p.last_name
FROM appointments a
JOIN providers p ON a.provider_id = p.provider_id
WHERE p.specialty = 'cardiology' AND a.status = 'scheduled';
```

**How it works**: For each row from the outer (top) table, scan the inner (bottom) table.

**When chosen**:
- Inner side has an efficient index
- Outer side returns few rows
- Small result sets where random access is acceptable

**Key metric - loops**: The `loops` count on the inner side tells you how many times it was scanned. `actual time` and `rows` are PER LOOP, so multiply:
- Total rows = `actual rows` x `loops`
- Total time = `actual time` x `loops`

**Red flag**: High loop count with Seq Scan on inner side = catastrophic performance.

**For SQL Server audience**: Same concept - Nested Loops Join.


#### Hash Join

```sql
EXPLAIN (ANALYZE, BUFFERS)
SELECT a.*, p.first_name, p.last_name
FROM appointments a
JOIN patients p ON a.patient_id = p.patient_id
WHERE a.appointment_date = '2024-06-15';
```

**How it works**:
1. Builds a hash table from the smaller (inner/build) input
2. Probes the hash table with each row from the larger (outer/probe) input

**When chosen**: No useful index on join column, or both sides are large.

**Watch for**:
- `Batches: 1` is good (fits in work_mem)
- `Batches: > 1` means hash table spilled to disk (slow!) - increase `work_mem`
- `Memory Usage: XXkB` shows hash table size

**For SQL Server audience**: Same concept - Hash Match.


#### Merge Join

```sql
EXPLAIN (ANALYZE, BUFFERS)
SELECT a.*, s.*
FROM appointments a
JOIN shifts s ON a.provider_id = s.provider_id AND a.appointment_date = s.shift_date
ORDER BY a.provider_id, a.appointment_date;
```

**How it works**: Both inputs must be sorted on the join key. Walks through both in parallel.

**When chosen**:
- Both inputs are already sorted (index provides order)
- Large datasets where hash won't fit in memory
- Query also needs ORDER BY on the join key

**Key detail**: Often preceded by Sort nodes unless an index provides the order.

**For SQL Server audience**: Same concept - Merge Join. PostgreSQL is pickier about using it.


### Aggregate/Sort Nodes

#### Sort

```
Sort  (cost=1234.56..1240.00 rows=5000 width=100)
  Sort Key: appointment_date
  Sort Method: quicksort  Memory: 1024kB    <-- GOOD: in-memory
  -- OR --
  Sort Method: external merge  Disk: 15360kB  <-- BAD: spilled to disk
```

**Red flag**: `external merge Disk: XXkB` means `work_mem` is too small. The sort spilled to temp files.

#### HashAggregate vs GroupAggregate

- **HashAggregate**: Builds a hash table of groups. Fast for moderate group counts. Can spill to disk if too many groups.
- **GroupAggregate**: Requires sorted input. Better for very large number of groups or when input is already sorted.

#### WindowAgg

Window functions (`ROW_NUMBER()`, `RANK()`, `LAG()`, `LEAD()`, etc.) produce a WindowAgg node. The input MUST be sorted on the PARTITION BY + ORDER BY columns.


### Parallel Query Nodes

#### Gather / Gather Merge

```
Gather  (cost=1000.00..234567.89 rows=5000000 width=256)
  Workers Planned: 2
  Workers Launched: 2
  -> Parallel Seq Scan on appointments
       (cost=0.00..200000.00 rows=2083333 width=256)
```

- **Gather**: Collects results from parallel workers (no ordering guarantee)
- **Gather Merge**: Collects results preserving sort order from workers

**Key metric**: `Workers Launched` should equal `Workers Planned`. If fewer launched, the system was under resource pressure.

**Red flags**:
- `Workers Launched: 0` with `Workers Planned: 2` = all workers busy, fell back to serial
- Parallel plan for a tiny result set = overhead not worth it


### Other Important Nodes

#### CTE Scan

```sql
EXPLAIN (ANALYZE, BUFFERS)
WITH recent AS (
    SELECT * FROM appointments WHERE appointment_date > CURRENT_DATE - 30
)
SELECT * FROM recent WHERE status = 'cancelled';
```

**Pre-PG12**: CTEs were ALWAYS materialized (optimization fence). The CTE result was fully computed and stored before being scanned.

**PG12+**: CTEs can be inlined (treated like subqueries) UNLESS:
- The CTE is referenced more than once
- The CTE is recursive
- The CTE has side effects (INSERT/UPDATE/DELETE)
- You force materialization: `WITH recent AS MATERIALIZED (...)`

**Interview gotcha**: If you see a CTE Scan node with poor performance, check the PG version. Pre-12 = rewrite as subquery. Post-12 = planner should inline it, but check with `MATERIALIZED`/`NOT MATERIALIZED`.


#### Recursive Union (Recursive CTEs)

```sql
EXPLAIN (ANALYZE, BUFFERS)
WITH RECURSIVE referral_chain AS (
    -- Base case: direct referrals from provider 100
    SELECT referral_id, patient_id, referring_provider_id, 
           referred_to_provider_id, 1 AS depth
    FROM referrals
    WHERE referring_provider_id = 100
    
    UNION ALL
    
    -- Recursive case: follow the chain
    SELECT r.referral_id, r.patient_id, r.referring_provider_id,
           r.referred_to_provider_id, rc.depth + 1
    FROM referrals r
    JOIN referral_chain rc ON r.referring_provider_id = rc.referred_to_provider_id
    WHERE rc.depth < 5
)
SELECT * FROM referral_chain;
```

**Node structure**:
```
CTE Scan on referral_chain
  -> Recursive Union
       -> Index Scan (base case)
       -> Nested Loop (recursive step - executed repeatedly)
```

**Key detail**: The recursive term executes repeatedly until it returns no rows. Watch the `loops` count.

---

## 4. Key Metrics & Red Flags

### The Diagnostic Checklist (Memorize This)

When you see a slow plan, check THESE things in THIS order:

1. **Estimated vs Actual Rows** - The #1 source of bad plans
   - If estimated = 100 but actual = 1,000,000 - the planner chose the wrong strategy
   - Fix: `ANALYZE` the table, increase `default_statistics_target`, create extended statistics

2. **Seq Scans on large tables with small result sets**
   - Missing index or planner thinks the table is smaller than it is

3. **Rows Removed by Filter** - Wasted work
   - Large number = filtering happening too late (after reading rows)
   - Want: filtering to happen in the index (Index Cond) not in Filter

4. **Loops multiplier**
   - `actual time=0.5..1.0 rows=1 loops=500000` = 500,000ms total!
   - Per-iteration looks fast but multiply by loops

5. **Buffers: shared read >> shared hit**
   - Data is cold or working set exceeds cache
   - Second execution should show more hits

6. **Sort Method: external merge Disk**
   - Sort spilled to disk. Increase `work_mem`.

7. **Hash Batches > 1**
   - Hash join spilled to disk. Increase `work_mem`.

8. **Heap Fetches on Index Only Scan**
   - Table needs VACUUM to update visibility map

9. **Rows Removed by Recheck**
   - Bitmap went lossy. Increase `work_mem`.

10. **Workers Launched < Workers Planned**
    - Parallel execution degraded. Check `max_parallel_workers`.


### The Formula for Actual Totals in Looped Nodes

```
ACTUAL total rows = rows * loops
ACTUAL total time = time * loops (approximately)
ACTUAL total buffers = buffers * loops (EXCEPT shared hit/read are already totals in PG 13+)
```

**WARNING**: In PG versions before 13, buffer counts in EXPLAIN ANALYZE were per-loop. In PG 13+, they're totals. Know your version!

---

## 5. Progressive Exercises

### Exercise 1 - Basic Scan Types (Easy)

**Goal**: See the difference between Seq Scan, Index Scan, and no-index scenarios.

```sql
-- 1A: Seq Scan (no index on status column)
EXPLAIN (ANALYZE, BUFFERS) 
SELECT * FROM appointments WHERE status = 'cancelled';

-- OBSERVE:
-- - Seq Scan node
-- - Rows Removed by Filter (how many rows were read but didn't match)
-- - Buffer reads (entire table scanned)
-- - Actual rows vs estimated rows
```

**What to look for**: The planner must read ALL ~10M rows to find the cancelled ones. Note the "Rows Removed by Filter" - this is wasted work.

```sql
-- 1B: Index Scan (patient_id has an index)
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM appointments WHERE patient_id = 12345;

-- OBSERVE:
-- - Index Scan node
-- - Very few buffer reads
-- - No "Rows Removed by Filter" (filtering happened in the index)
-- - Index Cond vs Filter
```

```sql
-- 1C: Force a Seq Scan to compare (NEVER do this in production)
SET enable_indexscan = off;
SET enable_bitmapscan = off;
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM appointments WHERE patient_id = 12345;
RESET enable_indexscan;
RESET enable_bitmapscan;

-- OBSERVE:
-- - Same query, dramatically different cost and time
-- - Seq Scan with Filter instead of Index Cond
```


### Exercise 2 - Estimated vs Actual Row Mismatch (Easy-Medium)

**Goal**: See what happens when the planner gets the row count wrong.

```sql
-- 2A: Query on a skewed column (risk_score in patients)
-- Most patients have risk_score 0-2, very few have 8-10
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM patients WHERE risk_score > 8.0;

-- The planner might estimate WAY too many or too few rows
-- because default statistics may not capture the skew well

-- 2B: Check the stats
SELECT attname, n_distinct, most_common_vals, most_common_freqs, histogram_bounds
FROM pg_stats 
WHERE tablename = 'patients' AND attname = 'risk_score';

-- 2C: Increase statistics target and re-analyze
ALTER TABLE patients ALTER COLUMN risk_score SET STATISTICS 1000;
ANALYZE patients;

-- 2D: Run the query again and compare estimates
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM patients WHERE risk_score > 8.0;
```


### Exercise 3 - Join Strategies (Medium)

**Goal**: See PostgreSQL choose different join strategies.

```sql
-- 3A: Nested Loop (small outer, indexed inner)
EXPLAIN (ANALYZE, BUFFERS)
SELECT a.appointment_id, p.first_name, p.last_name, p.specialty
FROM appointments a
JOIN providers p ON a.provider_id = p.provider_id
WHERE a.patient_id = 42;

-- OBSERVE: Nested Loop with Index Scan on providers (small result from appointments)

-- 3B: Hash Join (large result, no useful index on join key for this query pattern)
EXPLAIN (ANALYZE, BUFFERS)
SELECT a.appointment_id, a.appointment_date, p.first_name, p.last_name
FROM appointments a
JOIN patients p ON a.patient_id = p.patient_id
WHERE a.appointment_date BETWEEN '2024-01-01' AND '2024-03-31';

-- OBSERVE: Hash Join (too many rows for Nested Loop, no sorted input for Merge Join)

-- 3C: See the join order change with different filters
EXPLAIN (ANALYZE, BUFFERS)
SELECT a.appointment_id, f.facility_name, d.dept_name, p.last_name
FROM appointments a
JOIN facilities f ON a.facility_id = f.facility_id
JOIN departments d ON a.department_id = d.department_id
JOIN providers p ON a.provider_id = p.provider_id
WHERE f.state = 'OH' AND a.status = 'scheduled';
```


### Exercise 4 - The Bitmap Scan Pattern (Medium)

**Goal**: Understand when and why bitmap scans appear.

```sql
-- Create an index we'll need for this exercise
CREATE INDEX idx_appointments_date ON appointments(appointment_date);
ANALYZE appointments;

-- 4A: Very selective - should use Index Scan
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM appointments WHERE appointment_date = '2024-06-15';

-- 4B: Moderately selective - should switch to Bitmap Scan
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM appointments 
WHERE appointment_date BETWEEN '2024-06-01' AND '2024-06-30';

-- 4C: Very wide range - should switch to Seq Scan (most of the table)
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM appointments 
WHERE appointment_date BETWEEN '2023-01-01' AND '2024-12-31';

-- 4D: BitmapAnd / BitmapOr (combining multiple indexes)
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM appointments 
WHERE patient_id = 42 AND appointment_date = '2024-06-15';

-- OBSERVE: May see BitmapAnd combining two Bitmap Index Scans
-- Compare this to: what if we had a composite index instead?

-- Drop the index after exercise (we want it missing for later exercises)
-- DROP INDEX idx_appointments_date;
```


### Exercise 5 - CTEs and Materialization (Medium-Hard)

**Goal**: Understand CTE materialization behavior.

```sql
-- 5A: CTE that should be inlined (PG12+)
EXPLAIN (ANALYZE, BUFFERS)
WITH recent_appts AS (
    SELECT * FROM appointments 
    WHERE appointment_date > CURRENT_DATE - 30
)
SELECT ra.*, p.last_name
FROM recent_appts ra
JOIN providers p ON ra.provider_id = p.provider_id
WHERE ra.status = 'scheduled';

-- OBSERVE: No "CTE Scan" node - the CTE was inlined as a subquery

-- 5B: Force materialization (creates optimization fence)
EXPLAIN (ANALYZE, BUFFERS)
WITH recent_appts AS MATERIALIZED (
    SELECT * FROM appointments 
    WHERE appointment_date > CURRENT_DATE - 30
)
SELECT ra.*, p.last_name
FROM recent_appts ra
JOIN providers p ON ra.provider_id = p.provider_id
WHERE ra.status = 'scheduled';

-- OBSERVE: CTE Scan node appears. Filter on status happens AFTER materialization.
-- Compare costs between 5A and 5B.

-- 5C: CTE referenced twice (always materializes)
EXPLAIN (ANALYZE, BUFFERS)
WITH provider_stats AS (
    SELECT provider_id, COUNT(*) AS appt_count, 
           AVG(copay_amount) AS avg_copay
    FROM appointments
    GROUP BY provider_id
)
SELECT 
    (SELECT COUNT(*) FROM provider_stats WHERE appt_count > 2000) AS high_volume,
    (SELECT COUNT(*) FROM provider_stats WHERE avg_copay > 100) AS high_copay;
```


### Exercise 6 - Recursive CTE (Hard)

**Goal**: Understand recursive query execution.

```sql
-- 6A: Referral chain traversal
EXPLAIN (ANALYZE, BUFFERS)
WITH RECURSIVE referral_chain AS (
    SELECT r.referral_id, r.patient_id, 
           r.referring_provider_id, r.referred_to_provider_id,
           1 AS depth,
           ARRAY[r.referring_provider_id] AS path
    FROM referrals r
    WHERE r.referring_provider_id = 100
    
    UNION ALL
    
    SELECT r.referral_id, r.patient_id,
           r.referring_provider_id, r.referred_to_provider_id,
           rc.depth + 1,
           rc.path || r.referring_provider_id
    FROM referrals r
    JOIN referral_chain rc ON r.referring_provider_id = rc.referred_to_provider_id
    WHERE rc.depth < 5
    AND NOT r.referring_provider_id = ANY(rc.path)  -- cycle prevention
)
SELECT rc.*, p.first_name, p.last_name
FROM referral_chain rc
JOIN providers p ON rc.referred_to_provider_id = p.provider_id;

-- OBSERVE:
-- - Recursive Union node
-- - WorkTable Scan
-- - How many loops the recursive step executed
-- - Whether the referrals table needs an index on referring_provider_id
```


### Exercise 7 - Window Functions (Hard)

**Goal**: Understand WindowAgg and sort requirements.

```sql
-- 7A: ROW_NUMBER for deduplication
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM (
    SELECT a.*,
           ROW_NUMBER() OVER (
               PARTITION BY a.patient_id 
               ORDER BY a.appointment_date DESC
           ) AS rn
    FROM appointments a
    WHERE a.status = 'completed'
) sub
WHERE rn = 1;

-- OBSERVE:
-- - WindowAgg node
-- - Sort node underneath (for PARTITION BY + ORDER BY)
-- - Whether the Sort spills to disk
-- - SubqueryScan node
-- - How the outer filter (rn = 1) is applied

-- 7B: Multiple window functions
EXPLAIN (ANALYZE, BUFFERS)
SELECT 
    provider_id,
    appointment_date,
    COUNT(*) OVER (PARTITION BY provider_id) AS total_appts,
    ROW_NUMBER() OVER (PARTITION BY provider_id ORDER BY appointment_date) AS appt_num,
    LAG(appointment_date) OVER (PARTITION BY provider_id ORDER BY appointment_date) AS prev_date
FROM appointments
WHERE provider_id IN (1, 2, 3);

-- OBSERVE: May see multiple WindowAgg nodes if different sort orders needed
```


### Exercise 8 - Parallel Query (Hard)

**Goal**: Understand parallel execution and its limits.

```sql
-- 8A: Query that triggers parallel execution
EXPLAIN (ANALYZE, BUFFERS)
SELECT status, COUNT(*), AVG(copay_amount)
FROM appointments
GROUP BY status;

-- OBSERVE:
-- - Gather or Gather Merge node
-- - Parallel Seq Scan underneath
-- - Partial HashAggregate (each worker aggregates its portion)
-- - Finalize HashAggregate (combines worker results)
-- - Workers Planned vs Workers Launched

-- 8B: Force serial to compare
SET max_parallel_workers_per_gather = 0;
EXPLAIN (ANALYZE, BUFFERS)
SELECT status, COUNT(*), AVG(copay_amount)
FROM appointments
GROUP BY status;
RESET max_parallel_workers_per_gather;

-- Compare total execution time between parallel and serial
```

---

## 6. HypoPG Workflow Exercises

### Exercise H1 - Basic HypoPG Workflow

**Scenario**: The `audit_log` table has NO indexes beyond the PK. Queries filtering by `table_name` and `performed_at` are slow.

```sql
-- Step 1: See the current (bad) plan
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM audit_log 
WHERE table_name = 'appointments' 
AND performed_at > NOW() - INTERVAL '7 days'
ORDER BY performed_at DESC
LIMIT 100;

-- Record: cost=_____, actual time=_____, buffers read=_____

-- Step 2: Reset and create hypothetical index
SELECT hypopg_reset();
SELECT * FROM hypopg_create_index(
    'CREATE INDEX ON audit_log(table_name, performed_at DESC)'
);

-- Step 3: Check plan with hypothetical index (EXPLAIN only, not ANALYZE!)
EXPLAIN 
SELECT * FROM audit_log 
WHERE table_name = 'appointments' 
AND performed_at > NOW() - INTERVAL '7 days'
ORDER BY performed_at DESC
LIMIT 100;

-- Record: estimated cost=_____
-- Compare with Step 1's cost. Big reduction? Good index candidate.

-- Step 4: Try alternative index strategies
SELECT hypopg_reset();

-- Option A: Reversed column order
SELECT * FROM hypopg_create_index(
    'CREATE INDEX ON audit_log(performed_at DESC, table_name)'
);
EXPLAIN 
SELECT * FROM audit_log 
WHERE table_name = 'appointments' 
AND performed_at > NOW() - INTERVAL '7 days'
ORDER BY performed_at DESC
LIMIT 100;

-- Option B: Include columns (covering index)
SELECT hypopg_reset();
SELECT * FROM hypopg_create_index(
    'CREATE INDEX ON audit_log(table_name, performed_at DESC) INCLUDE (action, performed_by)'
);
EXPLAIN 
SELECT action, performed_by, performed_at FROM audit_log 
WHERE table_name = 'appointments' 
AND performed_at > NOW() - INTERVAL '7 days'
ORDER BY performed_at DESC
LIMIT 100;

-- Step 5: Pick the winner and create the real index
SELECT hypopg_reset();
CREATE INDEX CONCURRENTLY idx_audit_tablename_date 
ON audit_log(table_name, performed_at DESC);

-- Step 6: ANALYZE and validate with real execution
ANALYZE audit_log;
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM audit_log 
WHERE table_name = 'appointments' 
AND performed_at > NOW() - INTERVAL '7 days'
ORDER BY performed_at DESC
LIMIT 100;

-- Step 7: PROVE the improvement
-- Record: actual time=_____, buffers=_____
-- Compare with Step 1. Quantify: "Index reduced execution from X ms to Y ms, 
-- buffer reads from A to B"
```


### Exercise H2 - When HypoPG Says "No"

**Scenario**: Not every index helps.

```sql
-- Query: count of appointments by status
EXPLAIN (ANALYZE, BUFFERS)
SELECT status, COUNT(*) FROM appointments GROUP BY status;

-- Try adding an index on status
SELECT hypopg_reset();
SELECT * FROM hypopg_create_index('CREATE INDEX ON appointments(status)');

-- Check: Does the planner use it?
EXPLAIN SELECT status, COUNT(*) FROM appointments GROUP BY status;

-- LIKELY RESULT: Planner still chooses Seq Scan!
-- WHY? There are only ~8 distinct status values across 10M rows.
-- An index scan would touch almost every page anyway.
-- The planner correctly decides Seq Scan is cheaper.

-- LESSON: Don't blindly index. Low-cardinality columns on large tables
-- rarely benefit from B-tree indexes for aggregate queries.

SELECT hypopg_reset();
```


### Exercise H3 - Composite Index Column Order Matters

```sql
-- Query: Find appointments for a specific provider on a specific date
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM appointments 
WHERE provider_id = 500 AND appointment_date = '2024-06-15';

-- Try: (provider_id, appointment_date)
SELECT hypopg_reset();
SELECT * FROM hypopg_create_index(
    'CREATE INDEX ON appointments(provider_id, appointment_date)'
);
EXPLAIN SELECT * FROM appointments 
WHERE provider_id = 500 AND appointment_date = '2024-06-15';
-- Record cost: _____

-- Try: (appointment_date, provider_id)
SELECT hypopg_reset();
SELECT * FROM hypopg_create_index(
    'CREATE INDEX ON appointments(appointment_date, provider_id)'
);
EXPLAIN SELECT * FROM appointments 
WHERE provider_id = 500 AND appointment_date = '2024-06-15';
-- Record cost: _____

-- For equality on both: order doesn't matter much (both are equally selective)
-- But for range queries, leading column matters more:

EXPLAIN SELECT * FROM appointments 
WHERE provider_id = 500 
AND appointment_date BETWEEN '2024-06-01' AND '2024-06-30';

-- The (provider_id, appointment_date) index is MUCH better here because
-- equality match on provider_id narrows to ~2000 rows, then range scan on date.
-- With (appointment_date, provider_id), the range scan on date is wider.

SELECT hypopg_reset();
```

---

## 7. Anti-Patterns & Interview Gotchas

### Gotcha 1: Index That Makes Things Worse

```sql
-- Scenario: Query returns most of the table
-- A covering Seq Scan is cheaper than millions of random index lookups

EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM appointments WHERE status = 'completed';

-- 'completed' is ~60% of all rows (6 million).
-- Even WITH an index on status, the planner should choose Seq Scan.
-- If someone adds the index and forces it:

-- CREATE INDEX idx_appt_status ON appointments(status);
-- SET enable_seqscan = off;
-- EXPLAIN (ANALYZE, BUFFERS) SELECT * FROM appointments WHERE status = 'completed';
-- RESET enable_seqscan;

-- The Index Scan will be SLOWER because:
-- 6 million random heap fetches > 1 sequential table scan
```


### Gotcha 2: Stale Statistics

```sql
-- After a big data load or bulk update, stats may be wrong
-- Simulate by checking current stats:

SELECT relname, n_live_tup, last_analyze, last_autoanalyze
FROM pg_stat_user_tables
WHERE relname = 'appointments';

-- If you see bad estimates in EXPLAIN ANALYZE, first thing to try:
ANALYZE appointments;
-- Then re-run the query
```


### Gotcha 3: Correlated Columns (Extended Statistics)

```sql
-- The planner assumes columns are independent.
-- city and state are CORRELATED (city='Atlanta' implies state='GA')

EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM patients WHERE city = 'Atlanta' AND state = 'GA';

-- The planner may estimate: 
--   P(city='Atlanta') * P(state='GA') * total_rows
-- This underestimates because EVERY Atlanta patient is in GA.

-- Fix with extended statistics:
CREATE STATISTICS patients_city_state (dependencies) 
ON city, state FROM patients;
ANALYZE patients;

-- Re-run and compare estimates
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM patients WHERE city = 'Atlanta' AND state = 'GA';
```


### Gotcha 4: CTE Materialization Fence

```sql
-- Pre-PG12 behavior (or MATERIALIZED keyword):
EXPLAIN (ANALYZE, BUFFERS)
WITH all_appts AS MATERIALIZED (
    SELECT * FROM appointments
)
SELECT * FROM all_appts WHERE patient_id = 42;

-- The CTE materializes ALL 10M rows, then filters for patient 42.
-- Without MATERIALIZED (PG12+), the planner can push the filter down.

EXPLAIN (ANALYZE, BUFFERS)
WITH all_appts AS (
    SELECT * FROM appointments
)
SELECT * FROM all_appts WHERE patient_id = 42;

-- Compare execution times. The inlined version uses the index!
```


### Gotcha 5: enable_seqscan = off is Testing Only

```sql
-- This is useful to SEE what plan the optimizer would pick if forced
-- NEVER use in production - it doesn't disable seq scans,
-- it makes them cost 10^10 which breaks cost comparisons

SET enable_seqscan = off;
EXPLAIN SELECT * FROM appointments WHERE patient_id = 42;
RESET enable_seqscan;

-- In an interview, demonstrate you KNOW this tool exists for testing
-- but immediately state it's never a production solution.
-- The right fix is always: proper indexing, better statistics, or query rewrite.
```


### Gotcha 6: VACUUM/ANALYZE Impact on Plan Quality

```sql
-- Check table bloat indicators
SELECT 
    schemaname, relname,
    n_live_tup, n_dead_tup,
    ROUND(n_dead_tup::NUMERIC / GREATEST(n_live_tup, 1) * 100, 2) AS dead_pct,
    last_vacuum, last_autovacuum,
    last_analyze, last_autoanalyze
FROM pg_stat_user_tables
WHERE relname IN ('appointments', 'audit_log', 'patients')
ORDER BY n_dead_tup DESC;

-- If dead_pct > 20%, plan quality degrades because:
-- 1. Statistics may not reflect current data
-- 2. Index Only Scans need heap fetches (stale visibility map)
-- 3. Tables are physically larger (more pages to scan)

-- Fix:
VACUUM ANALYZE appointments;
```

---

## 8. Speed Drills (Timed Interview Simulations)

**Instructions**: Set a timer. Read the query. Run EXPLAIN (ANALYZE, BUFFERS). Diagnose. Fix. Prove.

### Speed Drill 1 (5 minutes) - The Missing Index

```sql
-- SCENARIO: Users report the "recent audit" page is slow
-- Your task: Diagnose and fix

EXPLAIN (ANALYZE, BUFFERS)
SELECT al.*, p.first_name || ' ' || p.last_name AS performer
FROM audit_log al
LEFT JOIN providers p ON al.performed_by = p.provider_id
WHERE al.table_name = 'appointments'
AND al.action = 'UPDATE'
AND al.performed_at > NOW() - INTERVAL '24 hours'
ORDER BY al.performed_at DESC
LIMIT 50;

-- TARGET: Identify Seq Scan on audit_log, propose composite index,
-- test with HypoPG, create, validate. Under 5 minutes.
```

<details>
<summary>Solution</summary>

1. The bottleneck is Seq Scan on audit_log (15M rows scanned for ~50 results)
2. Create composite index: `(table_name, action, performed_at DESC)`
3. HypoPG test: `SELECT * FROM hypopg_create_index('CREATE INDEX ON audit_log(table_name, action, performed_at DESC)');`
4. Verify with EXPLAIN (plan should show Index Scan)
5. Create real index: `CREATE INDEX CONCURRENTLY idx_audit_lookup ON audit_log(table_name, action, performed_at DESC);`
6. `ANALYZE audit_log;`
7. Re-run EXPLAIN (ANALYZE, BUFFERS) - should see Index Scan, <10ms, minimal buffer reads
</details>


### Speed Drill 2 (5 minutes) - Bad Join Strategy

```sql
-- SCENARIO: Provider dashboard showing appointment counts is slow

EXPLAIN (ANALYZE, BUFFERS)
SELECT p.provider_id, p.first_name, p.last_name, p.specialty,
       COUNT(a.appointment_id) AS total_appointments,
       COUNT(CASE WHEN a.status = 'cancelled' THEN 1 END) AS cancelled_count,
       COUNT(CASE WHEN a.is_telehealth THEN 1 END) AS telehealth_count
FROM providers p
LEFT JOIN appointments a ON p.provider_id = a.provider_id
WHERE p.is_active = true
GROUP BY p.provider_id, p.first_name, p.last_name, p.specialty
ORDER BY total_appointments DESC
LIMIT 20;

-- TARGET: This will aggregate ALL 10M appointments. 
-- Identify the problem and propose optimizations.
```

<details>
<summary>Solution</summary>

The problem is aggregating all 10M appointment rows. Solutions (from best to worst):

1. **Rewrite with a subquery/lateral join**: Only aggregate what's needed
```sql
SELECT p.provider_id, p.first_name, p.last_name, p.specialty,
       a_stats.total_appointments, a_stats.cancelled_count, a_stats.telehealth_count
FROM providers p
LEFT JOIN LATERAL (
    SELECT COUNT(*) AS total_appointments,
           COUNT(*) FILTER (WHERE status = 'cancelled') AS cancelled_count,
           COUNT(*) FILTER (WHERE is_telehealth) AS telehealth_count
    FROM appointments a
    WHERE a.provider_id = p.provider_id
) a_stats ON true
WHERE p.is_active = true
ORDER BY a_stats.total_appointments DESC
LIMIT 20;
```

2. **Add a covering index**: `CREATE INDEX ON appointments(provider_id) INCLUDE (status, is_telehealth);`

3. **Materialized view** for dashboard (pre-computed)
</details>


### Speed Drill 3 (7 minutes) - Misleading Plan

```sql
-- SCENARIO: This query "sometimes" runs slow, sometimes fast

EXPLAIN (ANALYZE, BUFFERS)
SELECT a.appointment_id, a.appointment_date, a.status,
       p.first_name, p.last_name, p.risk_score
FROM appointments a
JOIN patients p ON a.patient_id = p.patient_id
WHERE p.risk_score > 9.0
AND a.appointment_date > CURRENT_DATE - INTERVAL '90 days'
AND a.status = 'scheduled';

-- RUN IT TWICE. The second run may be much faster (buffer cache).
-- The REAL question: is the plan itself efficient, or just cached?

-- TARGET: Look at buffer reads vs hits across runs.
-- Identify whether the plan is actually good or just benefiting from warm cache.
-- Consider: what would happen under production load with cold cache?
```

<details>
<summary>Solution</summary>

1. First run: high `shared read` = cold cache
2. Second run: high `shared hit` = warm cache, BUT the plan is still doing excessive work
3. Check estimated vs actual rows on `risk_score > 9.0` - likely WAY off (skewed distribution)
4. The real fix is a partial index:
```sql
CREATE INDEX idx_patients_high_risk ON patients(patient_id) WHERE risk_score > 9.0;
CREATE INDEX idx_appts_recent_scheduled ON appointments(patient_id, appointment_date) 
WHERE status = 'scheduled' AND appointment_date > CURRENT_DATE - INTERVAL '90 days';
```
5. Also: `ALTER TABLE patients ALTER COLUMN risk_score SET STATISTICS 1000; ANALYZE patients;`
</details>


### Speed Drill 4 (7 minutes) - The N+1 Query Pattern

```sql
-- SCENARIO: Application is running this in a loop for each facility (50 times!)
-- Simulate the performance impact

EXPLAIN (ANALYZE, BUFFERS)
SELECT f.facility_name,
       (SELECT COUNT(*) FROM appointments a 
        WHERE a.facility_id = f.facility_id 
        AND a.status = 'scheduled') AS scheduled_count,
       (SELECT COUNT(*) FROM appointments a 
        WHERE a.facility_id = f.facility_id 
        AND a.appointment_date = CURRENT_DATE) AS today_count,
       (SELECT COUNT(*) FROM shifts s 
        WHERE s.facility_id = f.facility_id 
        AND s.shift_date = CURRENT_DATE) AS today_shifts
FROM facilities f
WHERE f.is_active = true;

-- TARGET: Each subquery is a separate scan. Identify and rewrite.
```

<details>
<summary>Solution</summary>

```sql
-- Rewrite with explicit JOINs and conditional aggregation
SELECT f.facility_name,
       COALESCE(a_stats.scheduled_count, 0) AS scheduled_count,
       COALESCE(a_stats.today_count, 0) AS today_count,
       COALESCE(s_stats.today_shifts, 0) AS today_shifts
FROM facilities f
LEFT JOIN (
    SELECT facility_id,
           COUNT(*) FILTER (WHERE status = 'scheduled') AS scheduled_count,
           COUNT(*) FILTER (WHERE appointment_date = CURRENT_DATE) AS today_count
    FROM appointments
    WHERE status = 'scheduled' OR appointment_date = CURRENT_DATE
    GROUP BY facility_id
) a_stats ON f.facility_id = a_stats.facility_id
LEFT JOIN (
    SELECT facility_id, COUNT(*) AS today_shifts
    FROM shifts
    WHERE shift_date = CURRENT_DATE
    GROUP BY facility_id
) s_stats ON f.facility_id = s_stats.facility_id
WHERE f.is_active = true;

-- Also: add indexes
CREATE INDEX idx_appt_facility_status ON appointments(facility_id, status);
CREATE INDEX idx_appt_facility_date ON appointments(facility_id, appointment_date);
CREATE INDEX idx_shift_facility_date ON shifts(facility_id, shift_date);
```
</details>


### Speed Drill 5 (5 minutes) - JSONB Query Performance

```sql
-- SCENARIO: Finding patients with specific allergies (stored in JSONB)

EXPLAIN (ANALYZE, BUFFERS)
SELECT patient_id, first_name, last_name, medical_history
FROM patients
WHERE medical_history -> 'allergies' @> '["penicillin"]'::jsonb;

-- TARGET: Identify that JSONB containment without a GIN index = Seq Scan.
-- Create appropriate index and validate.
```

<details>
<summary>Solution</summary>

```sql
-- Create GIN index on the JSONB column (or specific path)
CREATE INDEX idx_patients_medical_gin ON patients USING GIN (medical_history);
-- OR more targeted:
CREATE INDEX idx_patients_allergies_gin ON patients USING GIN ((medical_history -> 'allergies'));

ANALYZE patients;

-- Validate
EXPLAIN (ANALYZE, BUFFERS)
SELECT patient_id, first_name, last_name, medical_history
FROM patients
WHERE medical_history -> 'allergies' @> '["penicillin"]'::jsonb;

-- Should now show Bitmap Index Scan using the GIN index
```
</details>


### Speed Drill 6 (10 minutes) - Full Diagnostic Workflow

```sql
-- SCENARIO: This report runs nightly and takes 45 minutes. Fix it.

EXPLAIN (ANALYZE, BUFFERS)
SELECT 
    f.facility_name,
    d.dept_name,
    p.specialty,
    DATE_TRUNC('month', a.appointment_date) AS month,
    COUNT(*) AS total_appointments,
    COUNT(*) FILTER (WHERE a.status = 'completed') AS completed,
    COUNT(*) FILTER (WHERE a.status = 'cancelled') AS cancelled,
    COUNT(*) FILTER (WHERE a.status = 'no_show') AS no_shows,
    ROUND(AVG(a.copay_amount), 2) AS avg_copay,
    ROUND(SUM(a.insurance_billed), 2) AS total_billed
FROM appointments a
JOIN facilities f ON a.facility_id = f.facility_id
JOIN departments d ON a.department_id = d.department_id
JOIN providers p ON a.provider_id = p.provider_id
WHERE a.appointment_date BETWEEN '2024-01-01' AND '2024-12-31'
GROUP BY f.facility_name, d.dept_name, p.specialty, 
         DATE_TRUNC('month', a.appointment_date)
ORDER BY f.facility_name, d.dept_name, month;

-- TARGET: Multi-step optimization:
-- 1. Add missing indexes for filter and join columns
-- 2. Consider work_mem for large hash joins and sorts
-- 3. Consider if a materialized view is appropriate
-- 4. Quantify improvement at each step
```

<details>
<summary>Solution</summary>

Step-by-step:

1. **Add index for date filter**: `CREATE INDEX idx_appt_date ON appointments(appointment_date);`
2. **Add indexes for join columns without them**: 
   - `CREATE INDEX idx_appt_facility ON appointments(facility_id);`
   - `CREATE INDEX idx_appt_department ON appointments(department_id);`
3. **Increase work_mem for session**: `SET work_mem = '256MB';`
4. **Re-run and check**: Sort and Hash should be in-memory now
5. **For nightly report - create materialized view**:
```sql
CREATE MATERIALIZED VIEW mv_monthly_report AS
SELECT 
    a.facility_id, a.department_id, p.specialty,
    DATE_TRUNC('month', a.appointment_date) AS month,
    COUNT(*) AS total_appointments,
    COUNT(*) FILTER (WHERE a.status = 'completed') AS completed,
    COUNT(*) FILTER (WHERE a.status = 'cancelled') AS cancelled,
    COUNT(*) FILTER (WHERE a.status = 'no_show') AS no_shows,
    ROUND(AVG(a.copay_amount), 2) AS avg_copay,
    ROUND(SUM(a.insurance_billed), 2) AS total_billed
FROM appointments a
JOIN providers p ON a.provider_id = p.provider_id
WHERE a.appointment_date >= '2024-01-01'
GROUP BY a.facility_id, a.department_id, p.specialty, 
         DATE_TRUNC('month', a.appointment_date);
```
6. **Refresh nightly**: `REFRESH MATERIALIZED VIEW CONCURRENTLY mv_monthly_report;`
</details>


### Speed Drill 7 (5 minutes) - The Accidental Cartesian

```sql
-- SCENARIO: Developer says "my query returns wrong counts"
-- Actually it's a cartesian join in disguise

EXPLAIN (ANALYZE, BUFFERS)
SELECT p.provider_id, p.last_name,
       COUNT(DISTINCT a.appointment_id) AS appt_count,
       COUNT(DISTINCT s.shift_id) AS shift_count
FROM providers p
JOIN appointments a ON a.provider_id = p.provider_id
JOIN shifts s ON s.provider_id = p.provider_id
WHERE p.provider_id = 42
GROUP BY p.provider_id, p.last_name;

-- TARGET: Identify the row explosion (appointments x shifts per provider)
-- and rewrite to avoid it.
```

<details>
<summary>Solution</summary>

The JOIN creates a cross product of appointments x shifts for each provider. If provider 42 has 2000 appointments and 200 shifts, the intermediate result is 400,000 rows.

```sql
-- Rewrite with separate aggregations
SELECT p.provider_id, p.last_name,
       a_stats.appt_count,
       s_stats.shift_count
FROM providers p
LEFT JOIN (
    SELECT provider_id, COUNT(*) AS appt_count
    FROM appointments
    WHERE provider_id = 42
    GROUP BY provider_id
) a_stats ON p.provider_id = a_stats.provider_id
LEFT JOIN (
    SELECT provider_id, COUNT(*) AS shift_count
    FROM shifts
    WHERE provider_id = 42
    GROUP BY provider_id
) s_stats ON p.provider_id = s_stats.provider_id
WHERE p.provider_id = 42;
```
</details>

---

## 9. SQL Server DBA Talking Points

### How to Explain PostgreSQL Concepts to a SQL Server Audience

| Concept | PostgreSQL | SQL Server Equivalent |
|---------|-----------|----------------------|
| Execution plan | `EXPLAIN (ANALYZE, BUFFERS)` | "Show Actual Execution Plan" button |
| Cost units | Abstract cost units (seq_page_cost=1) | Estimated subtree cost (%) |
| Seq Scan | Full table scan, reads all pages | Clustered Index Scan / Table Scan |
| Index Scan | Index lookup + heap fetch | Nonclustered Index Seek + Key Lookup |
| Index Only Scan | Covered by index, visibility map check | Covering Index Seek |
| Bitmap Scan | Two-phase: build bitmap then batch fetch | No direct equivalent |
| Hash Join | Build hash table from smaller input | Hash Match |
| Merge Join | Sorted merge of both inputs | Merge Join |
| Nested Loop | For each outer, scan inner | Nested Loops |
| MVCC | Row versions stored in heap | Row versioning in tempdb (RCSI) |
| VACUUM | Reclaims dead row space | Ghost cleanup (automatic) |
| ANALYZE | Gathers column statistics | UPDATE STATISTICS |
| Shared Buffers | Dedicated PostgreSQL buffer pool | Buffer Pool |
| work_mem | Per-operation memory for sorts/hashes | Sort/Hash memory from Query Memory Grant |
| WAL | Write-ahead log (like SQL Server's transaction log) | Transaction Log |
| Tablespace | Storage location for database objects | Filegroups |
| TOAST | Large value storage (auto-compressed) | Row-overflow / LOB storage |

### Key Differences to Highlight

**PostgreSQL MVCC vs SQL Server Locking**:
"In PostgreSQL, readers never block writers and writers never block readers. Instead of locking rows, we keep multiple row versions in the heap. The tradeoff is that we need VACUUM to clean up old versions - there's no automatic ghost cleanup like in SQL Server."

**PostgreSQL doesn't have Clustered Indexes**:
"Every PostgreSQL table is a heap - there's no concept of a clustered index that determines physical row order. Our closest equivalent is the CLUSTER command, but it's a one-time reorder, not maintained on writes. This means every index in PostgreSQL is conceptually like a nonclustered index in SQL Server."

**Cost-Based Optimizer**:
"PostgreSQL's optimizer works similarly to SQL Server's - it generates candidate plans and picks the lowest cost. The key difference is transparency: we can see exact cost numbers, row estimates, and buffer usage in the plan. PostgreSQL also exposes the cost model parameters (seq_page_cost, random_page_cost, etc.) that you can tune."

**Statistics**:
"PostgreSQL stores histogram buckets, most common values, and distinct counts per column - similar to SQL Server's statistics. The main difference: PostgreSQL doesn't auto-create statistics on non-indexed columns. You need to manually create extended statistics for correlated columns (like CREATE STATISTICS in PG 10+)."

---

## Quick Reference Card (Print This)

### EXPLAIN Cheat Sheet

```
EXPLAIN (ANALYZE, BUFFERS) SELECT ...;    -- Your default tool

Read bottom-up, inside-out.

Check in order:
1. Estimated rows vs Actual rows     -- Bad estimates = bad plan
2. Seq Scan on large table + small result  -- Missing index
3. Rows Removed by Filter           -- Filter too late, push into index
4. actual time * loops               -- Real total time
5. shared read >> shared hit         -- Cold cache, working set too large
6. Sort: external merge Disk         -- work_mem too small
7. Hash Batches > 1                  -- work_mem too small
8. Heap Fetches on Index Only Scan   -- Need VACUUM
```

### HypoPG Cheat Sheet

```sql
SELECT hypopg_reset();                                    -- Clear all
SELECT * FROM hypopg_create_index('CREATE INDEX ON ...');  -- Create
EXPLAIN SELECT ...;                                        -- Test (NOT ANALYZE)
SELECT * FROM hypopg_list_indexes();                       -- List
SELECT hypopg_drop_index(oid);                             -- Drop one
```

### Interview Validation Pattern

```
1. Run EXPLAIN (ANALYZE, BUFFERS) - record baseline
2. Identify bottleneck node
3. Propose fix (index, rewrite, config)
4. Test with HypoPG (if index)
5. Implement fix
6. Run EXPLAIN (ANALYZE, BUFFERS) again
7. State: "Execution time went from X ms to Y ms, 
   buffer reads from A to B. That's a Z% improvement."
```

**Always quantify. Always validate. Never assume the fix worked - PROVE it.**

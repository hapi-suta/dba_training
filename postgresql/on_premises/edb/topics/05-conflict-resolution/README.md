# Conflict Resolution in PGD/BDR

## Understanding Conflicts

### What is a Conflict?

A **conflict** occurs when the same data is modified on different nodes simultaneously, and the changes cannot be automatically merged.

### When Conflicts Happen

1. **Same row updated on different nodes**
   ```sql
   -- Node 1: UPDATE users SET email = 'new1@example.com' WHERE id = 1;
   -- Node 2: UPDATE users SET email = 'new2@example.com' WHERE id = 1;
   ```

2. **Primary key violations**
   ```sql
   -- Node 1: INSERT INTO users (id, name) VALUES (100, 'Alice');
   -- Node 2: INSERT INTO users (id, name) VALUES (100, 'Bob');
   ```

3. **Unique constraint violations**
   ```sql
   -- Node 1: INSERT INTO users (email) VALUES ('test@example.com');
   -- Node 2: INSERT INTO users (email) VALUES ('test@example.com');
   ```

4. **Foreign key violations**
   ```sql
   -- Node 1: DELETE FROM categories WHERE id = 1;
   -- Node 2: INSERT INTO products (category_id) VALUES (1);
   ```

## Conflict Resolution Policies

### 1. last_update_wins

Most recent update based on timestamp wins.

**Requirements:**
- Table must have a timestamp column
- Default: `updated_at` or `last_modified`
- Can specify custom column

**Configuration:**
```sql
-- Use default timestamp column
SELECT bdr.table_set_conflict_resolution(
    'public.users',
    'last_update_wins'
);

-- Specify custom timestamp column
SELECT bdr.table_set_conflict_resolution(
    'public.users',
    'last_update_wins',
    timestamp_column := 'modified_at'
);
```

**How it works:**
- Compare `updated_at` (or specified column) values
- Row with later timestamp wins
- Other row's changes are discarded

**Use case:** Most common policy, good for many applications

### 2. first_update_wins

First update wins (opposite of last_update_wins).

```sql
SELECT bdr.table_set_conflict_resolution(
    'public.users',
    'first_update_wins'
);
```

**Use case:** When you want to preserve the original value

### 3. accept_local

Local node's changes always win.

```sql
SELECT bdr.table_set_conflict_resolution(
    'public.users',
    'accept_local'
);
```

**Use case:**
- Regional data ownership
- Node has authority over specific data
- Prefer local changes

### 4. accept_remote

Remote node's changes always win.

```sql
SELECT bdr.table_set_conflict_resolution(
    'public.users',
    'accept_remote'
);
```

**Use case:**
- Central authority node
- Prefer changes from specific node
- Less common

### 5. custom

Write your own conflict handler function.

```sql
CREATE OR REPLACE FUNCTION merge_user_conflict(
    local_tuple RECORD,
    remote_tuple RECORD,
    conflict_type TEXT
) RETURNS RECORD AS $$
DECLARE
    result RECORD;
BEGIN
    -- Example: Merge non-conflicting fields
    result := local_tuple;
    
    -- If remote has newer timestamp, use remote email
    IF remote_tuple.updated_at > local_tuple.updated_at THEN
        result.email := remote_tuple.email;
    END IF;
    
    -- Always keep local preferences
    result.preferences := local_tuple.preferences;
    
    RETURN result;
END;
$$ LANGUAGE plpgsql;

-- Apply custom handler
SELECT bdr.table_set_conflict_resolution(
    'public.users',
    'custom',
    conflict_handler := 'merge_user_conflict'
);
```

**Use case:** Complex business logic, field-level merging

## Conflict Detection

### Automatic Detection

BDR automatically detects conflicts during replication apply:

1. **Row update conflict**: Same row updated on different nodes
2. **Insert conflict**: Same primary key inserted on different nodes
3. **Delete conflict**: Row deleted on one node, updated on another

### Conflict Logging

Enable conflict logging to track all conflicts:

```sql
-- Enable logging
ALTER SYSTEM SET bdr.log_conflicts = 'on';
SELECT pg_reload_conf();

-- View conflict history
SELECT 
    conflict_time,
    table_name,
    conflict_type,
    local_tuple,
    remote_tuple,
    resolution
FROM bdr.bdr_conflict_history
ORDER BY conflict_time DESC
LIMIT 100;
```

## Conflict Resolution Strategies

### Strategy 1: Avoid Conflicts (Best Practice)

**Partition data by node:**
- Node 1 handles users 1-1000
- Node 2 handles users 1001-2000
- Reduces conflict probability

**Use application-level routing:**
```python
def get_node_for_user(user_id):
    if user_id <= 1000:
        return 'node1'
    else:
        return 'node2'
```

### Strategy 2: Accept Conflicts with Policy

Use `last_update_wins` for most tables:
- Simple and predictable
- Works well for many use cases
- Requires timestamp column

### Strategy 3: Custom Merging

Write custom handlers for complex cases:
- Merge non-conflicting fields
- Apply business rules
- More complex but flexible

## Handling Specific Conflict Types

### UPDATE vs UPDATE

```sql
-- Node 1: UPDATE users SET name = 'Alice' WHERE id = 1;
-- Node 2: UPDATE users SET email = 'bob@example.com' WHERE id = 1;

-- Resolution: last_update_wins uses timestamp
-- If Node 2's update is newer, both changes are lost
-- Solution: Update both fields in single transaction, or use custom handler
```

### INSERT vs INSERT (Primary Key)

```sql
-- Node 1: INSERT INTO users (id, name) VALUES (100, 'Alice');
-- Node 2: INSERT INTO users (id, name) VALUES (100, 'Bob');

-- Resolution: One insert succeeds, other fails
-- BDR will apply one and log conflict for other
-- Consider using sequences or UUIDs
```

### DELETE vs UPDATE

```sql
-- Node 1: DELETE FROM users WHERE id = 1;
-- Node 2: UPDATE users SET name = 'New Name' WHERE id = 1;

-- Resolution: Depends on order
-- If delete arrives first: update fails
-- If update arrives first: delete succeeds, update lost
-- Consider soft deletes
```

## Best Practices

### 1. Design for Low Conflicts

- **Partition writes**: Route writes to specific nodes
- **Use sequences/UUIDs**: Avoid primary key conflicts
- **Soft deletes**: Mark as deleted instead of DELETE

### 2. Choose Appropriate Policy

- **Most tables**: `last_update_wins`
- **Reference data**: `accept_local` or `accept_remote`
- **Complex logic**: Custom handler

### 3. Monitor Conflicts

- Enable conflict logging
- Set up alerts for high conflict rates
- Review conflict history regularly

### 4. Test Conflict Scenarios

- Simulate conflicts in test environment
- Verify resolution behavior
- Document expected behavior

### 5. Update Timestamps

Ensure timestamp columns are updated:

```sql
-- Create trigger to auto-update timestamp
CREATE OR REPLACE FUNCTION update_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER users_updated_at
    BEFORE UPDATE ON users
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at();
```

## Conflict Resolution Examples

### Example 1: Simple last_update_wins

```sql
-- Table with timestamp
CREATE TABLE products (
    id SERIAL PRIMARY KEY,
    name TEXT,
    price DECIMAL,
    updated_at TIMESTAMP DEFAULT NOW()
);

-- Enable last_update_wins
SELECT bdr.table_add('public.products');
SELECT bdr.table_set_conflict_resolution(
    'public.products',
    'last_update_wins'
);
```

### Example 2: Regional Ownership

```sql
-- Tables owned by region
CREATE TABLE regional_data (
    id SERIAL PRIMARY KEY,
    region TEXT,
    data JSONB
);

-- Node 1 (US region) accepts local
SELECT bdr.table_set_conflict_resolution(
    'public.regional_data',
    'accept_local'
);
-- Configure: Only US data written to Node 1
```

### Example 3: Custom Merger

```sql
-- Merge user profiles
CREATE FUNCTION merge_profiles(
    local RECORD,
    remote RECORD,
    conflict_type TEXT
) RETURNS RECORD AS $$
BEGIN
    -- Merge: keep latest email, merge preferences JSON
    RETURN ROW(
        local.id,
        COALESCE(remote.email, local.email),
        local.preferences || remote.preferences,  -- JSON merge
        GREATEST(local.updated_at, remote.updated_at)
    );
END;
$$ LANGUAGE plpgsql;
```

## Next Steps

- **Topic 06**: Monitoring and troubleshooting conflicts
- **Topic 07**: High availability and failover


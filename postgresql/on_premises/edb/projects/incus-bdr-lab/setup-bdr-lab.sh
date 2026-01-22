#!/bin/bash
# PostgreSQL Bi-Directional Replication Lab Setup Script
# Run this inside the Lima VM: limactl shell incus-lab

set -e

echo "=============================================="
echo "PostgreSQL BDR Lab Setup"
echo "=============================================="

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print status
print_status() {
    echo -e "${GREEN}[✓]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[!]${NC} $1"
}

print_error() {
    echo -e "${RED}[✗]${NC} $1"
}

# Check if running inside Lima VM
if [ ! -f /etc/lima-guestagent ]; then
    print_warning "This script should be run inside the Lima VM"
    print_warning "Run: limactl shell incus-lab"
    exit 1
fi

echo ""
echo "Step 1: Starting containerd..."
sudo systemctl start containerd
sleep 2
print_status "Containerd started"

echo ""
echo "Step 2: Creating network..."
if sudo nerdctl network ls | grep -q pgnet; then
    print_warning "Network 'pgnet' already exists"
else
    sudo nerdctl network create pgnet --subnet 172.20.0.0/24
    print_status "Network 'pgnet' created"
fi

echo ""
echo "Step 3: Removing existing containers (if any)..."
for node in pg-node1 pg-node2 pg-node3; do
    sudo nerdctl rm -f $node 2>/dev/null || true
done
print_status "Cleaned up existing containers"

echo ""
echo "Step 4: Creating PostgreSQL containers..."
for i in 1 2 3; do
    ip=$((10 + i))
    sudo nerdctl run -d \
        --name pg-node$i \
        --hostname pg-node$i \
        --network pgnet \
        --ip 172.20.0.$ip \
        -e POSTGRES_PASSWORD=postgres \
        -e POSTGRES_HOST_AUTH_METHOD=trust \
        postgres:16
    print_status "Created pg-node$i (172.20.0.$ip)"
done

echo ""
echo "Waiting for PostgreSQL to start..."
sleep 8

echo ""
echo "Step 5: Installing pglogical..."
for node in pg-node1 pg-node2 pg-node3; do
    echo "  Installing on $node..."
    sudo nerdctl exec $node bash -c "apt-get update > /dev/null 2>&1 && apt-get install -y postgresql-16-pglogical > /dev/null 2>&1"
done
print_status "pglogical installed on all nodes"

echo ""
echo "Step 6: Configuring PostgreSQL..."
for node in pg-node1 pg-node2 pg-node3; do
    sudo nerdctl exec $node psql -U postgres -c "ALTER SYSTEM SET wal_level = logical;" > /dev/null
    sudo nerdctl exec $node psql -U postgres -c "ALTER SYSTEM SET max_replication_slots = 10;" > /dev/null
    sudo nerdctl exec $node psql -U postgres -c "ALTER SYSTEM SET max_wal_senders = 10;" > /dev/null
    sudo nerdctl exec $node psql -U postgres -c "ALTER SYSTEM SET max_worker_processes = 10;" > /dev/null
    sudo nerdctl exec $node psql -U postgres -c "ALTER SYSTEM SET shared_preload_libraries = 'pglogical';" > /dev/null
    sudo nerdctl exec $node bash -c "echo 'host all all 172.20.0.0/24 trust' >> /var/lib/postgresql/data/pg_hba.conf"
    sudo nerdctl exec $node bash -c "echo 'host replication all 172.20.0.0/24 trust' >> /var/lib/postgresql/data/pg_hba.conf"
done
print_status "PostgreSQL configured on all nodes"

echo ""
echo "Step 7: Restarting containers..."
for node in pg-node1 pg-node2 pg-node3; do
    sudo nerdctl restart $node > /dev/null
done
sleep 8
print_status "Containers restarted"

echo ""
echo "Step 8: Creating practice database and pglogical extension..."
for node in pg-node1 pg-node2; do
    sudo nerdctl exec $node psql -U postgres -c "CREATE DATABASE practice;" > /dev/null
    sudo nerdctl exec $node psql -U postgres -d practice -c "CREATE EXTENSION pglogical;" > /dev/null
done
print_status "Practice database created"

echo ""
echo "Step 9: Creating pglogical nodes..."
sudo nerdctl exec pg-node1 psql -U postgres -d practice -c "
  SELECT pglogical.create_node(
    node_name := 'node1',
    dsn := 'host=172.20.0.11 port=5432 dbname=practice user=postgres'
  );
" > /dev/null

sudo nerdctl exec pg-node2 psql -U postgres -d practice -c "
  SELECT pglogical.create_node(
    node_name := 'node2',
    dsn := 'host=172.20.0.12 port=5432 dbname=practice user=postgres'
  );
" > /dev/null
print_status "pglogical nodes created"

echo ""
echo "Step 10: Creating sample table..."
for node in pg-node1 pg-node2; do
    sudo nerdctl exec $node psql -U postgres -d practice -c "
      CREATE TABLE users (
        id SERIAL PRIMARY KEY,
        name TEXT NOT NULL,
        email TEXT,
        created_at TIMESTAMP DEFAULT NOW(),
        updated_at TIMESTAMP DEFAULT NOW()
      );
    " > /dev/null
    sudo nerdctl exec $node psql -U postgres -d practice -c "
      SELECT pglogical.replication_set_add_table('default', 'users', true);
    " > /dev/null
done
print_status "Sample table created"

echo ""
echo "Step 11: Creating bi-directional subscriptions..."
sudo nerdctl exec pg-node2 psql -U postgres -d practice -c "
  SELECT pglogical.create_subscription(
    subscription_name := 'sub_node1_to_node2',
    provider_dsn := 'host=172.20.0.11 port=5432 dbname=practice user=postgres',
    synchronize_data := false
  );
" > /dev/null

sudo nerdctl exec pg-node1 psql -U postgres -d practice -c "
  SELECT pglogical.create_subscription(
    subscription_name := 'sub_node2_to_node1',
    provider_dsn := 'host=172.20.0.12 port=5432 dbname=practice user=postgres',
    synchronize_data := false
  );
" > /dev/null
print_status "Bi-directional subscriptions created"

echo ""
echo "Step 12: Configuring sequences to avoid conflicts..."
sudo nerdctl exec pg-node1 psql -U postgres -d practice -c "ALTER SEQUENCE users_id_seq INCREMENT BY 2 RESTART WITH 1;" > /dev/null
sudo nerdctl exec pg-node2 psql -U postgres -d practice -c "ALTER SEQUENCE users_id_seq INCREMENT BY 2 RESTART WITH 2;" > /dev/null
print_status "Sequences configured"

echo ""
echo "=============================================="
echo -e "${GREEN}Setup Complete!${NC}"
echo "=============================================="
echo ""
echo "Lab Environment:"
echo "  pg-node1: 172.20.0.11 (odd IDs: 1,3,5...)"
echo "  pg-node2: 172.20.0.12 (even IDs: 2,4,6...)"
echo "  pg-node3: 172.20.0.13 (spare)"
echo ""
echo "Quick Test Commands:"
echo "  # Connect to node1"
echo "  sudo nerdctl exec -it pg-node1 psql -U postgres -d practice"
echo ""
echo "  # Insert on node1"
echo "  sudo nerdctl exec pg-node1 psql -U postgres -d practice -c \"INSERT INTO users (name, email) VALUES ('Test', 'test@example.com');\""
echo ""
echo "  # Check node2 (should see the data)"
echo "  sudo nerdctl exec pg-node2 psql -U postgres -d practice -c \"SELECT * FROM users;\""
echo ""


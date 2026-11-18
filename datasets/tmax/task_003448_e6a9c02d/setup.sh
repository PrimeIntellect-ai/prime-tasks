#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl sudo postgresql redis-server cargo rustc
    pip3 install pytest

    # Create directories
    mkdir -p /app/corpus/clean
    mkdir -p /app/corpus/evil

    # Create start_services.sh
    cat << 'EOF' > /app/start_services.sh
#!/bin/bash
# Start PostgreSQL
su - postgres -c "/usr/lib/postgresql/*/bin/pg_ctl -D /var/lib/postgresql/*/main start"
# Start Redis
redis-server --daemonize yes

sleep 3

# Setup PostgreSQL
su - postgres -c "psql -c \"CREATE USER backup_admin WITH PASSWORD 'secretpassword';\""
su - postgres -c "psql -c \"CREATE DATABASE backups_db OWNER backup_admin;\""

su - postgres -c "psql -d backups_db -c \"
CREATE TABLE backup_nodes (
    id VARCHAR PRIMARY KEY,
    parent_id VARCHAR,
    backup_type VARCHAR,
    size_bytes BIGINT
);
INSERT INTO backup_nodes (id, parent_id, backup_type, size_bytes) VALUES
('b_full_1', NULL, 'FULL', 1000),
('b_inc_1', 'b_full_1', 'INCREMENTAL', 100),
('b_inc_2', 'b_inc_1', 'INCREMENTAL', 50),
('e_cycle_1', 'e_cycle_2', 'INCREMENTAL', 10),
('e_cycle_2', 'e_cycle_1', 'INCREMENTAL', 10),
('e_orphan_1', 'e_missing', 'INCREMENTAL', 10),
('bad_status', 'b_full_1', 'INCREMENTAL', 10);
\""

# Setup Redis
redis-cli SET manifest:b_full_1 '{"checksum":"abc","status":"AVAILABLE"}'
redis-cli SET manifest:b_inc_1 '{"checksum":"def","status":"AVAILABLE"}'
redis-cli SET manifest:b_inc_2 '{"checksum":"ghi","status":"AVAILABLE"}'
redis-cli SET manifest:e_cycle_1 '{"checksum":"jkl","status":"AVAILABLE"}'
redis-cli SET manifest:e_orphan_1 '{"checksum":"mno","status":"AVAILABLE"}'
redis-cli SET manifest:bad_status '{"checksum":"xyz","status":"ARCHIVED"}'

echo "Services started and populated."
EOF
    chmod +x /app/start_services.sh

    # Create clean corpus
    cat << 'EOF' > /app/corpus/clean/f1.json
{"backup_id": "b_full_1"}
EOF
    cat << 'EOF' > /app/corpus/clean/f2.json
{"backup_id": "b_inc_2"}
EOF

    # Create evil corpus
    cat << 'EOF' > /app/corpus/evil/e1.json
{"backup_id": "e_cycle_1"}
EOF
    cat << 'EOF' > /app/corpus/evil/e2.json
{"backup_id": "e_orphan_1"}
EOF
    cat << 'EOF' > /app/corpus/evil/e3.json
{"backup_id": "bad_status"}
EOF
    cat << 'EOF' > /app/corpus/evil/e4.json
{"wrong_key": "b_inc_1"}
EOF

    # Create user
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user

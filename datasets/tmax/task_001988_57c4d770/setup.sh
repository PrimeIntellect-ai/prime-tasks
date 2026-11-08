#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl docker.io docker-compose
    pip3 install pytest

    # Install Rust
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    export PATH="/root/.cargo/bin:${PATH}"

    # Create directories
    mkdir -p /home/user/services
    mkdir -p /home/user/app/deadlock_detector
    mkdir -p /home/user/corpora/clean
    mkdir -p /home/user/corpora/evil

    # Create docker-compose.yml
    cat << 'EOF' > /home/user/services/docker-compose.yml
version: '3.8'
services:
  postgres_db:
    image: postgres:15
    environment:
      POSTGRES_USER: admin
      POSTGRES_PASSWORD: secret
      POSTGRES_DB: monitoring
    ports:
      - "5432:5432"
    volumes:
      - ./init.sql:/docker-entrypoint-initdb.d/init.sql
  redis_cache:
    image: redis:7
    ports:
      - "6379:6379"
EOF

    # Create Postgres init script
    cat << 'EOF' > /home/user/services/init.sql
CREATE TABLE deadlock_reports (
    file_name TEXT,
    is_deadlocked BOOLEAN,
    root_cause_tx INT,
    root_query TEXT
);
EOF

    # Generate corpora
    python3 -c '
import os
import hashlib

def make_hash(i):
    return hashlib.md5(str(i).encode()).hexdigest()

for i in range(50):
    with open(f"/home/user/corpora/clean/clean_{i}.csv", "w") as f:
        f.write("tx_id,waiting_for_tx_id,query_hash\n")
        for j in range(1, 10):
            f.write(f"{j},{j-1},{make_hash(j)}\n")

for i in range(50):
    with open(f"/home/user/corpora/evil/evil_{i}.csv", "w") as f:
        f.write("tx_id,waiting_for_tx_id,query_hash\n")
        for j in range(10):
            f.write(f"{j},{(j+1)%10},{make_hash(j)}\n")
'

    # Create user
    useradd -m -s /bin/bash user || true

    # Setup permissions
    chmod -R 777 /home/user

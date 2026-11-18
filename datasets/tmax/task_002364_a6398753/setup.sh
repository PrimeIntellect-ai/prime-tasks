#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    # Create directories
    mkdir -p /app/graph_auditor/core
    mkdir -p /opt/oracle

    # Create __init__.py files
    touch /app/graph_auditor/__init__.py
    touch /app/graph_auditor/core/__init__.py

    # Create transaction.py with the deadlock bug
    cat << 'EOF' > /app/graph_auditor/core/transaction.py
import threading
import time

_locks = {}
_locks_lock = threading.Lock()

def get_lock(node_id):
    with _locks_lock:
        if node_id not in _locks:
            _locks[node_id] = threading.Lock()
        return _locks[node_id]

def insert_edge(src, dst, data):
    lock_src = get_lock(src)
    lock_dst = get_lock(dst)

    # Deliberate flaw: acquiring locks in the order provided
    with lock_src:
        time.sleep(0.01) # Increase chance of deadlock
        with lock_dst:
            pass # Insert edge logic here
EOF

    # Create dummy oracle
    cat << 'EOF' > /opt/oracle/audit_oracle.py
import sys
import json

def run_oracle(input_json):
    pass

if __name__ == "__main__":
    if len(sys.argv) > 1:
        run_oracle(sys.argv[1])
EOF

    chmod +x /opt/oracle/audit_oracle.py

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user

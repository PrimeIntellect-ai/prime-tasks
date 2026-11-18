#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip git
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/service-repo
    cd /home/user/service-repo
    git init
    git config user.email "test@example.com"
    git config user.name "Test User"

    # Base commit
    cat << 'EOF' > worker.py
import threading
import time

class ConnectionManager:
    def __init__(self):
        self.active_connections = []
        self.lock = threading.Lock()

    def open_connection(self, conn_id):
        with self.lock:
            self.active_connections.append(conn_id)

    def close_connection(self, conn_id):
        with self.lock:
            if conn_id in self.active_connections:
                self.active_connections.remove(conn_id)

manager = ConnectionManager()

def process_job(job_id):
    manager.open_connection(job_id)
    time.sleep(0.01)
    manager.close_connection(job_id)
EOF

    cat << 'EOF' > load_test.py
import os
import sys
import threading
from worker import process_job, manager

if os.environ.get("TEST_AUTH_TOKEN") != "trk_9918273645x_alpha":
    print("Error: Invalid or missing TEST_AUTH_TOKEN")
    sys.exit(1)

threads = []
for i in range(200):
    t = threading.Thread(target=process_job, args=(i,))
    threads.append(t)
    t.start()

for t in threads:
    t.join()

if len(manager.active_connections) > 0:
    print(f"Memory Leak Detected! {len(manager.active_connections)} orphaned connections.")
    sys.exit(1)
else:
    print("Success: No memory leak detected.")
    sys.exit(0)
EOF

    git add worker.py load_test.py
    git commit -m "Initial commit"

    # Commit 2: Add secret
    echo "# TEST_AUTH_TOKEN=trk_9918273645x_alpha" >> config.txt
    git add config.txt
    git commit -m "Add config with dev token"

    # Commit 3: Remove secret
    git rm config.txt
    git commit -m "Remove leaked token from config"

    # Generate some filler commits
    for i in $(seq 1 10); do
        echo "# comment $i" >> worker.py
        git commit -am "Update worker comments part $i"
    done

    # Commit introducing the bug: Remove the lock in close_connection
    cat << 'EOF' > worker.py
import threading
import time

class ConnectionManager:
    def __init__(self):
        self.active_connections = []
        self.lock = threading.Lock()

    def open_connection(self, conn_id):
        with self.lock:
            self.active_connections.append(conn_id)

    def close_connection(self, conn_id):
        # Optimization: removed lock to reduce contention
        if conn_id in self.active_connections:
            self.active_connections.remove(conn_id)

manager = ConnectionManager()

def process_job(job_id):
    manager.open_connection(job_id)
    time.sleep(0.01)
    manager.close_connection(job_id)
EOF
    git commit -am "Optimize connection closure by removing lock contention"
    BUG_COMMIT=$(git rev-parse HEAD)

    # Generate more filler commits
    for i in $(seq 11 20); do
        echo "# comment $i" >> worker.py
        git commit -am "Update worker comments part $i"
    done

    # Save the expected truth data to a hidden file for the test framework
    mkdir -p /tmp/truth
    echo "trk_9918273645x_alpha" > /tmp/truth/token.txt
    echo "$BUG_COMMIT" > /tmp/truth/commit.txt
    echo "close_connection" > /tmp/truth/function.txt

    chmod -R 777 /home/user
    chmod -R 777 /tmp/truth

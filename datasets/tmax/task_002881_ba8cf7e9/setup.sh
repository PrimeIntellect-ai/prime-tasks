#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pytest-timeout

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import os

os.makedirs('/home/user/evidence', exist_ok=True)
os.makedirs('/home/user/recovered', exist_ok=True)

script_content = """import threading
import time

class ConnectionPool:
    def __init__(self):
        self.conn_lock = threading.Lock()
        self.state_lock = threading.Lock()
        self.active_connections = 0

    def acquire_connection(self):
        with self.conn_lock:
            time.sleep(0.01) # Simulate work
            with self.state_lock:
                self.active_connections += 1

    def release_connection(self):
        with self.state_lock:
            time.sleep(0.01) # Simulate work
            with self.conn_lock:
                self.active_connections -= 1

pool = ConnectionPool()

def worker1():
    for _ in range(50):
        pool.acquire_connection()

def worker2():
    for _ in range(50):
        pool.release_connection()

def run():
    t1 = threading.Thread(target=worker1)
    t2 = threading.Thread(target=worker2)
    t1.start()
    t2.start()
    t1.join()
    t2.join()

if __name__ == "__main__":
    run()
"""

with open('/home/user/evidence/mem_dump.bin', 'wb') as f:
    f.write(os.urandom(1024 * 50))
    f.write(b"### SCRIPT_START\n")
    f.write(script_content.encode('utf-8'))
    f.write(b"### SCRIPT_END\n")
    f.write(os.urandom(1024 * 50))
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user

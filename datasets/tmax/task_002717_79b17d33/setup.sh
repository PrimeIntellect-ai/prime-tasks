#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/services.json
{
  "data_service": {
    "cmd": "python3 /home/user/data_service.py",
    "port": 9000
  },
  "migration_worker": {
    "cmd": "python3 /home/user/worker.py",
    "depends_on": "data_service",
    "env": {
      "MIGRATION_ENV": "active"
    }
  }
}
EOF

    cat << 'EOF' > /home/user/data_service.py
import time
import socket
import sys

# Simulate slow startup
time.sleep(3)

sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
sock.bind(('127.0.0.1', 9000))
sock.listen(1)
print("Data service ready on port 9000")

while True:
    conn, addr = sock.accept()
    conn.sendall(b"DATA_READY")
    conn.close()
EOF

    cat << 'EOF' > /home/user/worker.py
import os
import sys
import socket

if os.environ.get("MIGRATION_ENV") != "active":
    print("FATAL: MIGRATION_ENV is not set or invalid.")
    sys.exit(1)

try:
    sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    sock.connect(('127.0.0.1', 9000))
    data = sock.recv(1024)
    if data == b"DATA_READY":
        with open("/home/user/status.log", "w") as f:
            f.write("STATUS: MIGRATION_SUCCESS\n")
        print("Worker finished successfully.")
        sys.exit(0)
except Exception as e:
    print(f"FATAL: Could not connect to data service. Is it running? Error: {e}")
    sys.exit(1)
EOF

    cat << 'EOF' > /home/user/supervisor.py
import json
import subprocess
import time
import sys

def main():
    with open('/home/user/services.json', 'r') as f:
        services = json.load(f)

    processes = []

    # Buggy implementation: starts everything at once, ignores depends_on, port readiness, and env vars
    for name, config in services.items():
        print(f"Starting {name}...")
        cmd = config.get("cmd").split()
        p = subprocess.Popen(cmd)
        processes.append(p)

    for p in processes:
        p.wait()

if __name__ == "__main__":
    main()
EOF

    chmod -R 777 /home/user

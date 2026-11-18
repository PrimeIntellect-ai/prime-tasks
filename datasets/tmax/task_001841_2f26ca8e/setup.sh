#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup_incident.py
import os
import random

os.makedirs('/home/user/incident_data', exist_ok=True)

# Generate service.log
log_lines = []
time = 1680000000.0

# Normal operations
for i in range(100):
    time += random.uniform(0.01, 0.05)
    tid = f"Thread-{random.randint(10, 50)}"
    log_lines.append(f"[{time:.3f}] [{tid}] [INFO] Processing event")

# Deadlock scenario
time += 0.1
log_lines.append(f"[{time:.3f}] [Thread-14] [INFO] Acquired Resource-A")
time += 0.05
log_lines.append(f"[{time:.3f}] [Thread-42] [INFO] Acquired Resource-B")
time += 0.05
log_lines.append(f"[{time:.3f}] [Thread-14] [WAIT] Waiting for Resource-B")
time += 0.05
log_lines.append(f"[{time:.3f}] [Thread-42] [WAIT] Waiting for Resource-A")
time += 5.0 # Watchdog wait
log_lines.append(f"[{time:.3f}] [Watchdog-0] [CRITICAL] System hang detected, sending SIGKILL")

with open('/home/user/incident_data/service.log', 'w') as f:
    f.write('\n'.join(log_lines) + '\n')

# Generate transactions.wal
wal_lines = []
start_time = 1680000000.0

for i in range(1, 107):
    txn_id = f"TXN-{i:03d}"

    if i == 89:
        duration = 5.234 # Anomaly
    else:
        duration = random.uniform(0.01, 0.05) # Normal 10-50ms

    end_time = start_time + duration
    payload_hash = f"{random.randint(0, 0xFFFFFFFF):08x}"

    if i == 106:
        # Corrupted last entry
        wal_lines.append(f"{txn_id}:{start_time:.3f}:{end_time:.3f}:{payload_hash[:3]}")
    else:
        wal_lines.append(f"{txn_id}:{start_time:.3f}:{end_time:.3f}:{payload_hash}")

    start_time = end_time + random.uniform(0.001, 0.01)

with open('/home/user/incident_data/transactions.wal', 'w') as f:
    f.write('\n'.join(wal_lines)) # No trailing newline to simulate abrupt cut
EOF

    python3 /tmp/setup_incident.py
    rm /tmp/setup_incident.py

    chmod -R 777 /home/user

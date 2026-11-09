#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip
pip3 install pytest

useradd -m -s /bin/bash user || true

mkdir -p /home/user/app

cat << 'EOF' > /home/user/app/processor.py
import threading
import time

lock_a = threading.Lock()
lock_b = threading.Lock()

def process_x(txn_id):
    with lock_a:
        time.sleep(0.1)
        with lock_b:
            print(f"Processed X {txn_id}")

def process_y(txn_id):
    with lock_b:
        time.sleep(0.1)
        with lock_a:
            print(f"Processed Y {txn_id}")
EOF

cat << 'EOF' > /home/user/app/app.log
[2023-10-27 10:00:01] INFO Thread-Worker-1: Starting transaction processing.
[2023-10-27 10:00:01] INFO Thread-Worker-1: Acquired first lock for process_x.
[2023-10-27 10:00:01] INFO Thread-Worker-2: Starting transaction processing.
[2023-10-27 10:00:01] INFO Thread-Worker-2: Acquired first lock for process_y.
[2023-10-27 10:00:02] WARN Watchdog: Deadlock detected! Dumping memory and terminating.
EOF

dd if=/dev/urandom of=/home/user/app/memory.dmp bs=1K count=10 2>/dev/null
echo "[Thread-Worker-1] TXN_ID: TXN_88A9F0" >> /home/user/app/memory.dmp
dd if=/dev/urandom bs=1K count=5 2>/dev/null >> /home/user/app/memory.dmp
echo "[Thread-Worker-2] TXN_ID: TXN_33B2E1" >> /home/user/app/memory.dmp
echo "[Thread-Worker-3] TXN_ID: TXN_99C4D2" >> /home/user/app/memory.dmp
dd if=/dev/urandom bs=1K count=5 2>/dev/null >> /home/user/app/memory.dmp

chmod -R 777 /home/user

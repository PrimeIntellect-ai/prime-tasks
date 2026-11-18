#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip
pip3 install pytest

useradd -m -s /bin/bash user || true

mkdir -p /home/user/logs /home/user/wal

# Generate API logs
cat << 'EOF' > /home/user/logs/api.log
[2023-10-25 14:32:00] INFO: Received request for TXN-9430
[2023-10-25 14:32:01] INFO: Received request for TXN-9431
[2023-10-25 14:32:02] INFO: Received request for TXN-9432
[2023-10-25 14:32:03] INFO: Received request for TXN-9433
EOF

# Generate Worker logs
cat << 'EOF' > /home/user/logs/worker.log
[2023-10-25 14:32:00] [Thread-1] Assigned TXN-9430
[2023-10-25 14:32:01] [Thread-2] Assigned TXN-9431
[2023-10-25 14:32:01] [Thread-1] Finished TXN-9430
[2023-10-25 14:32:02] [Thread-2] Finished TXN-9431
[2023-10-25 14:32:03] [Thread-4] Assigned TXN-9432
[2023-10-25 14:32:03] [Thread-7] Assigned TXN-9432
[2023-10-25 14:32:04] [Thread-4] Allocating buffer for TXN-9432
[2023-10-25 14:32:04] [Thread-7] Allocating buffer for TXN-9432
[2023-10-25 14:32:05] [Thread-4] Expanding buffer for TXN-9432...
[2023-10-25 14:32:05] [Thread-7] Expanding buffer for TXN-9432...
[2023-10-25 14:32:06] FATAL: MemoryError in worker_pool.py line 112 - Process killed
EOF

# Generate DB logs
cat << 'EOF' > /home/user/logs/db.log
[2023-10-25 14:32:01] INFO: TXN-9430 flushed to disk
[2023-10-25 14:32:02] INFO: TXN-9431 flushed to disk
[2023-10-25 14:32:04] WARN: Multiple write locks requested for TXN-9432
EOF

# Generate WAL files
for i in $(seq -f "%03g" 1 50); do
    echo "DATA FOR WAL $i" > "/home/user/wal/wal_${i}.dat"
done

# Inject corrupted WAL data
echo "TXN-9432 STATUS:UNCOMMITTED PAYLOAD:0xDEADBEEF" > /home/user/wal/wal_042.dat

chmod -R 777 /home/user

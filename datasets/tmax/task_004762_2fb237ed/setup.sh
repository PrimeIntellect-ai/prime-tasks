#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip tar gzip
pip3 install pytest

useradd -m -s /bin/bash user || true

mkdir -p /home/user/data/docs/logs
mkdir -p /home/user/external

cat << 'EOF' > /home/user/external/metrics.json
[
  {"id": 101, "value": 42.5, "status": "active"},
  {"id": 102, "value": 89.1, "status": "pending"},
  {"id": 103, "value": 12.0, "status": "error"}
]
EOF

ln -s /home/user/external/metrics.json /home/user/data/metrics.json

echo "Document 1" > /home/user/data/docs/doc1.txt

ln -s /home/user/data /home/user/data/docs/logs/archive

cat << 'EOF' > /home/user/failed_backup.log
[2023-11-01 02:00:00] INFO: Starting backup of /home/user/data
[2023-11-01 02:00:01] INFO: Processing /home/user/data/docs
[2023-11-01 02:00:05] FATAL ERROR: Infinite symlink loop detected!
Stack trace of recursive resolution:
  -> /home/user/data/docs
  -> /home/user/data/docs/logs
  -> /home/user/data/docs/logs/archive
Resolves back to /home/user/data. Aborting.
[2023-11-01 02:00:05] ERROR: Backup failed with exit code 1.
EOF

chown -R user:user /home/user
chmod -R 777 /home/user

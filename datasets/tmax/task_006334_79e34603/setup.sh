#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ tar gzip
    pip3 install pytest

    mkdir -p /home/user
    cat << 'EOF' > /home/user/system.log
[2023-10-01 10:00:01] INFO: System started successfully. SESSION_TOKEN=abc123xyz
[2023-10-01 10:05:00] WARN: High memory usage detected.
[2023-10-01 10:10:22] ERROR: Disk Space Critical
Module: StorageController
Traceback (most recent call last):
  File "storage.py", line 42, in check_space
    raise DiskFullException()
SESSION_TOKEN=a1b2c3d4e5
[2023-10-01 10:11:00] INFO: Attempting to clear cache.
[2023-10-01 10:15:30] ERROR: Disk Space Critical
Module: LogWriter
Details: Failed to write to /var/log/app.log
SESSION_TOKEN=XyZ987
Please free up space immediately.
[2023-10-01 10:16:00] WARN: Skipping log write.
[2023-10-01 10:20:00] ERROR: Disk Space Critical
Module: DatabaseSync
SESSION_TOKEN=QWERTY123456
Sync failed due to ENOSPC.
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user

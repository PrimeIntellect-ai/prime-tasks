#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user/archive_mounts/server_alpha/var/log/
    mkdir -p /home/user/archive_mounts/server_beta/app/logs/old/
    mkdir -p /home/user/archive_mounts/server_gamma/sys/

    cat << 'EOF' > /home/user/archive_mounts/server_alpha/var/log/backup.log
[2023-10-01 02:00:00] INFO - Backup job started
[2023-10-01 02:05:12] FATAL - Backup job failed: Insufficient permissions
Traceback (most recent call last):
  File "backup.py", line 42, in <module>
PermissionError: [Errno 13] Permission denied: '/mnt/data'
[2023-10-01 02:10:00] INFO - Cleanup finished
EOF

    cat << 'EOF' > /home/user/archive_mounts/server_beta/app/logs/old/archive_2023.log
[2023-09-15 01:00:00] INFO - Backup job started
[2023-09-15 01:45:00] WARN - High disk usage detected
[2023-09-15 01:50:33] FATAL - Backup job failed: Disk full
Details:
Volume /dev/sda1 has 0 bytes free.
Please free up space and retry.
[2023-09-15 02:00:00] INFO - Retrying...
EOF

    cat << 'EOF' > /home/user/archive_mounts/server_gamma/sys/system.log
[2023-11-20 03:00:00] INFO - Backup job started
[2023-11-20 03:01:00] ERROR - Minor connection drop
[2023-11-20 03:15:22] FATAL - Backup job failed: Timeout reached
Connection to remote server lost.
Retries exhausted.
[2023-11-20 03:16:00] INFO - System halting
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user

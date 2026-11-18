#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ rename
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/logs
    mkdir -p /home/user/archive

    cat << 'EOF' > /home/user/logs/node1.log
[INFO] 2023-10-01 10:00:00
System started up successfully.
Checking disk quotas...
[WARN] 2023-10-01 10:05:00
Latency spike detected on volume A.
[CRITICAL] 2023-10-01 10:10:00
Disk space critically low on /dev/sda1
Immediate action required.
Dumping core state...
[INFO] 2023-10-01 10:15:00
Cleanup routine started.
EOF

    cat << 'EOF' > /home/user/logs/node2.log
[INFO] 2023-10-01 09:00:00
Node 2 initialized.
[CRITICAL] 2023-10-01 09:30:00
RAID array degraded!
Drive 3 failed.
Please replace drive 3 and rebuild.
[WARN] 2023-10-01 09:35:00
Rebuild pending admin approval.
EOF

    chown -R user:user /home/user/logs /home/user/archive
    chmod -R 777 /home/user

#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ zlib1g-dev gzip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/logs

    cat << 'EOF' > /home/user/logs/archive1.log
===LOG===
Time: 2023-10-25T08:00:00
Status: INFO
Details: System booted.
===END===
===LOG===
Time: 2023-10-25T08:05:12
Status: CRITICAL
Details: RAID array degraded.
===END===
===LOG===
Time: 2023-10-25T08:10:00
Status: WARNING
Details: CPU temperature at 85C.
===END===
EOF

    cat << 'EOF' > /home/user/logs/archive2.log
===LOG===
Time: 2023-10-26T01:12:00
Status: INFO
Details: Daily backup started.
===END===
===LOG===
Time: 2023-10-26T02:45:55
Status: CRITICAL
Details: Kernel panic - not syncing: VFS: Unable to mount root fs.
===END===
EOF

    gzip /home/user/logs/archive1.log
    gzip /home/user/logs/archive2.log

    chown -R user:user /home/user/logs
    chmod -R 777 /home/user

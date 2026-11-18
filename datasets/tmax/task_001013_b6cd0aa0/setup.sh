#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/legacy.log
2023/10/24-14:23:10 INFO [USR-001] System started successfully.
10-24-2023 14:25:01 ERROR [USR-099] Connection timeout in region us-east.
2023.10.24 14:26:15 WARN [USR-442] Disk usage high on /dev/sda1
2023/10/24-14:28:00 ERROR [SYS-111] Kernel panic - not syncing!
10-25-2023 09:00:00 ERROR [USR-102] Database lock acquisition failed.
2023.10.25 09:15:22 INFO [USR-102] Retry successful.
01-01-2024 00:00:01 WARN [USR-007]   Unexpected payload size: 4096 bytes  
EOF

    chmod -R 777 /home/user

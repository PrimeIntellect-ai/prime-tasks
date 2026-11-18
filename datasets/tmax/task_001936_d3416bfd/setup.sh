#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/system_logs.csv
timestamp,log_level,user_id,message
2023-10-01T10:00:00Z,INFO,usr1,"Normal system startup"
2023-10-01T10:05:00Z,ERROR,usr2,"Connection timeout
at module.network (network.c:120)
Retrying..."
2023-10-01T10:10:00Z,CRITICAL,usr3,"Kernel panic - not syncing"
2023-10-01T10:15:00Z,ERROR,UsR2,"Connection timeout
at module.network (network.c:120)
Retrying..."
2023-10-01T10:20:00Z,ERROR,usr4,"Database lock exception"
2023-10-01T10:25:00Z,CRITICAL,usr5,"Out of memory
OOM killer invoked"
2023-10-01T10:30:00Z,CRITICAL,usr6,"Disk full on /dev/sda1"
invalid_date_string,ERROR,usr7,"Malformed date event"
2023-10-01T10:40:00Z,ERROR,usr8,"Unreachable host"
2025-01-01T10:00:00Z,ERROR,usr9,"Future date event"
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user

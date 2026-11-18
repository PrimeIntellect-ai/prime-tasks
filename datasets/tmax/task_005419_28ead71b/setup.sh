#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3 cron gawk sed
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/incoming.log
[2024-05-12T08:15:30] LEVEL=warn msg="Disk space low" IP=192.168.1.5 user=AdminCode code=404
[2024-05-12T08:16:05] ip=10.0.0.9 CODE=500 level=ERROR msg="Crash" USER=sysadmin
[2024-05-12T08:17:22] level=info msg="User logged out" user=Bob
[2024-05-12T08:18:00] IP=172.16.0.4 LEVEL=CRITICAL code=503 msg="DB down"
EOF

    chmod -R 777 /home/user

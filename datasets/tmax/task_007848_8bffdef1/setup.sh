#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cron
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/app_a.log
2023-10-25 09:30:00 -0400 | Connection reset by peer
2023-10-25 09:35:00 -0400 | Out of memory error
2023-10-25 10:00:00 -0400 | Database timeout occurred during query
2023-10-25 11:15:00 -0400 | Unknown variable in template
EOF

    cat << 'EOF' > /home/user/app_b.log
25/Oct/2023:13:31:00 +0000 - Connection was reset by peer
25/Oct/2023:13:50:00 +0000 - Disk space full
25/Oct/2023:14:02:00 +0000 - Database timeout during query execution
25/Oct/2023:16:15:00 +0000 - Unknown variable in template
EOF

    chmod -R 777 /home/user

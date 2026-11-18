#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/logs.txt
[2023-10-24 10:15:00] User 1234 encountered ERR_OOM in module A.
[2023-10-24 10:16:30] User 5678 failed with ERR_TIMEOUT.
[2023-10-24 11:05:12] User 1234 hit ERR_OOM again.
[2023-10-24 11:20:00] System restart initialized. Memory cleared.
[2023-10-24 12:00:01] User 9012 got ERR_ACCESS_DENIED on /admin.
[2023-10-24 12:05:00] User 9999 experienced ERR_UNKNOWN.
EOF

    cat << 'EOF' > /home/user/departments.csv
user_id,dept
1234,Sales
5678,Engineering
9012,HR
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user

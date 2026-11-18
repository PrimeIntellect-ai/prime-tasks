#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk coreutils sed
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user

    cat << 'EOF' > /home/user/activity.log
2023-10-01T08:00:00 U001 LOGIN SUCCESS
2023-10-01T08:05:00 U001 PURCHASE 150.00
2023-10-01T09:12:00 U002 LOGIN FAIL
2023-10-01T09:15:00 U002 LOGIN FAIL
2023-10-01T09:20:00 U002 LOGIN SUCCESS
2023-10-01T09:25:00 U002 PURCHASE 500.50
2023-10-01T10:00:00 U003 PURCHASE 45.00
2023-10-01T11:00:00 U004 LOGIN SUCCESS
2023-10-01T11:05:00 U001 PURCHASE 25.50
2023-10-01T11:10:00 U001 LOGIN SUCCESS
EOF

    cat << 'EOF' > /home/user/priors.csv
U001,0.05
U002,0.15
U003,0.02
U004,0.01
U005,0.10
EOF

    chown -R user:user /home/user
    chmod -R 777 /home/user

#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cron
    pip3 install pytest Levenshtein

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/etl_data.tsv
101	SYS	1620000000	Database connection timed out
102	SYS	1620000005	Database connection timed out.
103	SYS	1620000010	Database conection timed out
104	APP	1620000020	User login failed for user admin
105	APP	1620000021	User logn failed for user admin
106	APP	1620000050	User login failed for user guest
107	NET	1620000100	Packet loss detected on eth0
108	NET	1620000102	Packet loss detected on eth1
109	SYS	1620000150	Out of memory error in process
110	SYS	1620000155	Out of memory error in proces
EOF

    chmod -R 777 /home/user

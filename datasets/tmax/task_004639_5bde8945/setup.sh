#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas

    mkdir -p /home/user/data

    cat << 'EOF' > /home/user/data/config_updates.log
System boot up at 2023-10-01 09:50:00
[2023-10-01 09:55:10] [INFO] system running normally
[2023-10-01 09:58:15] [UPDATE] server-A : cache_size -> 1024
[2023-10-01 10:01:45] [UPDATE] server-B : timeout -> 30
[2023-10-01 10:02:10] [UPDATE] server-A : cache_size -> 1024
[2023-10-01 10:03:00] [WARN] High memory usage on server-A
[2023-10-01 10:04:30] [UPDATE] server-A : max_workers -> 16
[2023-10-01 10:05:20] [UPDATE] server-C : log_level -> DEBUG
EOF

    cat << 'EOF' > /home/user/data/metrics.csv
timestamp,server_id,cpu
2023-10-01 09:56:10,server-A,40.0
2023-10-01 09:57:15,server-A,42.0
2023-10-01 09:57:45,server-A,46.0
2023-10-01 09:58:20,server-A,50.0
2023-10-01 10:00:10,server-B,60.0
2023-10-01 10:01:50,server-B,66.0
2023-10-01 10:03:05,server-A,70.0
2023-10-01 10:04:55,server-A,80.0
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user

#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user
    cat << 'EOF' > /home/user/api_latency.csv
2023-10-01T10:00:01,/login,45
2023-10-01T10:00:02,/login,50
2023-10-01T10:00:03,/login,48
2023-10-01T10:00:04,/login,52
2023-10-01T10:00:05,/login,47
2023-10-01T10:00:06,/login,110
2023-10-01T10:00:07,/login,55
2023-10-01T10:00:08,/login,49
2023-10-01T10:00:09,/login,51
2023-10-01T10:00:10,/login,150
2023-10-01T10:00:11,/login,60
2023-10-01T10:00:12,/login,58
2023-10-01T10:00:13,/login,62
2023-10-01T10:00:14,/login,55
2023-10-01T10:00:15,/login,130
EOF

    chown -R user:user /home/user
    chmod -R 777 /home/user

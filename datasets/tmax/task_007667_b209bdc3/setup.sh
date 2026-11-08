#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/logs

    cat << 'EOF' > /home/user/logs/access_1.log
2023-10-01T10:00:15Z,/api/login,200,500
2023-10-01T10:01:10Z,/api/data,500,200
2023-10-01T10:02:45Z,/api/data,200,1000
EOF

    cat << 'EOF' > /home/user/logs/access_2.log
2023-10-01T10:03:05Z,/api/login,200,600
2023-10-01T10:04:20Z,/api/data,502,250
2023-10-01T10:05:50Z,/api/data,200,1100
EOF

    chmod -R 777 /home/user

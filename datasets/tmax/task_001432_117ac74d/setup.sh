#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk
    pip3 install pytest

    mkdir -p /home/user/logs

    cat << 'EOF' > /home/user/logs/app.log
[2023-10-12 10:05:12] ERROR Disk full
[2023-10-12 10:14:59] WARNING High memory
[2023-10-12 10:17:00] ERROR Disk full
EOF

    cat << 'EOF' > /home/user/logs/sys.csv
timestamp,level,message
2023-10-12T10:29:10Z,WARNING,CPU spike
2023-10-12T10:10:00Z,ERROR,Network timeout
2023-10-12T10:14:15Z,WARNING,High memory
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user/logs
    chmod -R 777 /home/user

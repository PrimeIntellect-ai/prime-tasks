#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip build-essential cron
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/data
    mkdir -p /home/user/output

    cat << 'EOF' > /home/user/data/humidity.csv
timestamp,humidity
2023-10-12T08:00:00Z,45.2
2023-10-12T08:05:00Z,46.1
2023-10-12T08:10:00Z,45.8
2023-10-12T08:15:00Z,47.0
2023-10-12T08:25:00Z,48.5
EOF

    cat << 'EOF' > /tmp/temp.txt
timestamp,temperature
1697107200,22.4
1697107500,22.5
1697107800,22.6
1697108400,23.1
1697108700,23.4
EOF

    iconv -f UTF-8 -t UTF-16LE /tmp/temp.txt > /home/user/data/temp.csv
    rm /tmp/temp.txt

    chmod -R 777 /home/user

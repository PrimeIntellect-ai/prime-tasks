#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ make libssl-dev
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/legacy_logs
    mkdir -p /home/user/archive

    cat << 'EOF' > /tmp/log1.csv
Timestamp,Severity,Message
1670000000,INFO,System started successfully
1670000005,WARN,Memory usage high
1670000010,ERROR,Disk failure on /dev/sda
EOF

    cat << 'EOF' > /tmp/log2.csv
Timestamp,Severity,Message
1670000015,INFO,All systems nominal
1670000020,INFO,Routine backup completed
EOF

    iconv -f UTF-8 -t UTF-16LE /tmp/log1.csv > /home/user/legacy_logs/log1.csv
    iconv -f UTF-8 -t UTF-16LE /tmp/log2.csv > /home/user/legacy_logs/log2.csv

    chown -R user:user /home/user/legacy_logs /home/user/archive
    chmod -R 777 /home/user

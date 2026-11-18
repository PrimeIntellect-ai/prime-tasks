#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk sed gzip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/backup_drop/

    echo "1700000000.0" > /home/user/last_run.stamp

    cat << 'EOF' > /tmp/log1.txt
-- LOG START --
INFO 10.0.0.1 Connection established
CRITICAL 192.168.1.100 Disk full
EOF
    gzip -c /tmp/log1.txt > /home/user/backup_drop/log1.gz

    cat << 'EOF' > /home/user/backup_drop/log2.txt
-- APP LOG --
CRITICAL 172.16.0.5 Memory out of bounds
WARN 10.0.0.2 High CPU
EOF

    cat << 'EOF' > /home/user/backup_drop/fake.gz
XX CRITICAL 1.2.3.4 error
EOF

    cat << 'EOF' > /tmp/old.txt
CRITICAL 8.8.8.8 failure
EOF
    gzip -c /tmp/old.txt > /home/user/backup_drop/old.gz

    touch -d @1750000000 /home/user/backup_drop/log1.gz
    touch -d @1750000000 /home/user/backup_drop/log2.txt
    touch -d @1750000000 /home/user/backup_drop/fake.gz
    touch -d @1600000000 /home/user/backup_drop/old.gz

    chmod -R 777 /home/user

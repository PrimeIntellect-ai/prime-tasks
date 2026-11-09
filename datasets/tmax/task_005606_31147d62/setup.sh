#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user/raw_logs

    cat << 'EOF' > /home/user/raw_logs/server1.log
System boot initiated. Error! Disk 1 not found.
Checking redundancy... ERROR: redundancy failure.
System halted. error code 404.
EOF

    cat << 'EOF' > /home/user/raw_logs/server2.log
All systems nominal. Normal operations assumed.
No Error found.
EOF

    cat << 'EOF' > /home/user/raw_logs/app.log
Application start. Warning: Memory low.
allocating additional resources. Success.
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user

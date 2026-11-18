#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest

    mkdir -p /home/user/logs

    cat << 'EOF' > /home/user/config.txt
ARCHIVE_PATH=/home/user/archive.dat
FILTER_KEY=FATAL
EOF

    cat << 'EOF' > /home/user/logs/app.log
INFO Starting application
WARN Low memory
FATAL Out of memory exception in thread 1
INFO Retrying
FATAL Process crashed
EOF

    cat << 'EOF' > /home/user/logs/auth.log
INFO User admin logged in
INFO User root failed login
EOF

    cat << 'EOF' > /home/user/logs/sys.log
DEBUG kernel boot
FATAL Disk /dev/sda1 failure
WARN CPU temperature high
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user

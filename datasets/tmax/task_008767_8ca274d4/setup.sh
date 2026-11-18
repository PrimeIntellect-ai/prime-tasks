#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc zip unzip tar
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/archives
    cd /home/user/archives

    cat << 'EOF' > syslog1.txt
INFO: System started
[DISK_FULL] Device /dev/sda1 is out of space
DEBUG: Retrying write...
[DISK_FULL] Write failed on /var/log
INFO: Shutting down services
EOF
    zip logs.zip syslog1.txt
    tar -cf server1.tar logs.zip
    rm syslog1.txt logs.zip

    cat << 'EOF' > syslog2.txt
WARNING: CPU load high
INFO: User logged in
[DISK_FULL] Quota exceeded for user backup
[DISK_FULL] Cannot create temporary file
ERROR: Application crashed
EOF
    zip logs.zip syslog2.txt
    tar -cf server2.tar logs.zip
    rm syslog2.txt logs.zip

    chmod -R 777 /home/user

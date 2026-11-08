#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make zlib1g-dev wget tar
    pip3 install pytest

    # Create pigz directory and perturb Makefile
    mkdir -p /app
    cd /app
    wget https://github.com/madler/pigz/archive/refs/tags/v2.8.tar.gz -O pigz-2.8.tar.gz
    tar -xzf pigz-2.8.tar.gz
    rm pigz-2.8.tar.gz
    sed -i 's/-lz//g' /app/pigz-2.8/Makefile

    # Create user and home directory
    useradd -m -s /bin/bash user || true

    # Create config file
    cat << 'EOF' > /home/user/archive_config.conf
SOURCE_DIR=/var/log/app_logs
EXCLUDE_PATTERN_1=\[DEBUG\]
EXCLUDE_PATTERN_2=\[TRACE\]
COMPRESSION_LEVEL=-9
TARGET_FILE=/home/user/archived_logs.tar.gz
EOF

    # Generate log files
    mkdir -p /var/log/app_logs
    for i in $(seq 1 15000); do
        echo "2023-10-01 12:00:00 [DEBUG] This is a debug message with some extra padding to increase file size quickly." >> /tmp/base.log
        echo "2023-10-01 12:00:01 [TRACE] This is a trace message with some extra padding to increase file size quickly." >> /tmp/base.log
        echo "2023-10-01 12:00:02 [DEBUG] This is another debug message with some extra padding to increase file size quickly." >> /tmp/base.log
        echo "2023-10-01 12:00:03 [TRACE] This is another trace message with some extra padding to increase file size quickly." >> /tmp/base.log
        echo "2023-10-01 12:00:04 [INFO] This is an info message that should be kept in the archive." >> /tmp/base.log
    done

    for i in $(seq 1 5); do
        cp /tmp/base.log /var/log/app_logs/app_$i.log
    done
    rm /tmp/base.log

    chmod -R 777 /home/user
    chmod -R 777 /app
    chmod -R 777 /var/log/app_logs

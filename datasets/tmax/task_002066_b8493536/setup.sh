#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip coreutils tar
    pip3 install pytest

    # Create directories for dummy data
    mkdir -p /home/user/backup_data
    mkdir -p /tmp/dummy_logs/app1
    mkdir -p /tmp/dummy_logs/app2/nested

    # Create dummy log files
    echo "Info 1" > /tmp/dummy_logs/app1/service.info.log
    echo "Error 101: Timeout" > /tmp/dummy_logs/app1/db_timeout.err.log
    echo "Info 2" > /tmp/dummy_logs/app2/system.info.log
    echo "Error 500: Disk Full" > /tmp/dummy_logs/app2/nested/disk_full.err.log
    echo "Error 401: Auth" > /tmp/dummy_logs/app2/auth_fail.err.log

    # Create tarball and split it
    cd /tmp/dummy_logs
    tar -czf /tmp/system_logs.tar.gz .
    cd /home/user/backup_data
    # Use -d to ensure numeric suffixes (.00, .01, etc.) as required by tests
    split -b 150 -d /tmp/system_logs.tar.gz system_logs.tar.gz.

    # Cleanup temporary files
    rm -rf /tmp/dummy_logs /tmp/system_logs.tar.gz

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user

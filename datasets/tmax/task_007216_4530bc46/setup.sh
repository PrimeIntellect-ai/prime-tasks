#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tar coreutils
    pip3 install pytest watchdog

    mkdir -p /home/user/logs/subdir
    mkdir -p /home/user/archives
    mkdir -p /home/user/incoming

    # Setup Logs
    touch -d "10 days ago" "/home/user/logs/old app.log"
    dd if=/dev/urandom of="/home/user/logs/subdir/large file.log" bs=1M count=2 2>/dev/null
    echo "normal log" > "/home/user/logs/normal.log"

    # Setup Archives
    tar -czf /home/user/archives/backup_valid.tar.gz -C /home/user/logs normal.log
    echo "this is not a valid tarball" > /home/user/archives/backup_corrupted.tar.gz
    echo "garbage" > /home/user/archives/bad_archive.tar.gz

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user

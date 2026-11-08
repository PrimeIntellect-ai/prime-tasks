#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libc6-dev gawk sed
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/legacy_logs/dir1 /home/user/legacy_logs/dir2 /home/user/incoming /home/user/archive

    echo "INFO: Backup started\n[CRITICAL] Backup failed on /dev/sda1\nWARN: Low space" > /home/user/legacy_logs/dir1/db.log
    echo "[CRITICAL] Connection timeout to backup server\nINFO: Retrying..." > /home/user/legacy_logs/dir2/network.log
    echo "DEBUG: Nothing to report" > /home/user/legacy_logs/ignore.txt

    chown -R user:user /home/user/legacy_logs /home/user/incoming /home/user/archive
    chmod -R 777 /home/user

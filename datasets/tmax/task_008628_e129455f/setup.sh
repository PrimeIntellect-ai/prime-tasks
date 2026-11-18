#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tar gzip coreutils
    pip3 install pytest

    mkdir -p /home/user/logs
    cd /home/user

    # Create older logs
    for i in $(seq 1 10); do
        echo "INFO: System running normally - log file $i" > logs/file${i}.log
    done
    echo "FATAL: old error that was already backed up" >> logs/file2.log

    # Create full backup
    tar -czf full_backup.tar.gz logs/

    # Sleep to ensure timestamp difference
    sleep 2

    # Modify existing files
    echo "ERROR: Minor issue" >> logs/file3.log
    echo "FATAL: disk crash" >> logs/file3.log
    echo "WARN: High CPU" >> logs/file7.log

    # Create new files
    echo "INFO: New process started" > logs/file11.log
    echo "FATAL: memory leak" >> logs/file11.log
    echo "FATAL: cpu fire" >> logs/file11.log

    echo "DEBUG: Nothing to see here" > logs/file12.log

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user

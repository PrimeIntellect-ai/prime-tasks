#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip jq tar gzip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/backups

    # Normal backup
    mkdir -p /tmp/b1/a/b/c
    touch /tmp/b1/a/b/c/file.txt
    touch /tmp/b1/root.txt
    cd /tmp/b1 && tar -czf /home/user/backups/normal_backup.tar.gz a root.txt

    # Corrupted backup
    echo "This is not a valid tar gzip file, just some random text to simulate corruption." > /home/user/backups/corrupted_backup.tar.gz

    # Rogue backup
    mkdir -p /tmp/b3
    cd /tmp/b3
    DEEP_PATH="loop"
    for i in {1..25}; do
        DEEP_PATH="$DEEP_PATH/dir"
    done
    mkdir -p "$DEEP_PATH"
    touch "$DEEP_PATH/rogue_file.dat"
    tar -czf /home/user/backups/rogue_backup.tar.gz loop

    chmod -R 777 /home/user

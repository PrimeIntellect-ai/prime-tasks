#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    # Create the user
    useradd -m -s /bin/bash user || true

    # Create the backups directory
    mkdir -p /home/user/backups

    # Archive 1: Valid App A
    mkdir -p /tmp/backup_a
    echo '{"app_name": "FinanceApp", "version": "1.4.2"}' > /tmp/backup_a/metadata.json
    echo "fake data" > /tmp/backup_a/data.bin
    tar -czf /home/user/backups/alpha_backup.tar.gz -C /tmp/backup_a metadata.json data.bin

    # Archive 2: Valid App B
    mkdir -p /tmp/backup_b
    echo '{"app_name": "HRSystem", "version": "2.0.1"}' > /tmp/backup_b/metadata.json
    tar -czf /home/user/backups/beta_backup.tar.gz -C /tmp/backup_b metadata.json

    # Archive 3: Corrupted
    head -c 500 /dev/urandom > /home/user/backups/gamma_corrupted.tar.gz

    # Archive 4: Valid tarball but missing metadata.json
    mkdir -p /tmp/backup_d
    echo "just some text" > /tmp/backup_d/readme.txt
    tar -czf /home/user/backups/delta_missing.tar.gz -C /tmp/backup_d readme.txt

    # Cleanup temp dirs
    rm -rf /tmp/backup_a /tmp/backup_b /tmp/backup_d

    # Set permissions
    chmod -R 777 /home/user

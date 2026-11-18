#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    # Create directories
    mkdir -p /home/user/storage_mounts/vol1/appA
    mkdir -p /home/user/storage_mounts/vol1/appB
    mkdir -p /home/user/storage_mounts/vol2/logs
    mkdir -p /home/user/storage_mounts/vol3/archives/deep

    # File 1: Matches both criteria
    echo '{"retention_policy": "expired", "size_mb": 850, "type": "full"}' > /home/user/storage_mounts/vol1/appA/backup_001.metadata.json
    touch /home/user/storage_mounts/vol1/appA/backup_001.data

    # File 2: Size too small
    echo '{"retention_policy": "expired", "size_mb": 400, "type": "incremental"}' > /home/user/storage_mounts/vol1/appA/backup_002.metadata.json
    touch /home/user/storage_mounts/vol1/appA/backup_002.data

    # File 3: Not expired
    echo '{"retention_policy": "active", "size_mb": 1200, "type": "full"}' > /home/user/storage_mounts/vol1/appB/backup_003.metadata.json
    touch /home/user/storage_mounts/vol1/appB/backup_003.data

    # File 4: Matches both criteria
    echo '{"retention_policy": "expired", "size_mb": 1500, "type": "full"}' > /home/user/storage_mounts/vol2/logs/backup_004.metadata.json
    touch /home/user/storage_mounts/vol2/logs/backup_004.data

    # File 5: Matches both criteria (exactly 500 should FAIL, > 500 is required, this is 501 so it matches)
    echo '{"retention_policy": "expired", "size_mb": 501, "type": "incremental"}' > /home/user/storage_mounts/vol3/archives/deep/backup_005.metadata.json
    touch /home/user/storage_mounts/vol3/archives/deep/backup_005.data

    # File 6: Exactly 500 (fails criteria)
    echo '{"retention_policy": "expired", "size_mb": 500, "type": "incremental"}' > /home/user/storage_mounts/vol3/archives/deep/backup_006.metadata.json
    touch /home/user/storage_mounts/vol3/archives/deep/backup_006.data

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user

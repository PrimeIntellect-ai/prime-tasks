#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gzip tar coreutils
    pip3 install pytest

    mkdir -p /home/user/raw_backups/
    mkdir -p /home/user/clean_configs/

    cd /home/user

    # Create Backup 1 (Valid)
    mkdir -p backup1/src/configs
    mkdir -p backup1/var/logs
    echo '{"db": "mysql", "host": "localhost"}' > backup1/src/configs/db_config.json
    echo "INFO: Startup" > backup1/var/logs/app1.log
    echo "CRITICAL: Database connection lost in app1" >> backup1/var/logs/app1.log
    gzip backup1/var/logs/app1.log
    tar -czf raw_backups/backup_alpha.tar.gz -C backup1 .

    # Create Backup 2 (Corrupted)
    mkdir -p backup2/app/configs
    mkdir -p backup2/logs
    echo '{"api_key": "12345"}' > backup2/app/configs/api_config.json
    echo "CRITICAL: Corrupted archive leak" > backup2/logs/app2.log
    gzip backup2/logs/app2.log
    tar -czf raw_backups/backup_beta.tar.gz -C backup2 .
    # Corrupt the archive by overwriting a chunk in the middle
    dd if=/dev/urandom of=raw_backups/backup_beta.tar.gz bs=1 count=50 seek=50 conv=notrunc

    # Create Backup 3 (Valid)
    mkdir -p backup3/etc
    mkdir -p backup3/logs/old
    echo '{"cache": "redis", "ttl": 3600}' > backup3/etc/cache_config.json
    echo "WARN: Disk space low" > backup3/logs/old/sys.log
    echo "CRITICAL: Out of memory in sys" >> backup3/logs/old/sys.log
    gzip backup3/logs/old/sys.log
    tar -czf raw_backups/backup_gamma.tar.gz -C backup3 .

    rm -rf backup1 backup2 backup3

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user

#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tar coreutils
    pip3 install pytest

    mkdir -p /home/user/backups /home/user/current_configs /home/user/external_targets
    cd /home/user

    # Create legacy state
    mkdir -p legacy_temp/network legacy_temp/app legacy_temp/db
    echo "net.ipv4.ip_forward=1" > legacy_temp/network/sysctl.conf
    echo "port=8080" > legacy_temp/app/server.conf
    echo "max_connections=100" > legacy_temp/db/postgres.conf
    echo "some old data" > legacy_temp/db/tuning.conf

    # Package legacy state into internal_configs.tar
    cd legacy_temp
    tar -cf ../internal_configs.tar ./*
    cd ..

    # Package internal_configs.tar into a split tar.gz
    tar -czf legacy_backup.tar.gz internal_configs.tar
    # Use -d to generate numeric suffixes (.00, .01, etc.)
    split -d -b 150 legacy_backup.tar.gz /home/user/backups/legacy_backup.tar.gz.

    # Clean up legacy temp
    rm -rf legacy_temp internal_configs.tar legacy_backup.tar.gz

    # Create current state
    cd /home/user/current_configs
    mkdir -p network app db

    # MODIFIED file
    echo "net.ipv4.ip_forward=1" > network/sysctl.conf
    echo "net.ipv4.conf.all.rp_filter=1" >> network/sysctl.conf

    # UNMODIFIED file
    echo "port=8080" > app/server.conf

    # DELETED file (tuning.conf is gone, postgres.conf remains untouched)
    echo "max_connections=100" > db/postgres.conf

    # NEW file
    echo "log_level=DEBUG" > app/logging.conf

    # NEW SYMLINK pointing to an external target
    echo "external_config_data=true" > /home/user/external_targets/ext.conf
    ln -s /home/user/external_targets/ext.conf network/routing.conf

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user/backups /home/user/current_configs /home/user/external_targets
    chmod -R 777 /home/user

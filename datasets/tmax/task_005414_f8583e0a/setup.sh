#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tar coreutils
    pip3 install pytest

    mkdir -p /home/user/backups
    mkdir -p /home/user/source_base
    mkdir -p /home/user/source_incr

    echo "base_data_1" > /home/user/source_base/fileA.txt
    echo "unchanged_data" > /home/user/source_base/fileB.txt
    echo "old_config" > /home/user/source_base/config.ini

    echo "unchanged_data" > /home/user/source_incr/fileB.txt
    echo "new_config" > /home/user/source_incr/config.ini
    echo "new_data_1" > /home/user/source_incr/fileC.txt

    cd /home/user/source_base
    tar -czf /home/user/backups/base_backup.tar.gz *

    cd /home/user/source_incr
    tar -czf - * | split -b 100 - /home/user/backups/incr_backup.tar.gz.part
    mv /home/user/backups/incr_backup.tar.gz.partaa /home/user/backups/incr_backup.tar.gz.part1
    mv /home/user/backups/incr_backup.tar.gz.partab /home/user/backups/incr_backup.tar.gz.part2

    rm -rf /home/user/source_base /home/user/source_incr

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user

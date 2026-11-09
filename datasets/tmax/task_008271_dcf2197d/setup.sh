#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl openssl tar tzdata
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/archive_source
    echo "Winter data" > /home/user/archive_source/report_20230110_080000.dat
    echo "Summer data" > /home/user/archive_source/report_20230715_143000.dat

    cd /home/user/archive_source && tar -czf /home/user/reports_backup.tar.gz *.dat
    rm -rf /home/user/archive_source

    chmod -R 777 /home/user

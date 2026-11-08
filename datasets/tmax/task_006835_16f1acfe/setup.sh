#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make tar gzip findutils
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/logs/app1
    mkdir -p /home/user/logs/app2
    mkdir -p /home/user/logs/db

    # Create files that do NOT contain the string
    echo "Standard info log entry 1" > /home/user/logs/app1/info.log
    echo "Debug sequence initiated" > /home/user/logs/app2/debug.log
    echo "SELECT * FROM users;" > /home/user/logs/db/query.log
    echo "ARCHIVE_M false alarm" > /home/user/logs/db/other.log

    # Create files that DO contain the string
    echo -e "Error 404\nARCHIVE_ME\nStack trace..." > /home/user/logs/app1/error.log
    echo "System crashed. ARCHIVE_ME to cold storage." > /home/user/logs/app2/crash.log
    echo "ARCHIVE_ME" > /home/user/logs/db/corruption.log

    chmod -R 777 /home/user

#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gzip tar
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/logs_staging/app1/nested
    mkdir -p /home/user/logs_staging/app2
    mkdir -p /home/user/logs_staging/app3/empty

    # Create dummy logs
    echo "LogEntry: [2023-10-01] - Critical failure in module A" | gzip > /home/user/logs_staging/app1/error.log.gz
    echo "LogEntry: [2023-10-02] - Debug: connection timeout" | gzip > /home/user/logs_staging/app1/nested/debug.log.gz
    echo "LogEntry: [2023-10-01] - Warning: memory high" | gzip > /home/user/logs_staging/app2/warn.log.gz
    echo "LogEntry: [2023-09-15] - Info: system boot" | gzip > /home/user/logs_staging/app3/sys.log.gz

    # Create decoy files
    echo "Just a text file" > /home/user/logs_staging/app1/readme.txt
    echo "LogEntry: [2023-12-01]" > /home/user/logs_staging/app2/uncompressed.log

    chmod -R 777 /home/user

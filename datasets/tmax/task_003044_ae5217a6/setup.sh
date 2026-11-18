#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tar bash
    pip3 install pytest

    mkdir -p /home/user/setup_logs/dir1/subdirA
    mkdir -p /home/user/setup_logs/dir2

    # Create mock log files
    for i in {1..120}; do echo "Log entry $i for app1" >> /home/user/setup_logs/dir1/app1.log; done
    for i in {1..40}; do echo "Log entry $i for app2" >> /home/user/setup_logs/dir1/subdirA/app2.log; done
    for i in {1..210}; do echo "Log entry $i for db_sync" >> /home/user/setup_logs/dir2/db_sync.log; done

    # Create some non-log files that should be ignored
    echo "Just some notes" > /home/user/setup_logs/dir1/notes.txt
    echo "More data" > /home/user/setup_logs/dir2/data.dat

    # Create the incoming archive
    cd /home/user/setup_logs
    tar -cf /home/user/incoming_logs.tar .
    cd /home/user
    rm -rf /home/user/setup_logs

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user

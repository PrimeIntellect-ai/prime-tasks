#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip zip unzip tar
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/legacy_backups/server1
    mkdir -p /home/user/legacy_backups/server2
    mkdir -p /home/user/restored

    # Create reference file
    touch -d "2023-01-01 12:00:00" /home/user/last_backup.ref

    # Setup server1 data
    mkdir -p /tmp/server1_data
    echo "Old data" > /tmp/server1_data/file1.txt
    touch -d "2022-12-01 10:00:00" /tmp/server1_data/file1.txt
    echo "New data 1" > /tmp/server1_data/file2.txt
    touch -d "2023-05-01 10:00:00" /tmp/server1_data/file2.txt

    cd /tmp/server1_data
    tar -cf /tmp/server1_data.tar file1.txt file2.txt
    cd /tmp
    zip /home/user/legacy_backups/server1/backup.zip server1_data.tar

    # Setup server2 data
    mkdir -p /tmp/server2_data
    echo "New data 2" > /tmp/server2_data/file3.txt
    touch -d "2023-06-01 10:00:00" /tmp/server2_data/file3.txt
    echo "Old data 2" > /tmp/server2_data/file4.txt
    touch -d "2022-11-01 10:00:00" /tmp/server2_data/file4.txt

    cd /tmp/server2_data
    tar -cf /tmp/server2_data.tar file3.txt file4.txt
    cd /tmp
    zip /home/user/legacy_backups/server2/backup.zip server2_data.tar

    # Cleanup tmp
    rm -rf /tmp/server1_data /tmp/server2_data /tmp/server1_data.tar /tmp/server2_data.tar

    chmod -R 777 /home/user

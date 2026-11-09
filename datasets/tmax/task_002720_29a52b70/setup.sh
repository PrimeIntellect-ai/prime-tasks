#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ zip unzip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/archives
    mkdir -p /home/user/valid_backups

    # Create valid zip archives
    echo "Data for v1.0" > /tmp/data1.txt
    zip -j /home/user/archives/backup1.zip /tmp/data1.txt

    echo "Data for v2.0" > /tmp/data2.txt
    zip -j /home/user/archives/backup2.zip /tmp/data2.txt

    # Create a corrupted zip archive
    echo "Data for v3.0" > /tmp/data3.txt
    zip -j /home/user/archives/backup3.zip /tmp/data3.txt
    dd if=/dev/urandom of=/home/user/archives/backup3.zip bs=1 count=10 conv=notrunc

    # Create the multi-line log file
    cat << 'EOF' > /home/user/backup_history.log
Record Start
Version: v1.0
Archive: /home/user/archives/backup1.zip
Status: complete

Record Start
Version: v2.0
Archive: /home/user/archives/backup2.zip
Status: complete

Record Start
Version: v3.0
Archive: /home/user/archives/backup3.zip
Status: complete
EOF

    chmod -R 777 /home/user

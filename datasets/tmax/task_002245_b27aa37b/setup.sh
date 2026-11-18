#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip zip
    pip3 install pytest

    mkdir -p /home/user/backups
    mkdir -p /tmp/zip_setup
    cd /tmp/zip_setup

    dd if=/dev/zero of=file1.dat bs=1 count=15000
    dd if=/dev/zero of=file2.dat bs=1 count=25000
    dd if=/dev/zero of=file3.dat bs=1 count=8000
    dd if=/dev/zero of=file4.dat bs=1 count=42000

    zip -j /home/user/backups/app_backup.zip file1.dat file3.dat
    zip -j /home/user/backups/db_backup.zip file2.dat
    zip -j /home/user/backups/media_backup.zip file4.dat file1.dat

    echo "Not a real zip file, just some random text." > /home/user/backups/corrupt_backup.zip
    echo -ne "PK\x00\x00some corrupted data here" > /home/user/backups/fake.zip

    rm -rf /tmp/zip_setup

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user

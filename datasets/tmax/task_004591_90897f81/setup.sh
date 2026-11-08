#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip zip unzip tar gzip file gawk
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/storage_dump/folder1/subfolder
    mkdir -p /home/user/storage_dump/folder2

    # Valid Zip (misnamed as .txt)
    echo "test data" > /tmp/test.txt
    zip -j /home/user/storage_dump/folder1/hidden_zip.txt /tmp/test.txt

    # Corrupt Zip
    printf "PK\003\004broken" > /home/user/storage_dump/folder1/subfolder/bad.zip

    # Valid Tar
    tar -cf /home/user/storage_dump/folder2/backup.dat -C /tmp test.txt

    # Duplicate Valid Tar
    cp /home/user/storage_dump/folder2/backup.dat /home/user/storage_dump/folder2/backup_copy.dat

    # Not Archive
    echo "Just some plain text" > /home/user/storage_dump/folder1/readme.md

    chown -R user:user /home/user/storage_dump
    chmod -R 777 /home/user

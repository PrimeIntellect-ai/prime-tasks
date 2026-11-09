#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip zip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/project_blobs/dir1
    mkdir -p /home/user/project_blobs/dir2/nested

    # 1. Valid Zip file 1 (misleading extension)
    echo "content1" > /tmp/f1.txt
    cd /tmp && zip f1.zip f1.txt >/dev/null
    cp /tmp/f1.zip /home/user/project_blobs/dir1/blobA.dat
    # Copy as duplicate
    cp /tmp/f1.zip /home/user/project_blobs/dir2/nested/blobA_copy.bin

    # 2. Valid Zip file 2 (no extension)
    echo "different content" > /tmp/f2.txt
    cd /tmp && zip f2.zip f2.txt >/dev/null
    cp /tmp/f2.zip /home/user/project_blobs/dir2/blobB

    # 3. Valid Zip file 3 (standard extension)
    echo "more content" > /tmp/f3.txt
    cd /tmp && zip f3.zip f3.txt >/dev/null
    cp /tmp/f3.zip /home/user/project_blobs/dir1/blobC.zip

    # 4. Fake Zip file (misleading extension, not a zip)
    echo "I am just a text file but named like a zip" > /home/user/project_blobs/dir1/fake.zip

    # 5. Non-zip binary
    dd if=/dev/urandom of=/home/user/project_blobs/dir2/random.dat bs=1024 count=1 2>/dev/null

    chmod -R 777 /home/user

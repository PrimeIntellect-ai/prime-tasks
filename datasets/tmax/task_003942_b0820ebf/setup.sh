#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tar gzip coreutils
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/backups
    cd /home/user

    # Create source files for inc_01
    mkdir -p src1/dir1
    echo "Initial data for file 1" > src1/file1.txt
    echo "Initial data for file 2" > src1/dir1/file2.txt
    tar -czf backups/inc_01.tar.gz -C src1 .

    # Create source files for inc_02 with a zip-slip payload
    mkdir -p src2
    echo "Updated data for file 1" > src2/file1.txt
    echo "Malicious payload 1" > src2/bad1.txt
    tar -cf backups/inc_02.tar -C src2 file1.txt
    tar -rf backups/inc_02.tar -P -C src2 bad1.txt --transform='s,^bad1.txt,../bad1.txt,'
    gzip backups/inc_02.tar

    # Create source files for inc_03 with an absolute path payload
    mkdir -p src3/dir2
    echo "New file 3" > src3/dir2/file3.txt
    echo "Malicious payload 2" > src3/bad2.txt
    tar -cf backups/inc_03.tar -C src3 dir2/file3.txt
    tar -rf backups/inc_03.tar -P -C src3 bad2.txt --transform='s,^bad2.txt,/etc/malicious.txt,'
    gzip backups/inc_03.tar

    rm -rf src1 src2 src3

    chmod -R 777 /home/user

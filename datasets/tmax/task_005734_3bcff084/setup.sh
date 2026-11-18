#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc gzip coreutils
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/data_source/dirA
    mkdir -p /home/user/data_source/dirB/dirC

    # Regular files
    echo "Hello World! This is a test file for deduplication." > /home/user/data_source/file1.txt
    echo "Hello World! This is a test file for deduplication." > /home/user/data_source/dirA/file2.txt
    echo "Different content for file 3." > /home/user/data_source/dirB/file3.txt
    echo "Different content for file 3." > /home/user/data_source/dirB/dirC/file4.txt

    # Symlink loops
    ln -s /home/user/data_source /home/user/data_source/dirA/loop1
    ln -s ../dirB /home/user/data_source/dirB/dirC/loop2

    chmod -R 777 /home/user

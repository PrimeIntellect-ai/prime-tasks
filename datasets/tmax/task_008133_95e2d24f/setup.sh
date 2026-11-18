#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip util-linux findutils tar gzip coreutils
    pip3 install pytest

    mkdir -p /home/user/incoming
    mkdir -p /home/user/repo

    # Create 5 random binary files
    dd if=/dev/urandom of=/home/user/incoming/file1.bin bs=1M count=3
    dd if=/dev/urandom of=/home/user/incoming/file2.bin bs=1M count=2
    dd if=/dev/urandom of=/home/user/incoming/file3.bin bs=1M count=4
    dd if=/dev/urandom of=/home/user/incoming/file4.bin bs=1M count=5
    dd if=/dev/urandom of=/home/user/incoming/file5.bin bs=1M count=3

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user

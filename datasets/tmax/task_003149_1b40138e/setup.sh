#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip rustc netcat-openbsd
    pip3 install pytest

    mkdir -p /home/user/user_data/subdir
    dd if=/dev/zero of=/home/user/user_data/file1.dat bs=1000 count=3
    dd if=/dev/zero of=/home/user/user_data/subdir/file2.dat bs=1000 count=3

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user

#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip binutils tar gawk coreutils
    pip3 install pytest

    mkdir -p /home/user/incoming_artifacts /home/user/curated_repo /home/user/backups

    cp /bin/ls /home/user/incoming_artifacts/bin_ls
    cp /bin/echo /home/user/incoming_artifacts/bin_echo
    cp /lib/x86_64-linux-gnu/libc.so.6 /home/user/incoming_artifacts/libc.so
    echo "This is a readme." > /home/user/incoming_artifacts/readme.txt
    dd if=/dev/urandom of=/home/user/incoming_artifacts/corrupt.bin bs=1K count=1

    tar --listed-incremental=/home/user/backups/repo.snar -cvf /home/user/backups/base.tar /home/user/curated_repo

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user

#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    mkdir -p /home/user/src \
             /home/user/bin \
             /home/user/logs \
             /home/user/users/alice \
             /home/user/users/bob/docs \
             /home/user/users/charlie

    dd if=/dev/zero of=/home/user/users/alice/file1.dat bs=1000 count=2
    dd if=/dev/zero of=/home/user/users/alice/file2.dat bs=1000 count=4
    dd if=/dev/zero of=/home/user/users/bob/docs/large.dat bs=1000 count=15
    dd if=/dev/zero of=/home/user/users/charlie/data.bin bs=1000 count=12

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user

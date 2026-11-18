#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip coreutils
    pip3 install pytest

    mkdir -p /home/user/binary_repo/alpha
    mkdir -p /home/user/binary_repo/beta/gamma
    mkdir -p /home/user/binary_repo/delta

    echo -n "Hello, Artifact Manager. This is a test." > /home/user/binary_repo/alpha/item1.dat
    head -c 100 /dev/zero > /home/user/binary_repo/beta/gamma/nulls.dat
    echo -n "Another artifact" > /home/user/binary_repo/delta/data.dat
    echo -n "Ignore me" > /home/user/binary_repo/delta/ignore.txt

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user/binary_repo
    chmod -R 777 /home/user

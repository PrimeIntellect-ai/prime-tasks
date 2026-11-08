#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    apt-get install -y zlib1g-dev libssl-dev build-essential gzip

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/repo/subdir
    mkdir -p /home/user/repo/loop

    # Create artifacts
    echo -n "artifact_one_data" > /tmp/a1
    echo -n "artifact_two_data_v2" > /tmp/a2
    echo -n "artifact_three_data_final" > /tmp/a3

    gzip -c /tmp/a1 > /home/user/repo/art1.gz
    gzip -c /tmp/a2 > /home/user/repo/subdir/art2.gz
    gzip -c /tmp/a3 > /home/user/repo/subdir/art3.gz

    # Create symlink loop
    ln -s ../loop /home/user/repo/loop/inf
    ln -s ../subdir /home/user/repo/loop/fake_subdir

    chown -R user:user /home/user/repo
    chmod -R 777 /home/user

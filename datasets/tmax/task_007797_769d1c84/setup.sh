#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tar gzip coreutils
    pip3 install pytest

    mkdir -p /home/user/research_data
    mkdir -p /tmp/setup_workspace/messy/dir1
    mkdir -p /tmp/setup_workspace/messy/dir2
    mkdir -p /tmp/setup_workspace/messy/dir3
    mkdir -p /tmp/setup_workspace/messy/logs

    cd /tmp/setup_workspace

    head -c 15000 /dev/zero > messy/dir1/alpha.dat
    touch -d "2023-05-01 12:00:00" messy/dir1/alpha.dat

    head -c 20000 /dev/zero > messy/dir2/beta.dat
    touch -d "2022-12-01 12:00:00" messy/dir2/beta.dat

    head -c 5000 /dev/zero > messy/dir3/gamma.dat
    touch -d "2023-06-01 12:00:00" messy/dir3/gamma.dat

    head -c 12000 /dev/zero > messy/dir3/delta.dat
    touch -d "2023-08-01 12:00:00" messy/dir3/delta.dat

    touch -d "2023-01-01 10:00:00" messy/logs/run1.log
    touch -d "2023-09-01 15:00:00" messy/logs/run2.log
    touch -d "2023-08-01 10:00:00" messy/logs/run3.log

    tar -czf /home/user/research_data/raw_dump.tar.gz messy/
    cd /home/user
    rm -rf /tmp/setup_workspace

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user

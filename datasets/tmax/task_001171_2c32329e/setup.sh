#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc zip unzip file tar gzip coreutils
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/artifacts_raw/dir1/dir2
    mkdir -p /home/user/artifacts_raw/dir3

    # Create ARM ELF
    echo -ne '\x7fELF\x01\x01\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00\x02\x00\x28\x00\x01\x00\x00\x00' > /home/user/artifacts_raw/dir1/arm_app1

    # Create x86 ELF
    echo 'int main() { return 0; }' > /tmp/test.c
    gcc /tmp/test.c -o /home/user/artifacts_raw/dir3/x86_app

    # Create GCode
    echo -e "G21\nG90\nG28 X Y\nG1 X10" > /home/user/artifacts_raw/dir1/dir2/print1.gcode
    echo -e "G21\nG90\nG1 X10" > /home/user/artifacts_raw/dir3/print2.gcode

    # Create WAL files
    echo -ne '\x37\x7f\x06\x82\x00\x00\x00\x00' > /home/user/artifacts_raw/dir3/db1.wal
    echo -ne '\x37\x7f\x06\x83\x00\x00\x00\x00' > /home/user/artifacts_raw/dir1/db2.wal
    echo -ne '\x37\x7f\x06\x84\x00\x00\x00\x00' > /home/user/artifacts_raw/dir1/dir2/db3.wal

    # Create noise
    echo "Just some text" > /home/user/artifacts_raw/readme.txt

    cd /home/user/artifacts_raw
    tar -czvf /home/user/raw_artifacts.tar.gz *
    cd /home/user
    rm -rf /home/user/artifacts_raw

    chmod -R 777 /home/user

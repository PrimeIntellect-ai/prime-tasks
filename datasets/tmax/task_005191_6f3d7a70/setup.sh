#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip coreutils gzip
    pip3 install pytest

    mkdir -p /home/user/repo/libs
    mkdir -p /home/user/repo/docs

    # Create app.bin: 2,500,000 bytes of 'A'
    head -c 2500000 /dev/zero | tr '\0' 'A' > /home/user/repo/app.bin

    # Create libcore.so: 1,200,000 bytes of 'B'
    head -c 1200000 /dev/zero | tr '\0' 'B' > /home/user/repo/libs/libcore.so

    # Create readme.txt: 500,000 bytes of 'C'
    head -c 500000 /dev/zero | tr '\0' 'C' > /home/user/repo/docs/readme.txt

    # Create exact 1,000,000 bytes file (should be ignored)
    head -c 1000000 /dev/zero | tr '\0' 'D' > /home/user/repo/ignored.dat

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user

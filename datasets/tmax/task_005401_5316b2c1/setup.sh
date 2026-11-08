#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make tar
    pip3 install pytest

    mkdir -p /home/user/dataset_source
    cd /home/user/dataset_source

    # Create valid data files
    head -c 1024 /dev/urandom > data_alpha.dat
    head -c 2048 /dev/urandom > data_beta.dat
    head -c 512 /dev/urandom > data_gamma.dat

    # Create infinite symlink loop
    mkdir loops
    cd loops
    ln -s loop2 loop1
    ln -s loop1 loop2
    cd ..

    # Create transfer.log
    cat << 'EOF' > transfer.log
---RECORD---
DatasetID: 101
Status: SUCCESS
Path: data_alpha.dat
------------
---RECORD---
DatasetID: 102
Status: FAILED
Path: data_gamma.dat
------------
---RECORD---
DatasetID: 103
Status: SUCCESS
Path: loops/loop1/fake.dat
------------
---RECORD---
DatasetID: 104
Status: SUCCESS
Path: data_beta.dat
------------
EOF

    # Create the archive
    cd /home/user
    tar -czf dataset_archive.tar.gz -C dataset_source .
    rm -rf dataset_source

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user

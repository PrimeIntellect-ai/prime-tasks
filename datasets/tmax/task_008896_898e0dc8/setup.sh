#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ tar
    pip3 install pytest

    mkdir -p /home/user/extracted
    mkdir -p /tmp/dataset_build
    cd /tmp/dataset_build
    touch valid_data1.txt
    touch valid_data2.csv
    mkdir subdir
    touch subdir/valid3.txt

    # Create archive with normal files
    tar -cf /home/user/dataset.tar valid_data1.txt valid_data2.csv subdir/valid3.txt

    # Append malicious files using tar's transform
    touch malicious1.sh
    touch malicious2.txt
    tar -rf /home/user/dataset.tar -P --transform 's|^|/tmp/|' malicious1.sh
    tar -rf /home/user/dataset.tar -P --transform 's|^|../|' malicious2.txt

    rm -rf /tmp/dataset_build

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user

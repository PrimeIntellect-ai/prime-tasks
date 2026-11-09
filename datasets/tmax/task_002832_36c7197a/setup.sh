#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip zip unzip bzip2 tar coreutils
    pip3 install pytest

    mkdir -p /home/user/raw_dataset
    mkdir -p /home/user/.setup_tmp

    # Create valid sub-archive 1
    mkdir -p /home/user/.setup_tmp/valid_data1
    echo "Subject 1 Data" > /home/user/.setup_tmp/valid_data1/info.txt
    echo "DUPLICATE CONTENT MATCH" > /home/user/.setup_tmp/valid_data1/shared_measurements.txt
    cd /home/user/.setup_tmp/valid_data1
    zip -r ../valid_data1.zip ./*

    # Create valid sub-archive 2
    mkdir -p /home/user/.setup_tmp/valid_data2
    echo "Subject 2 Data" > /home/user/.setup_tmp/valid_data2/info.txt
    echo "DUPLICATE CONTENT MATCH" > /home/user/.setup_tmp/valid_data2/shared_measurements_copy.txt
    ln -s /non/existent/path /home/user/.setup_tmp/valid_data2/broken_link.txt
    cd /home/user/.setup_tmp/valid_data2
    tar -czf ../valid_data2.tar.gz ./*

    # Create corrupted archive
    echo "This is not a real zip file, it will fail integrity checks." > /home/user/.setup_tmp/corrupt_data.zip

    # Create the master archive
    cd /home/user/.setup_tmp
    tar -czf master_dataset.tar.gz valid_data1.zip valid_data2.tar.gz corrupt_data.zip

    # Split the master archive
    split -b 1K master_dataset.tar.gz /home/user/raw_dataset/dataset.tar.gz.part
    rm -rf /home/user/.setup_tmp

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user

#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang zip unzip tar
    pip3 install pytest

    mkdir -p /home/user/raw_data/
    mkdir -p /tmp/dataset_builder

    # Create inner data for batch 1
    mkdir -p /tmp/dataset_builder/batch1
    echo "42" > /tmp/dataset_builder/batch1/sensor_A1.txt
    echo "15" > /tmp/dataset_builder/batch1/sensor_A2.txt
    tar -czf /tmp/dataset_builder/batch1.tar.gz -C /tmp/dataset_builder batch1

    # Create inner data for batch 2
    mkdir -p /tmp/dataset_builder/batch2
    echo "99" > /tmp/dataset_builder/batch2/sensor_B1.txt
    echo "7" > /tmp/dataset_builder/batch2/sensor_B2.txt
    tar -czf /tmp/dataset_builder/batch2.tar.gz -C /tmp/dataset_builder batch2

    # Create master zip
    cd /tmp/dataset_builder
    zip -r /home/user/raw_data/dataset.zip batch1.tar.gz batch2.tar.gz

    # Cleanup
    rm -rf /tmp/dataset_builder

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user

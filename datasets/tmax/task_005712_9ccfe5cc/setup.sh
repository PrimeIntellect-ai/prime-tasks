#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip jq tar coreutils
    pip3 install pytest

    mkdir -p /home/user/incoming
    mkdir -p /tmp/dataset_setup

    cd /tmp/dataset_setup

    # Run 1 (High Quality)
    mkdir run_01
    echo '{"sensor_id": "S-100", "quality": "high", "location": "North"}' > run_01/meta.json
    echo "timestamp,value" > run_01/data.csv
    echo "1700000010,42.5" >> run_01/data.csv
    echo "1700000011,42.6" >> run_01/data.csv

    # Run 2 (Low Quality)
    mkdir run_02
    echo '{"sensor_id": "S-102", "quality": "low", "location": "South"}' > run_02/meta.json
    echo "timestamp,value" > run_02/data.csv
    echo "1700000005,12.0" >> run_02/data.csv
    echo "1700000006,12.1" >> run_02/data.csv

    # Run 3 (High Quality)
    mkdir run_03
    echo '{"sensor_id": "S-105", "quality": "high", "location": "East"}' > run_03/meta.json
    echo "timestamp,value" > run_03/data.csv
    echo "1700000001,43.1" >> run_03/data.csv
    echo "1700000002,43.2" >> run_03/data.csv

    # Run 4 (Corrupted / Medium Quality)
    mkdir run_04
    echo '{"sensor_id": "S-110", "quality": "medium", "location": "West"}' > run_04/meta.json
    echo "timestamp,value" > run_04/data.csv
    echo "1700000020,33.1" >> run_04/data.csv

    # Package and split
    tar -czf dataset.tar.gz run_*
    split -b 200 dataset.tar.gz /home/user/incoming/dataset.tar.gz.

    # Cleanup
    cd /
    rm -rf /tmp/dataset_setup

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user

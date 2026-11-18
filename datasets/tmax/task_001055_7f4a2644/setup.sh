#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest

    # Create the user
    useradd -m -s /bin/bash user || true

    # Setup directories
    mkdir -p /home/user/containers/c1
    mkdir -p /home/user/containers/c2
    mkdir -p /home/user/containers/c3
    mkdir -p /home/user/backups

    # c1 is healthy
    echo "HEALTHY" > /home/user/containers/c1/status.txt
    echo "valid_data_1" > /home/user/containers/c1/data.bin
    echo "valid_data_1" > /home/user/backups/c1_data.bin

    # c2 is unhealthy
    echo "UNHEALTHY" > /home/user/containers/c2/status.txt
    echo "corrupted_data_2" > /home/user/containers/c2/data.bin
    echo "valid_data_2_backup_payload" > /home/user/backups/c2_data.bin

    # c3 is unhealthy
    echo "UNHEALTHY" > /home/user/containers/c3/status.txt
    echo "corrupted_data_3" > /home/user/containers/c3/data.bin
    echo "valid_data_3_backup_payload" > /home/user/backups/c3_data.bin

    chmod -R 777 /home/user

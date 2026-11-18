#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip zip tar
    pip3 install pytest

    # Create user
    useradd -m -s /bin/bash user || true

    # Ensure directories exist
    mkdir -p /home/user/setup_workspace/sensor_A
    mkdir -p /home/user/setup_workspace/sensor_B

    # Generate deterministic log files
    for i in {1..60}; do echo "Sensor_A_1 reading $i" >> /home/user/setup_workspace/sensor_A/A_1.log; done
    for i in {1..60}; do echo "Sensor_A_2 reading $i" >> /home/user/setup_workspace/sensor_A/A_2.log; done
    for i in {1..60}; do echo "Sensor_B_1 reading $i" >> /home/user/setup_workspace/sensor_B/B_1.log; done
    for i in {1..60}; do echo "Sensor_B_2 reading $i" >> /home/user/setup_workspace/sensor_B/B_2.log; done

    # Zip them up
    cd /home/user/setup_workspace/sensor_A && zip -q A_data.zip A_1.log A_2.log
    cd /home/user/setup_workspace/sensor_B && zip -q B_data.zip B_1.log B_2.log

    # Move zips to a central tar directory
    mkdir -p /home/user/tar_workspace
    mv /home/user/setup_workspace/sensor_A/A_data.zip /home/user/tar_workspace/
    mv /home/user/setup_workspace/sensor_B/B_data.zip /home/user/tar_workspace/

    # Create the nested tar.gz
    cd /home/user/tar_workspace && tar -czf /home/user/raw_data.tar.gz A_data.zip B_data.zip

    # Clean up setup workspace
    rm -rf /home/user/setup_workspace /home/user/tar_workspace

    # Set permissions
    chown -R user:user /home/user
    chmod -R 777 /home/user

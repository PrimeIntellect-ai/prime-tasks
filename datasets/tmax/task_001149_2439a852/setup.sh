#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make wget tar
    pip3 install pytest

    # Create user
    useradd -m -s /bin/bash user || true

    # Download and extract cJSON
    mkdir -p /app
    cd /app
    wget https://github.com/DaveGamble/cJSON/archive/refs/tags/v1.7.15.tar.gz
    tar xf v1.7.15.tar.gz
    rm v1.7.15.tar.gz

    # Perturb the Makefile
    sed -i 's/^CC = gcc/CC = arm-linux-gnueabihf-gcc/' /app/cJSON-1.7.15/Makefile
    # Ensure it's there in case the sed didn't match exactly
    if ! grep -q "CC = arm-linux-gnueabihf-gcc" /app/cJSON-1.7.15/Makefile; then
        sed -i '1s/^/CC = arm-linux-gnueabihf-gcc\n/' /app/cJSON-1.7.15/Makefile
    fi

    # Set up corpora
    mkdir -p /app/corpus/clean /app/corpus/evil
    echo '{"sensor_id": "s1", "value": 1.0}' > /app/corpus/clean/1.json
    echo '{"sensor_id": "sensor_002", "value": -40.5}' > /app/corpus/clean/2.json
    echo '{"sensor_id": "abcdefghijklmnopqrstuvwxyz12345", "value": 0}' > /app/corpus/clean/3.json

    echo '{"sensor_id": "s1", "value": "1.0"}' > /app/corpus/evil/1.json
    echo '{"sensor_id": "abcdefghijklmnopqrstuvwxyz123456", "value": 1.0}' > /app/corpus/evil/2.json
    echo '{"value": 1.0}' > /app/corpus/evil/3.json
    echo '{"sensor_id": "s1"}' > /app/corpus/evil/4.json
    echo '{malformed json' > /app/corpus/evil/5.json

    # Setup pre-existing state for deployment script to backup
    mkdir -p /home/user/opt/edge_sensor/releases/v1
    touch /home/user/opt/edge_sensor/releases/v1/dummy_binary
    ln -s /home/user/opt/edge_sensor/releases/v1 /home/user/opt/edge_sensor/current

    chown -R user:user /home/user/opt

    chmod -R 777 /home/user

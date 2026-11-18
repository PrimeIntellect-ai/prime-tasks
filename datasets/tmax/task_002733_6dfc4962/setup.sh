#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip zip unzip coreutils
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/datasets
    cd /home/user/datasets

    # Helper function to create a binary file with anomalies at specific offsets
    create_bin() {
        local file=$1
        shift
        # Create 10KB of null bytes
        dd if=/dev/zero of="$file" bs=1024 count=10 2>/dev/null
        # Inject ANOMALY_778 at given offsets
        for offset in "$@"; do
            echo -n "ANOMALY_778" | dd of="$file" bs=1 seek=$offset conv=notrunc 2>/dev/null
        done
    }

    # 1. Valid zip with 2 anomalies
    create_bin measurements.bin 1024 4096
    zip data_01.zip measurements.bin
    rm measurements.bin

    # 2. Corrupted zip
    create_bin measurements.bin 500
    zip data_02.zip measurements.bin
    rm measurements.bin
    # Corrupt it by truncating
    truncate -s 100 data_02.zip

    # 3. Valid zip with 1 anomaly
    create_bin measurements.bin 2048
    zip data_03.zip measurements.bin
    rm measurements.bin

    # 4. Corrupted zip (garbage data)
    echo "This is not a zip file" > data_04.zip

    # 5. Valid zip with 0 anomalies
    create_bin measurements.bin
    zip data_05.zip measurements.bin
    rm measurements.bin

    chown -R user:user /home/user/datasets
    chmod -R 777 /home/user

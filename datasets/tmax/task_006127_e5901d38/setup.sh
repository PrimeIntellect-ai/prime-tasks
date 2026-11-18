#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip coreutils tar gzip
    pip3 install pytest

    mkdir -p /home/user/raw_dataset/sensor_A/2023/
    mkdir -p /home/user/raw_dataset/sensor_B/logs/
    mkdir -p /home/user/raw_dataset/misc/

    generate_lines() {
        local valid_count=$1
        local corrupt_count=$2
        local ignore_count=$3
        local out_file=$4

        for i in $(seq 1 $valid_count); do
            echo "DATA: {\"id\": $RANDOM, \"value\": $RANDOM, \"status\": \"OK\"}" >> "$out_file"
        done
        for i in $(seq 1 $corrupt_count); do
            echo "DATA: {\"id\": $RANDOM, \"value\": $RANDOM, \"status\": \"CORRUPT\"}" >> "$out_file"
        done
        for i in $(seq 1 $ignore_count); do
            echo "INFO: Sensor heartbeat $RANDOM" >> "$out_file"
        done
    }

    generate_lines 400 50 100 /home/user/raw_dataset/sensor_A/2023/data1.txt
    generate_lines 300 20 50 /home/user/raw_dataset/sensor_B/logs/data2.dat
    generate_lines 550 100 200 /home/user/raw_dataset/misc/mixed.txt
    generate_lines 100 0 0 /home/user/raw_dataset/misc/ignore.csv

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user

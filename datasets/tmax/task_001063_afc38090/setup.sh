#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip espeak ffmpeg netcat wget curl socat
    pip3 install pytest

    # Create directories
    mkdir -p /app
    mkdir -p /home/user/cloud_data/project_a
    mkdir -p /home/user/cloud_data/project_b

    # Generate the audio file
    espeak -w /tmp/temp.wav "Alert. Cloud storage costs exceed budget. Please archive all data older than forty five days. Use the following authorization token for the reporting API: Bearer FinOpsSecure2024"
    ffmpeg -i /tmp/temp.wav /app/billing_voicemail.wav
    rm /tmp/temp.wav

    # Create cold files (older than 45 days)
    # Total size must be exactly 10240 bytes. We'll make 15 files of 682 bytes (10230) and 1 of 10 bytes.
    for i in $(seq 1 15); do
        dd if=/dev/zero of=/home/user/cloud_data/project_a/old_$i.dat bs=1 count=682
        touch -d "60 days ago" /home/user/cloud_data/project_a/old_$i.dat
    done
    dd if=/dev/zero of=/home/user/cloud_data/project_a/old_16.dat bs=1 count=10
    touch -d "60 days ago" /home/user/cloud_data/project_a/old_16.dat

    # Create new files (newer than 45 days)
    for i in $(seq 1 20); do
        dd if=/dev/zero of=/home/user/cloud_data/project_b/new_$i.dat bs=1 count=250
        touch -d "10 days ago" /home/user/cloud_data/project_b/new_$i.dat
    done

    # Create user
    useradd -m -s /bin/bash user || true

    # Permissions
    chmod -R 777 /home/user
    chmod 777 /app/billing_voicemail.wav

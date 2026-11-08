#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        e2fsprogs \
        fuse2fs \
        espeak \
        systemd \
        build-essential \
        cargo \
        rustc

    pip3 install pytest

    # Create directories
    mkdir -p /app/corpora/clean
    mkdir -p /app/corpora/evil

    # Generate sample audio alert
    espeak -w /app/alert_sample.wav "Warning. Database shard seven has reached maximum IOPS capacity."

    # Populate clean corpus
    echo "CPU utilization exceeded 90%" > /app/corpora/clean/alert1.txt
    echo "Disk space critical on volume X" > /app/corpora/clean/alert2.txt
    echo "Memory usage at 95 percent" > /app/corpora/clean/alert3.txt

    # Populate evil corpus
    echo "Test message ignore" > /app/corpora/evil/spam1.txt
    echo "Printer out of paper" > /app/corpora/evil/spam2.txt
    echo "Update available" > /app/corpora/evil/spam3.txt

    # Create user
    useradd -m -s /bin/bash user || true

    # Set permissions
    chmod -R 777 /app
    chmod -R 777 /home/user

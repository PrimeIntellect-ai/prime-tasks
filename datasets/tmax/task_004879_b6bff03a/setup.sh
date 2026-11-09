#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo rustc espeak-ng tar gzip curl
    pip3 install pytest

    # Create user
    useradd -m -s /bin/bash user || true

    # Generate audio directive
    mkdir -p /app/audio
    espeak-ng -w /app/audio/directive.wav "The authorization code is delta seven uniform nine"

    # Generate corpora
    mkdir -p /app/corpora/clean /app/corpora/evil
    for i in $(seq 1 50); do
        echo "{\"file_path\": \"/backup/data_$i.txt\", \"size_bytes\": 100}" > /app/corpora/clean/clean_$i.json
        echo "{\"file_path\": \"../../etc/shadow\", \"size_bytes\": -500}" > /app/corpora/evil/evil_$i.json
    done

    # Generate raw backups
    mkdir -p /app/raw_backups
    for i in $(seq 1 50); do
        num=$(printf "%02d" $i)
        touch /app/raw_backups/file_$num.bin
    done

    # Generate baseline snapshot
    mkdir -p /app/baseline/dummy_dir
    touch /app/baseline/dummy_dir/dummy
    tar -cg /app/baseline/baseline.snar -f /dev/null /app/baseline/dummy_dir

    # Create secure archive directory
    mkdir -p /home/user/secure_archive

    chmod -R 777 /home/user
    chmod -R 777 /app

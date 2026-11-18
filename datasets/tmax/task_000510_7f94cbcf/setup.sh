#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg sox libsndfile1
    pip3 install pytest librosa numpy soundfile

    mkdir -p /app/storage_pool
    mkdir -p /home/user

    # Generate a dummy audio file using sox
    sox -n -r 16000 -c 1 /app/voicemail.wav synth 60 sine 440

    # Create dummy text files and copy the audio file to simulate duplication
    for i in $(seq 1 500); do
        echo "Dummy content $i" > "/app/storage_pool/dummy_$i.txt"
    done

    mkdir -p /app/storage_pool/logs
    mkdir -p /app/storage_pool/audio
    for i in $(seq 1 20); do
        cp /app/voicemail.wav "/app/storage_pool/logs/call_$i.wav"
    done

    # Create user
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app

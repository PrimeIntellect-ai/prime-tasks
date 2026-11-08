#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg
    pip3 install pytest

    mkdir -p /app/corpus/clean
    mkdir -p /app/corpus/evil

    # Generate reference sample
    ffmpeg -f lavfi -i sine=frequency=1000:duration=1 -ar 16000 -ac 1 -c:a pcm_s16le /app/reference_sample.wav

    # Generate clean corpus
    for i in 1 2 3 4 5; do
        ffmpeg -f lavfi -i sine=frequency=$((1000 + i*100)):duration=1 -ar 16000 -ac 1 -c:a pcm_s16le /app/corpus/clean/clean${i}.wav
    done

    # Generate evil corpus
    # evil1.wav: text file
    echo "This is not a wav file, just some garbage text." > /app/corpus/evil/evil1.wav

    # evil2.wav: 44100 Hz
    ffmpeg -f lavfi -i sine=frequency=1000:duration=1 -ar 44100 -ac 1 -c:a pcm_s16le /app/corpus/evil/evil2.wav

    # evil3.wav: 2 channels
    ffmpeg -f lavfi -i sine=frequency=1000:duration=1 -ar 16000 -ac 2 -c:a pcm_s16le /app/corpus/evil/evil3.wav

    # evil4.wav: truncated wav
    ffmpeg -f lavfi -i sine=frequency=1000:duration=1 -ar 16000 -ac 1 -c:a pcm_s16le /app/corpus/evil/evil4_full.wav
    head -c 100 /app/corpus/evil/evil4_full.wav > /app/corpus/evil/evil4.wav
    rm /app/corpus/evil/evil4_full.wav

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user

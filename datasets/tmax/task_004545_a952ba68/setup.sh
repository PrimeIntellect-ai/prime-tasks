#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl wget tar zip unzip espeak cargo
    pip3 install pytest

    mkdir -p /app/tmp_build
    cd /app/tmp_build

    mkdir -p folder1 folder2
    for i in $(seq 1 30); do echo "data" > folder1/file_$i.txt; done
    for i in $(seq 31 54); do echo "data" > folder2/data_$i.dat; done

    for i in $(seq 1 6); do espeak -w folder1/audio_$i.wav "audio"; done
    for i in $(seq 7 12); do espeak -w folder2/sound_$i.WAV "sound"; done

    zip -r part1.zip folder1
    tar -cvf part2.tar folder2

    mkdir -p nested
    mv part1.zip part2.tar nested/
    tar -czvf /app/legacy_dump.tar.gz nested/

    cd /app
    rm -rf /app/tmp_build

    espeak -w /app/secret_voicemail.wav "storage vault alpha"

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app

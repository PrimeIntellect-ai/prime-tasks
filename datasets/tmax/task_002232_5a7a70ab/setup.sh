#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        gcc \
        time \
        bc \
        espeak \
        ffmpeg \
        libsndfile1 \
        swig \
        libpulse-dev

    pip3 install pytest SpeechRecognition pocketsphinx

    mkdir -p /app

    # Generate audio
    espeak -w /app/retry_audio.wav "Name: Francois, SSN: 111-22-3333, Amount: 450.75. Name: Taro, SSN: 444-55-6666, Amount: 1200.00"

    # Generate historical_transactions.csv
    python3 -c '
import random
with open("/app/historical_transactions_base.csv", "w", encoding="utf-8") as f:
    for i in range(200000):
        name = f"User{i}"
        if i % 10 == 0: name = "José"
        if i % 11 == 0: name = "Müller"
        if i % 12 == 0: name = "Wei"
        ssn = f"{100+i%800:03d}-{10+i%80:02d}-{1000+i%8000:04d}"
        amount = round(random.uniform(10.0, 1000.0), 2)
        f.write(f"{name}, {ssn}, {amount}\n")
'
    # Duplicate to create 1M lines (200k * 5)
    cat /app/historical_transactions_base.csv \
        /app/historical_transactions_base.csv \
        /app/historical_transactions_base.csv \
        /app/historical_transactions_base.csv \
        /app/historical_transactions_base.csv > /app/historical_transactions.csv
    rm /app/historical_transactions_base.csv

    # Create reference_serial.c
    cat << 'EOF' > /app/reference_serial.c
#include <stdio.h>
#include <unistd.h>

int main() {
    // Dummy serial implementation that takes some time
    sleep(2);
    return 0;
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app

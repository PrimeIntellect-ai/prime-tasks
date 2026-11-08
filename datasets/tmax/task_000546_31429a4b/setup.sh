#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user

    cat << 'EOF' > /home/user/setup_data.py
import csv
import random
from datetime import datetime, timedelta

random.seed(42)

languages = ['es-ES', 'fr-FR', 'de-DE', 'it-IT', 'ja-JP', 'zh-CN', 'invalid-lang', 'pt-BR']
start_time = datetime(2023, 10, 1, 0, 0, 0)

with open('/home/user/translation_telemetry.csv', 'w', newline='') as f:
    writer = csv.writer(f)
    writer.writerow(['timestamp', 'language_code', 'latency_ms', 'words_translated'])

    for i in range(50000):
        # Generate time within 24 hours
        dt = start_time + timedelta(minutes=random.randint(0, 1439))
        ts = dt.strftime("%Y-%m-%dT%H:%M:%SZ")

        lang = random.choice(languages)

        # Introduce some invalid data
        if random.random() < 0.05:
            latency = -10.0 # invalid
        else:
            latency = random.uniform(50.0, 500.0)

        if random.random() < 0.05:
            words = 0 # invalid
        else:
            words = random.randint(1, 100)

        writer.writerow([ts, lang, latency, words])
EOF

    python3 /home/user/setup_data.py
    chmod -R 777 /home/user

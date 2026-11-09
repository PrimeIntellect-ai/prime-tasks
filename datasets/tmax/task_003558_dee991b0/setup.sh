#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gcc
pip3 install pytest

useradd -m -s /bin/bash user || true
mkdir -p /home/user

cat << 'EOF' > /tmp/setup_data.py
import csv
import hashlib
import random
from datetime import datetime, timedelta

random.seed(42)

start_time = int(datetime(2023, 10, 1, 0, 0, 0).timestamp())
langs = ["es-ES", "fr-FR", "de-DE", "ja-JP"]

events = []
hashes = []

# Generate some unique strings
for i in range(1000):
    text = f"String number {i}"
    h = hashlib.md5(text.encode()).hexdigest()
    words = random.randint(1, 20)
    hashes.append((h, words))

with open("/home/user/loc_events.log", "w", newline="") as f:
    writer = csv.writer(f)
    current_time = start_time

    for _ in range(5000):
        # Time moves forward
        current_time += random.randint(10, 600)

        # Pick a hash (heavy bias towards earlier hashes to create duplicates)
        h, words = random.choice(hashes[:200] + hashes)
        lang = random.choice(langs)

        writer.writerow([current_time, h, lang, words])

EOF
python3 /tmp/setup_data.py
chmod 644 /home/user/loc_events.log

chmod -R 777 /home/user

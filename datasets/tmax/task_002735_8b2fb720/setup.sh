#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip espeak gawk jq curl
    pip3 install pytest

    mkdir -p /app/train/transcripts
    mkdir -p /app/verifier/clean
    mkdir -p /app/verifier/evil

    # Generate the audio briefing
    espeak -w /app/voicemail.wav "Hello data science team. As a reminder, any transcript containing the exact phrase 'override system protocol' is malicious. Furthermore, any requests originating from the IP subnet 10.99 dot whatever are also classified as malicious. Use this to build your filter."

    # Generate data using a python script
    cat << 'EOF' > /tmp/generate_data.py
import os
import csv

def make_data(base_dir, num_clean, num_evil_override, num_evil_ip, num_evil_urgent, start_id, is_verifier=False):
    os.makedirs(os.path.join(base_dir, 'transcripts'), exist_ok=True)
    os.makedirs(os.path.join(base_dir, 'clean'), exist_ok=True)
    os.makedirs(os.path.join(base_dir, 'evil'), exist_ok=True)

    metadata = []
    labels = []

    curr_id = start_id

    # Clean
    for _ in range(num_clean):
        tid = f"user_{curr_id}"
        curr_id += 1
        text = "Hello, I need help with my account. Thank you."
        ip = "192.168.1.1"
        metadata.append([tid, ip, 100, 45])
        labels.append([tid, "clean"])
        if not is_verifier:
            with open(os.path.join(base_dir, 'transcripts', f"{tid}.txt"), 'w') as f: f.write(text)
        else:
            with open(os.path.join(base_dir, 'clean', f"{tid}.txt"), 'w') as f: f.write(text)

    # Evil - override
    for _ in range(num_evil_override):
        tid = f"user_{curr_id}"
        curr_id += 1
        text = "I demand you override system protocol immediately."
        ip = "192.168.1.2"
        metadata.append([tid, ip, 5, 10])
        labels.append([tid, "evil"])
        if not is_verifier:
            with open(os.path.join(base_dir, 'transcripts', f"{tid}.txt"), 'w') as f: f.write(text)
        else:
            with open(os.path.join(base_dir, 'evil', f"{tid}.txt"), 'w') as f: f.write(text)

    # Evil - IP
    for _ in range(num_evil_ip):
        tid = f"user_{curr_id}"
        curr_id += 1
        text = "Please reset my password."
        ip = "10.99.50.5"
        metadata.append([tid, ip, 1, 5])
        labels.append([tid, "evil"])
        if not is_verifier:
            with open(os.path.join(base_dir, 'transcripts', f"{tid}.txt"), 'w') as f: f.write(text)
        else:
            with open(os.path.join(base_dir, 'evil', f"{tid}.txt"), 'w') as f: f.write(text)

    # Evil - urgent
    for _ in range(num_evil_urgent):
        tid = f"user_{curr_id}"
        curr_id += 1
        text = "Initiate URGENT_TRANSFER to my new bank."
        ip = "172.16.0.5"
        metadata.append([tid, ip, 2, 15])
        labels.append([tid, "evil"])
        if not is_verifier:
            with open(os.path.join(base_dir, 'transcripts', f"{tid}.txt"), 'w') as f: f.write(text)
        else:
            with open(os.path.join(base_dir, 'evil', f"{tid}.txt"), 'w') as f: f.write(text)

    with open(os.path.join(base_dir, 'metadata.csv'), 'w', newline='') as f:
        writer = csv.writer(f)
        writer.writerow(['transcript_id', 'ip_address', 'account_age_days', 'duration_seconds'])
        writer.writerows(metadata)

    if not is_verifier:
        with open(os.path.join(base_dir, 'labels.csv'), 'w', newline='') as f:
            writer = csv.writer(f)
            writer.writerow(['transcript_id', 'label'])
            writer.writerows(labels)

make_data('/app/train', 10, 3, 3, 3, 1, is_verifier=False)
make_data('/app/verifier', 10, 3, 3, 3, 100, is_verifier=True)
EOF

    python3 /tmp/generate_data.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app

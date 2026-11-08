#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make sqlite3
    pip3 install pytest

    mkdir -p /app
    mkdir -p /home/user/src

    cat << 'EOF' > /app/generate_data.py
import math
import wave
import struct
import csv
import uuid
import random

random.seed(42)

sample_rate = 16000
duration = 60
num_samples = sample_rate * duration

audio = [int(random.gauss(0, 500)) for _ in range(num_samples)]

events = []
true_ids = []

for i in range(50):
    start_time = random.uniform(0.5, duration - 1.0)
    beep_duration = random.uniform(0.1, 0.4)

    start_idx = int(start_time * sample_rate)
    end_idx = int((start_time + beep_duration) * sample_rate)

    for j in range(start_idx, end_idx):
        t = j / sample_rate
        audio[j] += int(10000 * math.sin(2 * math.pi * 1000 * t))

    event_id = str(uuid.uuid4())
    true_ids.append(event_id)
    events.append({
        'event_id': event_id,
        'timestamp_ms': int(start_time * 1000),
        'duration_ms': int(beep_duration * 1000),
        'confidence_score': round(random.uniform(0.85, 0.99), 3)
    })

for i in range(num_samples):
    if audio[i] > 32767: audio[i] = 32767
    elif audio[i] < -32768: audio[i] = -32768

with wave.open('/app/machine_audio.wav', 'w') as f:
    f.setnchannels(1)
    f.setsampwidth(2)
    f.setframerate(sample_rate)
    data = struct.pack('<' + 'h'*num_samples, *audio)
    f.writeframes(data)

all_events = list(events)
for i in range(40):
    base_event = random.choice(events)
    dup_id = str(uuid.uuid4())
    shift = random.randint(-100, 100)
    all_events.append({
        'event_id': dup_id,
        'timestamp_ms': base_event['timestamp_ms'] + shift,
        'duration_ms': base_event['duration_ms'] + random.randint(-10, 10),
        'confidence_score': round(base_event['confidence_score'] - random.uniform(0.01, 0.1), 3)
    })

random.shuffle(all_events)

with open('/app/noisy_events.csv', 'w', newline='') as f:
    writer = csv.DictWriter(f, fieldnames=['event_id', 'timestamp_ms', 'duration_ms', 'confidence_score'])
    writer.writeheader()
    writer.writerows(all_events)

with open('/app/ground_truth_ids.txt', 'w') as f:
    for tid in true_ids:
        f.write(tid + '\n')
EOF

    python3 /app/generate_data.py

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
    chmod -R 777 /app

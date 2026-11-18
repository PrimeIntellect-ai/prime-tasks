#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg espeak bc gawk
    pip3 install pytest

    mkdir -p /app/corpus/clean /app/corpus/evil

    # Generate the audio file
    espeak -w /app/manager_notes.wav "Attention team. We have identified the leaked test phrase. Please purge all records containing the codename OMEGA-77-ECHO immediately."

    # Generate data using Python
    python3 -c "
import os
import random

train_ids = [f'TRN_{i:04d}' for i in range(100)]
with open('/app/train_master_ids.txt', 'w') as f:
    f.write('\n'.join(train_ids) + '\n')

counts = [int(random.gauss(50, 4)) for _ in range(100)]
with open('/app/baseline_line_counts.txt', 'w') as f:
    f.write('\n'.join(map(str, counts)) + '\n')

for i in range(50):
    num_lines = random.randint(45, 55)
    lines = [f'DOC_ID: CLN_{i:04d}'] + [f'Line {j}' for j in range(1, num_lines)]
    with open(f'/app/corpus/clean/file_{i:03d}.txt', 'w') as f:
        f.write('\n'.join(lines) + '\n')

for i in range(15):
    num_lines = random.randint(45, 55)
    lines = [f'DOC_ID: EVL_A_{i:04d}'] + [f'Line {j}' for j in range(1, num_lines)]
    lines[num_lines // 2] = 'Something OMEGA-77-ECHO something'
    with open(f'/app/corpus/evil/file_omega_{i:03d}.txt', 'w') as f:
        f.write('\n'.join(lines) + '\n')

for i in range(15):
    num_lines = random.randint(45, 55)
    lines = [f'DOC_ID: {train_ids[i]}'] + [f'Line {j}' for j in range(1, num_lines)]
    with open(f'/app/corpus/evil/file_leak_{i:03d}.txt', 'w') as f:
        f.write('\n'.join(lines) + '\n')

for i in range(20):
    num_lines = 10 if i < 10 else 150
    lines = [f'DOC_ID: EVL_C_{i:04d}'] + [f'Line {j}' for j in range(1, num_lines)]
    with open(f'/app/corpus/evil/file_len_{i:03d}.txt', 'w') as f:
        f.write('\n'.join(lines) + '\n')
"

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app

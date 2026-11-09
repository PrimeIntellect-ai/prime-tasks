#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip make ffmpeg jq
    pip3 install pytest

    mkdir -p /app/raw_logs
    mkdir -p /app/corpora/clean
    mkdir -p /app/corpora/evil

    python3 -c "
import os, json, subprocess

# Generate video frames
frames = [1, 0, 1, 1, 0, 1, 1, 0, 1, 0, 1, 1]
os.makedirs('/tmp/frames', exist_ok=True)
for i, f in enumerate(frames):
    with open(f'/tmp/frames/img_{i:02d}.ppm', 'w') as out:
        if f == 1:
            out.write('P3\n10 10\n255\n' + ('255 255 255\n' * 100))
        else:
            out.write('P3\n10 10\n255\n' + ('0 0 0\n' * 100))

subprocess.run(['ffmpeg', '-y', '-framerate', '1', '-i', '/tmp/frames/img_%02d.ppm', '-c:v', 'libx264', '-r', '1', '-pix_fmt', 'yuv420p', '/app/transmission.mp4'], check=True)

# Generate user data
with open('/app/user_data.csv', 'w') as f:
    f.write('id,user_name,department\n')
    for i in range(1, 101):
        f.write(f'{i},User{i},Dept{i%3}\n')

# Generate clean corpus
for i in range(1, 51):
    with open(f'/app/corpora/clean/log_{i}.json', 'w') as f:
        json.dump({'id': str(i), 'metric_formula': f'{i} + {i}'}, f)

# Generate evil corpus
for i in range(1, 51):
    with open(f'/app/corpora/evil/log_{i}.json', 'w') as f:
        json.dump({'id': str(i+50), 'metric_formula': '__import__(\\'os\\')'}, f)

# Generate raw logs
for i in range(1, 5):
    with open(f'/app/raw_logs/log_{i}.json', 'w') as f:
        json.dump({'id': str(i), 'metric_formula': f'{i} + {i}'}, f)
with open('/app/raw_logs/log_evil.json', 'w') as f:
    json.dump({'id': '99', 'metric_formula': 'eval(\\'1\\')'}, f)
"

    rm -rf /tmp/frames

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app

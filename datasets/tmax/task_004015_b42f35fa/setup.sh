#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg imagemagick coreutils
    pip3 install pytest

    # Create directories
    mkdir -p /app/corpus/clean /app/corpus/evil

    # Generate dummy video
    ffmpeg -f lavfi -i testsrc=duration=5:size=1280x720:rate=10 -c:v libx264 /app/video.mp4

    # Generate CSV files
    python3 -c "
import os, random
random.seed(42)
os.makedirs('/app/corpus/clean', exist_ok=True)
os.makedirs('/app/corpus/evil', exist_ok=True)

def gen_row():
    return ','.join(str(random.random()) for _ in range(5))

for i in range(5):
    # Clean dataset
    clean = [gen_row() for _ in range(100)]
    with open(f'/app/corpus/clean/data_{i}.csv', 'w') as f:
        f.write('\n'.join(clean) + '\n')

    # Evil dataset
    evil = [gen_row() for _ in range(100)]
    for j in range(6):
        evil[60+j] = evil[10+j]
    with open(f'/app/corpus/evil/data_{i}.csv', 'w') as f:
        f.write('\n'.join(evil) + '\n')
"

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user

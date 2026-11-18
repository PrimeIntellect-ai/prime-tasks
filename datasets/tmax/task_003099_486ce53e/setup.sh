#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg gcc zlib1g-dev
    pip3 install pytest

    mkdir -p /app/corpus/clean
    mkdir -p /app/corpus/evil
    mkdir -p /home/user/frames

    # Generate a 15-second video
    ffmpeg -f lavfi -i testsrc=duration=15:size=640x360:rate=30 -c:v libx264 /app/surveillance.mp4

    # Generate log files using Python
    python3 -c '
import gzip
import os

clean_record = "BEGIN_RECORD\nUser login successful\nTimestamp: 123456\nEND_RECORD\n"
evil_record_1 = "BEGIN_RECORD\nAccessing ../../../etc/passwd\nEND_RECORD\n"
evil_record_2 = "BEGIN_RECORD\nMALICIOUS activity detected\nEND_RECORD\n"

for i in range(5):
    with gzip.open(f"/app/corpus/clean/clean_{i}.log.gz", "wt") as f:
        f.write(clean_record * 3)

for i in range(5):
    with gzip.open(f"/app/corpus/evil/evil_{i}.log.gz", "wt") as f:
        f.write(clean_record)
        if i % 2 == 0:
            f.write(evil_record_1)
        else:
            f.write(evil_record_2)
        f.write(clean_record)
'

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app

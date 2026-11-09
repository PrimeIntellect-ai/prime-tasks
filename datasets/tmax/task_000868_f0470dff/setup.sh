#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg cargo rustc cron
    pip3 install pytest

    mkdir -p /app/corpora/clean /app/corpora/evil /var/data

    # Generate reference video with exactly 120 frames (4 seconds at 30 fps)
    ffmpeg -f lavfi -i color=c=black:s=320x240:d=4 -r 30 -c:v libx264 /app/reference.mp4

    # Generate corpora
    python3 -c "
import csv, os
with open('/app/corpora/clean/clean1.csv', 'w', newline='') as f:
    writer = csv.writer(f)
    writer.writerow(['id', 'timestamp', 'user_agent', 'description'])
    writer.writerow(['1', '123', 'ua', 'this is a normal description'])
    writer.writerow(['2', '124', 'ua', 'another normal one'])

with open('/app/corpora/evil/evil1.csv', 'w', newline='') as f:
    writer = csv.writer(f)
    writer.writerow(['id', 'timestamp', 'user_agent', 'description'])
    writer.writerow(['3', '125', 'ua', 'eval something'])
    writer.writerow(['4', '126', 'ua', 'script tag here'])
    writer.writerow(['5', '127', 'ua', 'word ' * 125])
"

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /var/data
    chmod -R 777 /app

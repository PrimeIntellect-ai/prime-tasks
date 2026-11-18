#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg socat netcat-openbsd
    pip3 install pytest

    mkdir -p /app/corpus/clean /app/corpus/evil

    # Generate a dummy 15-second mp4 file for the fixture
    ffmpeg -f lavfi -i testsrc=duration=15:size=640x480:rate=30 -c:v libx264 /app/camera1.mp4

    # Populate clean corpus
    echo '{"action": "capture", "device_id": "cam1", "tz": "America/New_York"}' > /app/corpus/clean/c1.json
    echo '{"action": "capture", "device_id": "hallway2", "tz": "UTC"}' > /app/corpus/clean/c2.json

    # Populate evil corpus
    echo '{"action": "capture", "device_id": "cam1; cat /etc/passwd", "tz": "America/New_York"}' > /app/corpus/evil/e1.json
    echo '{"action": "capture", "device_id": "cam1", "tz": "../../../etc/shadow"}' > /app/corpus/evil/e2.json
    echo '{"action": "delete", "device_id": "cam1", "tz": "UTC"}' > /app/corpus/evil/e3.json

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app

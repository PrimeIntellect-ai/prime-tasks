#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg
    pip3 install pytest

    mkdir -p /app/corpora/clean /app/corpora/evil

    # Generate a dummy video with exactly 120 frames
    ffmpeg -f lavfi -i testsrc=duration=5:size=320x240:rate=24 -pix_fmt yuv420p /app/calibration.mp4

    # Populate clean corpus
    echo "/api/v1/route/calculate?x=30&y=10" > /app/corpora/clean/req1.txt
    echo "/api/v1/route/update?x=100&y=20" > /app/corpora/clean/req2.txt
    echo "/api/v1/route/calculate?x=5&y=15" > /app/corpora/clean/req3.txt

    # Populate evil corpus
    echo "/api/v1/route/calculate?x=10&y=15" > /app/corpora/evil/req1.txt
    echo "/api/v1/route/calculate?x=-10&y=30" > /app/corpora/evil/req2.txt
    echo "/api/v1/route/update?x=10&y=10&z=5" > /app/corpora/evil/req3.txt
    echo "/api/v1/route/delete?x=10&y=10" > /app/corpora/evil/req4.txt
    echo "/api/v1/route/calculate?x=10;ls&y=10" > /app/corpora/evil/req5.txt
    echo "/api/v1/route/calculate?x=10.5&y=9.5" > /app/corpora/evil/req6.txt

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user

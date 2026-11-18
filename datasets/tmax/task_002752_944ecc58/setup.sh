#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg
    pip3 install pytest

    mkdir -p /app/corpus/clean /app/corpus/evil

    # Generate test video with exactly 450 frames
    ffmpeg -f lavfi -i testsrc=duration=15:size=640x480:rate=30 -c:v libx264 /app/test_video.mp4

    # Create corpus files
    echo '{"frame": 10, "callback": "https://a.com/b?c=d-e_f"}' > /app/corpus/clean/1.json
    echo '{"frame": 450, "callback": "https://a.com/b"}' > /app/corpus/clean/2.json

    echo '{"frame": 10, "callback": "http://a.com/b; rm -rf /"}' > /app/corpus/evil/1.json
    echo '{"frame": 451, "callback": "https://a.com/"}' > /app/corpus/evil/2.json
    echo '{"frame": 10, "callback": "http://a.com/b`whoami`"}' > /app/corpus/evil/3.json
    echo '{"frame": 10, "callback": "http://a.com/b|ls"}' > /app/corpus/evil/4.json
    echo '{"frame": 10, "callback": "http://a.com/b&ls"}' > /app/corpus/evil/5.json

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/logs
    mkdir -p /home/user/deployment
    touch /home/user/logs/access.log

    chown -R user:user /home/user
    chmod -R 777 /home/user
    chmod -R 777 /app

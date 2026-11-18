#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg nginx
    pip3 install pytest opencv-python-headless Pillow

    # Create directories
    mkdir -p /app/corpus/clean
    mkdir -p /app/corpus/evil

    # Generate clean videos
    for i in $(seq 1 5); do
        ffmpeg -y -f lavfi -i testsrc=duration=2:size=320x240:rate=30 -c:v libx264rgb -crf 0 -pix_fmt rgb24 /app/corpus/clean/clean_${i}.mp4
    done

    # Generate evil videos
    for i in $(seq 1 5); do
        ffmpeg -y -f lavfi -i testsrc=duration=2:size=320x240:rate=30 -vf "drawbox=x=0:y=0:w=10:h=10:color=red@1.0:t=fill" -c:v libx264rgb -crf 0 -pix_fmt rgb24 /app/corpus/evil/evil_${i}.mp4
    done

    # Generate incident record (300 frames = 10 seconds at 30 fps)
    # The red square appears starting at frame 142
    ffmpeg -y -f lavfi -i testsrc=duration=10:size=320x240:rate=30 -vf "drawbox=x=0:y=0:w=10:h=10:color=red@1.0:t=fill:enable='gte(n,142)'" -c:v libx264rgb -crf 0 -pix_fmt rgb24 /app/incident_record.mp4

    # Create user
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app

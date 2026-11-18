#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg imagemagick
    pip3 install pytest

    mkdir -p /app/training_data/clean_corpus
    mkdir -p /app/training_data/evil_corpus
    mkdir -p /app/test_data/clean_corpus
    mkdir -p /app/test_data/evil_corpus

    # Generate clean corpus (e.g., solid gray, brightness ~150)
    for i in $(seq 1 5); do
        convert -size 64x64 xc:"gray(150)" /app/training_data/clean_corpus/clean_${i}.jpg
        convert -size 64x64 xc:"gray(150)" /app/test_data/clean_corpus/clean_${i}.jpg
    done

    # Generate evil corpus (e.g., solid black, brightness 0 or random noise)
    for i in $(seq 1 5); do
        convert -size 64x64 xc:black /app/training_data/evil_corpus/evil_${i}.jpg
        convert -size 64x64 xc:black /app/test_data/evil_corpus/evil_${i}.jpg
    done

    # Generate video frames
    mkdir -p /tmp/vid_frames
    for i in $(seq 1 15); do
        fname=$(printf "/tmp/vid_frames/frame_%04d.jpg" $i)
        if [ $i -eq 4 ] || [ $i -eq 9 ] || [ $i -eq 12 ]; then
            # Glitch
            convert -size 320x240 xc:black $fname
        elif [ $i -eq 7 ] || [ $i -eq 8 ]; then
            # Valid, but brightness < 100
            convert -size 320x240 xc:"gray(50)" $fname
        else
            # Valid, brightness >= 100
            convert -size 320x240 xc:"gray(150)" $fname
        fi
    done

    # Create video at 1 fps
    ffmpeg -framerate 1 -i /tmp/vid_frames/frame_%04d.jpg -c:v libx264 -pix_fmt yuv420p /app/factory_feed.mp4
    rm -rf /tmp/vid_frames

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app

#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg zip fonts-dejavu-core
    pip3 install pytest

    mkdir -p /app/corpora/clean
    mkdir -p /app/corpora/evil

    # Generate video
    ffmpeg -f lavfi -i color=c=black:s=320x240:d=6 \
      -vf "drawtext=fontfile=/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf:text='CRITICAL FAILURE\: ERR9X':fontcolor=white:fontsize=24:x=(w-text_w)/2:y=(h-text_h)/2:enable='between(t,2,5)'" \
      -c:v libx264 -y /app/system_incident.mp4

    # Clean corpus
    cd /app/corpora/clean
    echo "Valid content" > valid_file.txt
    zip valid_archive.zip valid_file.txt
    ln -s valid_file.txt safe_link
    echo "Normal log entry 1" > app.log
    echo "Normal log entry 2" >> app.log

    # Evil corpus
    cd /app/corpora/evil
    echo "This is not a zip file" > corrupt_archive.zip
    mkdir loop_dir
    cd loop_dir
    ln -s . infinite
    cd ..
    echo "Error occurred: ERR9X in module A" > error.log
    echo "Another ERR9X found" >> error.log

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app

#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3 libsqlite3-dev ffmpeg g++
    pip3 install pytest

    mkdir -p /app
    sqlite3 /app/reference.db <<EOF
CREATE TABLE signal_types (
    id INTEGER PRIMARY KEY,
    min_val REAL,
    max_val REAL,
    signal_name TEXT
);
INSERT INTO signal_types (min_val, max_val, signal_name) VALUES
(0.0, 50.0, 'background'),
(50.01, 150.0, 'low_activity'),
(150.01, 255.0, 'high_activity');
EOF

    mkdir -p /tmp/gen_frames
    for i in {1..10}; do
        if [ $i -eq 2 ]; then
            color="0x646464" # approx 100/255
        elif [ $i -eq 3 ]; then
            color="0xc8c8c8" # approx 200/255
        else
            color="0x0a0a0a"  # approx 10/255
        fi
        ffmpeg -y -f lavfi -i color=c=${color}:s=100x100 -frames:v 1 /tmp/gen_frames/frame_$(printf "%04d" $i).png
    done

    ffmpeg -y -framerate 1 -pattern_type glob -i '/tmp/gen_frames/*.png' -c:v libx264 -pix_fmt yuv420p /app/signal.mp4
    rm -rf /tmp/gen_frames

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user

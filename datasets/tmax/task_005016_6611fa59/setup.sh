#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg g++ cmake make curl wget
    pip3 install pytest

    # Create user
    useradd -m -s /bin/bash user || true

    # Create CSV file
    cat << 'EOF' > /home/user/baseline_config.csv
timestamp_sec,config_id
0,cfg_init
2,cfg_update_1
6,cfg_update_2
9,cfg_final
EOF

    # Create video fixture
    mkdir -p /app
    cd /app
    ffmpeg -y -f lavfi -i color=c=black:s=320x240:r=10:d=10 -pix_fmt yuv420p base.mp4
    ffmpeg -y -f lavfi -i color=c=white:s=320x240:r=10:d=0.1 -pix_fmt yuv420p flash.mp4

    cat << 'EOF' > concat.txt
file 'base.mp4'
inpoint 0.0
outpoint 2.3
file 'flash.mp4'
file 'base.mp4'
inpoint 2.4
outpoint 5.7
file 'flash.mp4'
file 'base.mp4'
inpoint 5.8
outpoint 8.1
file 'flash.mp4'
file 'base.mp4'
inpoint 8.2
outpoint 10.0
EOF

    ffmpeg -y -f concat -safe 0 -i concat.txt -c copy rack_monitor.mp4
    rm base.mp4 flash.mp4 concat.txt

    # Set permissions
    chmod -R 777 /home/user
    chmod -R 777 /app

#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg
    pip3 install pytest

    mkdir -p /app/corpora/clean /app/corpora/evil

    cat << 'EOF' > /app/corpora/clean/clean_1.manifest
[RECORD]
ID: 1
File-Path: test.txt
Size: 100
[END]
EOF

    cat << 'EOF' > /app/corpora/clean/clean_2.manifest
[RECORD]
ID: 2
File-Path: dir/../dir/file
Size: 200
[END]
EOF

    cat << 'EOF' > /app/corpora/evil/evil_1.manifest
[RECORD]
ID: 3
File-Path: ../../../etc/shadow
Size: 300
[END]
EOF

    cat << 'EOF' > /app/corpora/evil/evil_2.manifest
[RECORD]
ID: 4
File-Path: /var/log/syslog
Size: 400
[END]
EOF

    cat << 'EOF' > /app/corpora/evil/evil_3.manifest
[RECORD]
ID: 5
File-Path: a/../../b
Size: 500
[END]
EOF

    # Generate video with 125 black frames (5s @ 25fps) and 34 red frames (1.36s @ 25fps)
    ffmpeg -y -f lavfi -i color=c=black:s=320x240:r=25:d=5 \
           -f lavfi -i color=c=red:s=320x240:r=25:d=1.36 \
           -filter_complex "[0:v][1:v]concat=n=2:v=1:a=0[outv]" \
           -map "[outv]" -c:v libx264 -pix_fmt yuv420p /app/backup_cam.mp4

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app

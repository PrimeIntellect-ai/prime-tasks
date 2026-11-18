#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        ffmpeg \
        tesseract-ocr \
        libtesseract-dev \
        g++ \
        fonts-dejavu-core

    pip3 install pytest

    # Create corpora directories
    mkdir -p /app/corpora/clean /app/corpora/evil

    # Generate clean queries
    cat << 'EOF' > /app/corpora/clean/1.txt
MATCH (n:Backup) RETURN n LIMIT 10
EOF

    cat << 'EOF' > /app/corpora/clean/2.txt
SELECT * WHERE { ?s ?p ?o } LIMIT 100
EOF

    # Generate evil queries
    cat << 'EOF' > /app/corpora/evil/1.txt
MATCH (n:Secret) RETURN n LIMIT 1
EOF

    cat << 'EOF' > /app/corpora/evil/2.txt
MATCH (n:Backup) DELETE n
EOF

    cat << 'EOF' > /app/corpora/evil/3.txt
MATCH (n:Backup) RETURN n
EOF

    # Generate video with exactly 14 frames of "FAIL"
    ffmpeg -f lavfi -i color=c=black:s=640x480:d=14:r=1 -vf "drawtext=fontfile=/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf:text='FAIL':fontcolor=white:fontsize=72:x=(w-text_w)/2:y=(h-text_h)/2" -c:v libx264 -pix_fmt yuv420p /tmp/fail.mp4
    ffmpeg -f lavfi -i color=c=black:s=640x480:d=6:r=1 -vf "drawtext=fontfile=/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf:text='OK':fontcolor=white:fontsize=72:x=(w-text_w)/2:y=(h-text_h)/2" -c:v libx264 -pix_fmt yuv420p /tmp/ok.mp4

    cat << 'EOF' > /tmp/inputs.txt
file '/tmp/fail.mp4'
file '/tmp/ok.mp4'
EOF

    ffmpeg -f concat -safe 0 -i /tmp/inputs.txt -c copy /app/backup_monitor.mp4
    rm -f /tmp/fail.mp4 /tmp/ok.mp4 /tmp/inputs.txt

    # Setup user
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user

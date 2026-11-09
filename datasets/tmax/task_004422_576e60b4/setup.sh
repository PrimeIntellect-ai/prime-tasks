#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg fonts-dejavu-core
    pip3 install pytest

    mkdir -p /app
    mkdir -p /home/user

    # Create the suspicious daemon
    echo -n "ELF... C2_PORT=31337" > /home/user/suspicious_daemon

    # Calculate the hash
    ACTUAL_HASH=$(sha256sum /home/user/suspicious_daemon | awk '{print $1}')

    # Create text files for ffmpeg to avoid escaping issues
    echo "Payload hash: ${ACTUAL_HASH}" > /tmp/text1.txt
    echo "CSP_PAYLOAD: default-src 'none'; script-src http://evil.com;" > /tmp/text2.txt

    # Generate the video
    ffmpeg -f lavfi -i color=c=black:s=800x600:d=30 -r 1 -vf \
    "drawtext=fontfile=/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf:textfile=/tmp/text1.txt:fontcolor=white:fontsize=18:x=10:y=10:enable='between(t,14,15)', \
     drawtext=fontfile=/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf:textfile=/tmp/text2.txt:fontcolor=white:fontsize=18:x=10:y=50:enable='between(t,21,22)'" \
    -c:v libx264 -pix_fmt yuv420p /app/evidence_041.mp4

    # Clean up temp files
    rm /tmp/text1.txt /tmp/text2.txt

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app

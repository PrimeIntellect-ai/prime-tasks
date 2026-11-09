#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg tesseract-ocr fonts-dejavu-core
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user
    mkdir -p /app

    cat << 'EOF' > /home/user/auth.log
Jan 14 10:00:01 server sshd[1024]: Failed password for root from 192.168.1.50 port 33412 ssh2
Jan 14 10:00:05 server sshd[1025]: Failed password for admin from 10.0.0.5 port 44212 ssh2
Jan 14 10:01:23 server sshd[1029]: Accepted password for admin from 172.16.4.88 port 55122 ssh2
Jan 14 10:02:00 server sshd[1030]: Disconnected from user admin 172.16.4.88 port 55122
EOF

    ffmpeg -f lavfi -i color=c=black:s=640x480:d=5 \
      -vf "drawtext=fontfile=/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf:fontsize=30:fontcolor=white:x=(w-text_w)/2:y=(h-text_h)/2:text='B@ckD00r_77Xq':enable='between(t,3,4)'" \
      -c:v libx264 -pix_fmt yuv420p /app/attacker_screencast.mp4

    chmod 644 /app/attacker_screencast.mp4

    chmod -R 777 /home/user

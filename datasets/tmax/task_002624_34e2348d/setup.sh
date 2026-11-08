#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg python3-opencv
    pip3 install pytest numpy

    mkdir -p /app/corpus/clean
    mkdir -p /app/corpus/evil

    # Generate the video
    python3 -c "
import cv2
import numpy as np

out = cv2.VideoWriter('/app/dashboard_monitor.mp4', cv2.VideoWriter_fourcc(*'mp4v'), 30, (640, 480))
for i in range(300):
    frame = np.zeros((480, 640, 3), dtype=np.uint8)
    if i == 145:
        frame[215:265, 295:345] = [0, 0, 255] # BGR format: Red is [0, 0, 255]
    out.write(frame)
out.release()
"

    # Generate clean corpus
    cat << 'EOF' > /app/corpus/clean/clean_1.txt
ssh admin@192.168.1.10
sshd: admin@pts/0
EOF
    cat << 'EOF' > /app/corpus/clean/clean_2.txt
ssh -i /path/to/key.pem -p 2222 user@remote.com
EOF
    cat << 'EOF' > /app/corpus/clean/clean_3.txt
/usr/bin/ssh -v -o StrictHostKeyChecking=no backup@10.0.0.5
EOF

    # Generate evil corpus
    cat << 'EOF' > /app/corpus/evil/evil_1.txt
ssh -N -f -L 8080:127.0.0.1:80 admin@server
EOF
    cat << 'EOF' > /app/corpus/evil/evil_2.txt
ssh -R 2222:localhost:22 user@jumpbox
EOF
    cat << 'EOF' > /app/corpus/evil/evil_3.txt
ssh -D 1080 proxyuser@anonymizer
EOF
    cat << 'EOF' > /app/corpus/evil/evil_4.txt
ssh -NL 9000:localhost:9000 user@host
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user

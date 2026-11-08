#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip ffmpeg libglib2.0-0
pip3 install pytest opencv-python-headless pytz

mkdir -p /app/corpus/clean /app/corpus/evil /app/hidden_corpus/clean /app/hidden_corpus/evil

cat << 'EOF' > /app/corpus/clean/clean1
Port 22
PubkeyAuthentication yes
AuthorizedKeysFile .ssh/authorized_keys
EOF

cat << 'EOF' > /app/corpus/clean/clean2
Port 22
PasswordAuthentication no
EOF

cat << 'EOF' > /app/corpus/clean/clean3
Port 22
AuthenticationMethods publickey
EOF

cat << 'EOF' > /app/corpus/clean/clean4
Port 2222
EOF

cat << 'EOF' > /app/corpus/clean/clean5
# Just a comment
EOF

cat << 'EOF' > /app/corpus/evil/evil1
AuthorizedKeysFile /dev/null
EOF

cat << 'EOF' > /app/corpus/evil/evil2
PubkeyAcceptedKeyTypes none
EOF

cat << 'EOF' > /app/corpus/evil/evil3
AuthenticationMethods password
EOF

cat << 'EOF' > /app/corpus/evil/evil4
Match User *
    AuthorizedKeysFile /var/empty/%u
EOF

cat << 'EOF' > /app/corpus/evil/evil5
PubkeyAuthentication no
EOF

cp -r /app/corpus/clean/* /app/hidden_corpus/clean/
cp -r /app/corpus/evil/* /app/hidden_corpus/evil/

cat << 'EOF' > /tmp/gen_vid.py
import cv2
import numpy as np

out = cv2.VideoWriter('/app/monitor_feed.mp4', cv2.VideoWriter_fourcc(*'mp4v'), 30, (100, 100))
for i in range(300):
    frame = np.zeros((100, 100, 3), dtype=np.uint8)
    if (45 <= i <= 75) or (150 <= i <= 180):
        frame[10, 10] = [0, 0, 255] # BGR format in OpenCV
    out.write(frame)
out.release()
EOF

python3 /tmp/gen_vid.py
rm /tmp/gen_vid.py

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
chmod -R 777 /app

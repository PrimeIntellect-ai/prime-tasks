#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip ffmpeg g++ tar gzip coreutils
pip3 install pytest numpy opencv-python-headless

mkdir -p /home/user/backups/monthly /home/user/backup_logs /app

# Create valid archives
for i in 1 2 3; do
  mkdir -p /tmp/b$i
  echo "data" > /tmp/b$i/file.txt
  tar -czf /home/user/backups/monthly/backup_valid_$i.tar.gz -C /tmp b$i
done

# Create corrupted archive
mkdir -p /tmp/b_corr
echo "data" > /tmp/b_corr/file.txt
tar -czf /home/user/backups/archive_corrupted.tar.gz -C /tmp b_corr
# Corrupt it by overwriting the middle
dd if=/dev/urandom of=/home/user/backups/archive_corrupted.tar.gz bs=1 count=100 seek=50 conv=notrunc

# Create log files
cat << 'EOF' > /home/user/backup_logs/log1.txt
[START_BACKUP]
ID: BKP-991
TIMESTAMP: 1670000000
STATUS: FAILED
[END_BACKUP]
[START_BACKUP]
ID: BKP-992
TIMESTAMP: 1670000100
STATUS: SUCCESS
[END_BACKUP]
EOF

cat << 'EOF' > /home/user/backup_logs/log2.txt
[START_BACKUP]
ID: BKP-993
TIMESTAMP: 1670000200
STATUS: SUCCESS
[END_BACKUP]
EOF

# Generate video artifact
cat << 'EOF' > /tmp/gen_video.py
import cv2
import numpy as np

# Sequence for "s3cr3tKEY"
bits = "011100110011001101100011011100100011001101110100010010110100010101011001"
fps = 10
width, height = 100, 100

fourcc = cv2.VideoWriter_fourcc(*'mp4v')
out = cv2.VideoWriter('/app/backup_audit.mp4', fourcc, fps, (width, height))

for b in bits:
    color = 255 if b == '1' else 0
    frame = np.full((height, width, 3), color, dtype=np.uint8)
    out.write(frame)

out.release()
EOF
python3 /tmp/gen_video.py

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user /app

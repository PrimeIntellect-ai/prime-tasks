#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip e2fsprogs ffmpeg nginx
pip3 install pytest opencv-python-headless numpy

mkdir -p /app

# Create the ext4 image using mke2fs -d to avoid mount/loop issues
mkdir -p /tmp/router_fs_dir/etc
echo -e "127.0.0.1:9001\n127.0.0.1:9002\n127.0.0.1:9003" > /tmp/router_fs_dir/etc/backend_ips.conf
dd if=/dev/zero of=/app/router_fs.ext4 bs=1M count=10
mkfs.ext4 -d /tmp/router_fs_dir /app/router_fs.ext4
chmod 644 /app/router_fs.ext4

# Generate the video fixture
cat << 'EOF' > /tmp/gen_video.py
import cv2
import numpy as np

# 30fps, 10 seconds = 300 frames
out = cv2.VideoWriter('/app/vnc_capture.mp4', cv2.VideoWriter_fourcc(*'mp4v'), 30, (640, 480))
down_frames = set(list(range(45, 86)) + list(range(160, 211)) + list(range(260, 281)))

for i in range(300):
    frame = np.zeros((480, 640, 3), dtype=np.uint8)
    if i in down_frames:
        frame[0:50, 0:50] = (0, 0, 255) # BGR for Red
    else:
        frame[0:50, 0:50] = (0, 255, 0) # BGR for Green
    out.write(frame)

out.release()
EOF

python3 /tmp/gen_video.py
rm /tmp/gen_video.py
rm -rf /tmp/router_fs_dir

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user

#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg
    pip3 install pytest numpy opencv-python-headless

    mkdir -p /app

    # Generate the video
    cat << 'EOF' > /tmp/gen_video.py
import cv2
import numpy as np

out = cv2.VideoWriter('/app/config_dashboard_feed.mp4', cv2.VideoWriter_fourcc(*'mp4v'), 30, (640, 480))
red_frames = [142, 455, 891, 1024, 1560]

for i in range(1801):
    frame = np.zeros((480, 640, 3), dtype=np.uint8)
    if i in red_frames:
        frame[0:50, 0:50] = [0, 0, 255] # BGR
    out.write(frame)

out.release()
EOF
    python3 /tmp/gen_video.py

    # Generate the backups archive using bash
    cat << 'EOF' > /tmp/setup.sh
#!/bin/bash
mkdir -p /app/backups_raw/batch_0/
for i in $(seq 0 1800); do
  mkdir -p /app/backups_raw/batch_$((i/100))
  echo "[VALID_CONFIG_DATA]" > /app/backups_raw/batch_$((i/100))/config_batch_$i.conf
  if [[ " 142 455 891 1024 1560 " =~ " $i " ]]; then
    for j in $(seq 1 1000); do
      echo "[ROGUE_OVERRIDE_ENABLED=TRUE]" >> /app/backups_raw/batch_$((i/100))/config_batch_$i.conf
    done
  fi
done
tar -czf /app/config_backups.tar.gz -C /app backups_raw
rm -rf /app/backups_raw
EOF
    bash /tmp/setup.sh

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user

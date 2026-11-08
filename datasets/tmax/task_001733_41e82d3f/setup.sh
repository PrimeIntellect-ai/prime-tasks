#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang-go ffmpeg python3-opencv
    pip3 install pytest numpy

    mkdir -p /app/corpus/clean
    mkdir -p /app/corpus/evil

    # Generate video
    python3 -c "
import cv2
import numpy as np

out = cv2.VideoWriter('/app/deadlock_dashboard.mp4', cv2.VideoWriter_fourcc(*'mp4v'), 30, (100, 100))
red_frames = {24, 78, 142, 205, 310}

for i in range(400):
    frame = np.zeros((100, 100, 3), dtype=np.uint8)
    if i in red_frames:
        frame[:] = (0, 0, 255) # BGR
    out.write(frame)

out.release()
"

    # Generate corpora
    cat << 'EOF' > /app/corpus/clean/clean_1.json
{
  "transactions": [
    {"id": "T1", "holds_locks_on": ["TableA"], "waiting_for_locks_on": ["TableB"]},
    {"id": "T2", "holds_locks_on": ["TableB"], "waiting_for_locks_on": ["TableC"]}
  ]
}
EOF

    cat << 'EOF' > /app/corpus/clean/clean_2.json
{
  "transactions": [
    {"id": "T3", "holds_locks_on": ["TableX"], "waiting_for_locks_on": []}
  ]
}
EOF

    cat << 'EOF' > /app/corpus/evil/evil_1.json
{
  "transactions": [
    {"id": "T1", "holds_locks_on": ["TableA"], "waiting_for_locks_on": ["TableB"]},
    {"id": "T2", "holds_locks_on": ["TableB"], "waiting_for_locks_on": ["TableA"]}
  ]
}
EOF

    cat << 'EOF' > /app/corpus/evil/evil_2.json
{
  "transactions": [
    {"id": "T1", "holds_locks_on": ["TableA"], "waiting_for_locks_on": ["TableB"]},
    {"id": "T2", "holds_locks_on": ["TableB"], "waiting_for_locks_on": ["TableC"]},
    {"id": "T3", "holds_locks_on": ["TableC"], "waiting_for_locks_on": ["TableA"]}
  ]
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user

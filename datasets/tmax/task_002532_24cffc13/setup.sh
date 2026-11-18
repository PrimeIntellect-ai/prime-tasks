#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip libglib2.0-0
    pip3 install pytest numpy opencv-python-headless

    mkdir -p /app/verifier/clean /app/verifier/evil

    cat << 'EOF' > /tmp/gen_video.py
import cv2
import numpy as np

out = cv2.VideoWriter('/app/conveyor_belt.mp4', cv2.VideoWriter_fourcc(*'mp4v'), 30, (100, 100))
for i in range(300):
    frame = np.full((100, 100, 3), 100, dtype=np.uint8)
    if i in [45, 46, 47, 120, 121, 250, 251, 252, 253]:
        frame[:, :, 2] = 200 # R=200, B=100 -> R-B = 100 > 50
    out.write(frame)
out.release()
EOF
    python3 /tmp/gen_video.py

    cat << 'EOF' > /app/verifier/clean/clean_1.csv
timestamp_ms,sensor_A,sensor_B
1000,50.0,15.0
1100,50.0,15.0
1200,50.0,15.0
EOF

    cat << 'EOF' > /app/verifier/clean/clean_2.csv
timestamp_ms,sensor_A,sensor_B
1000,100.0,10.0
1050,100.0,10.0
2049,100.0,10.0
EOF

    cat << 'EOF' > /app/verifier/evil/evil_1_monotonic.csv
timestamp_ms,sensor_A,sensor_B
1000,50.0,15.0
1100,50.0,15.0
1050,50.0,15.0
EOF

    cat << 'EOF' > /app/verifier/evil/evil_2_gap.csv
timestamp_ms,sensor_A,sensor_B
1000,50.0,15.0
2001,50.0,15.0
EOF

    cat << 'EOF' > /app/verifier/evil/evil_3_rolling.csv
timestamp_ms,sensor_A,sensor_B
1000,100.0,15.0
1100,100.0,15.0
1200,101.0,15.0
EOF

    cat << 'EOF' > /app/verifier/evil/evil_4_global.csv
timestamp_ms,sensor_A,sensor_B
1000,50.0,9.9
1100,50.0,10.0
EOF

    cat << 'EOF' > /app/verifier/evil/evil_5_headers.csv
timestamp, sensorA, sensorB
1000,50.0,15.0
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user

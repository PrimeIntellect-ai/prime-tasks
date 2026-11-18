#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3 libglib2.0-0
    pip3 install pytest numpy pandas opencv-python-headless

    mkdir -p /app
    mkdir -p /home/user

    # Generate mock video
    python3 -c "
import cv2
import numpy as np
out = cv2.VideoWriter('/app/sensor_feed.mp4', cv2.VideoWriter_fourcc(*'mp4v'), 30, (640, 480))
for i in range(100):
    frame = np.zeros((480, 640, 3), dtype=np.uint8)
    cv2.circle(frame, (100 + i*2, 240), 10, (255, 255, 255), -1)
    out.write(frame)
out.release()
"

    # Create sqlite database
    sqlite3 /home/user/calibration.db <<EOF
CREATE TABLE configs (id INTEGER PRIMARY KEY, is_active INTEGER, offset_x REAL);
INSERT INTO configs (is_active, offset_x) VALUES (0, 10.0);
INSERT INTO configs (is_active, offset_x) VALUES (0, -50.0);
INSERT INTO configs (is_active, offset_x) VALUES (1, 1000000.0); -- large offset to cause cancellation
EOF

    # Create buggy python script
    cat << 'EOF' > /home/user/analyze_motion.py
import cv2
import numpy as np
import sqlite3
import pandas as pd

def get_offset():
    conn = sqlite3.connect('/home/user/calibration.db')
    cursor = conn.cursor()
    # BUG: Gets the first row instead of active
    cursor.execute("SELECT offset_x FROM configs LIMIT 1")
    offset = cursor.fetchone()[0]
    conn.close()
    return offset

def process_video(video_path, offset):
    cap = cv2.VideoCapture(video_path)
    x_coords = []

    while cap.isOpened():
        ret, frame = cap.read()
        if not ret:
            break
        # Mock tracking: just take the argmax of the red channel for simplicity
        # (Assuming the video has a bright spot)
        gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)
        _, _, _, max_loc = cv2.minMaxLoc(gray)
        x_coords.append(max_loc[0] + offset)

    cap.release()
    return np.array(x_coords, dtype=np.float32)

def compute_rolling_variance(x_coords, window=30):
    variances = []
    for i in range(window - 1, len(x_coords)):
        window_data = x_coords[i - window + 1 : i + 1]
        # BUG: Naive variance calculation in float32 causes catastrophic cancellation
        n = len(window_data)
        sum_val = np.sum(window_data)
        sum_sq = np.sum(window_data**2)
        var = (sum_sq - (sum_val**2) / n) / n
        variances.append((i, var))
    return variances

def main():
    offset = get_offset()
    x_coords = process_video('/app/sensor_feed.mp4', offset)
    variances = compute_rolling_variance(x_coords)

    df = pd.DataFrame(variances, columns=['frame_idx', 'variance'])
    df.to_csv('/home/user/variance_output.csv', index=False)

if __name__ == '__main__':
    main()
EOF

    chmod +x /home/user/analyze_motion.py

    # Generate ground truth for the verifier
    python3 -c "
import cv2
import numpy as np
import pandas as pd

cap = cv2.VideoCapture('/app/sensor_feed.mp4')
x_coords = []
offset = 1000000.0
while cap.isOpened():
    ret, frame = cap.read()
    if not ret: break
    gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)
    _, _, _, max_loc = cv2.minMaxLoc(gray)
    x_coords.append(max_loc[0] + offset)
cap.release()

x_coords = np.array(x_coords, dtype=np.float64)
window = 30
variances = []
for i in range(window - 1, len(x_coords)):
    window_data = x_coords[i - window + 1 : i + 1]
    var = np.var(window_data, ddof=0, dtype=np.float64)
    variances.append((i, var))

df = pd.DataFrame(variances, columns=['frame_idx', 'variance'])
df.to_csv('/tmp/truth_variance.csv', index=False)
"

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
    chmod 777 /tmp/truth_variance.csv

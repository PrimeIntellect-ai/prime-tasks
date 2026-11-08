#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg
    pip3 install pytest numpy opencv-python-headless

    mkdir -p /app/corpora/evil
    mkdir -p /app/corpora/clean

    # Generate evil corpus
    cat << 'EOF' > /app/corpora/evil/evil1.py
from sklearn.preprocessing import StandardScaler
from sklearn.model_selection import train_test_split
scaler = StandardScaler()
X_scaled = scaler.fit_transform(X)
X_train, X_test, y_train, y_test = train_test_split(X_scaled, y)
EOF

    cat << 'EOF' > /app/corpora/evil/evil2.py
scaler.fit(data)
train, test = train_test_split(data)
EOF

    # Generate clean corpus
    cat << 'EOF' > /app/corpora/clean/clean1.py
from sklearn.model_selection import train_test_split
X_train, X_test = train_test_split(X)
X_train_scaled = scaler.fit_transform(X_train)
EOF

    cat << 'EOF' > /app/corpora/clean/clean2.py
train_test_split(X, y)
scaler.fit(X_train)
EOF

    # Generate telemetry video
    cat << 'EOF' > /tmp/gen_vid.py
import cv2
import numpy as np

out = cv2.VideoWriter('/app/telemetry.mp4', cv2.VideoWriter_fourcc(*'mp4v'), 10, (100, 100))
for i in range(100):
    frame = np.zeros((100, 100, 3), dtype=np.uint8)
    if i in [10, 20, 30, 40, 50, 60, 70]:
        frame[:] = (0, 0, 255) # BGR -> Red is (0, 0, 255)
    else:
        frame[:] = (255, 255, 255)
    out.write(frame)
out.release()
EOF
    python3 /tmp/gen_vid.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user

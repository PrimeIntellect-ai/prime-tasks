#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc ffmpeg
    pip3 install pytest opencv-python-headless numpy

    mkdir -p /app/corpus/clean
    mkdir -p /app/corpus/evil

    # Generate video
    cat << 'EOF' > /tmp/gen_video.py
import cv2
import numpy as np

out = cv2.VideoWriter('/app/spectroscopy.mp4', cv2.VideoWriter_fourcc(*'mp4v'), 30, (100, 100), False)
for i in range(300):
    val = int(127.5 * (1 + np.sin(i / 10.0)))
    frame = np.full((100, 100), val, dtype=np.uint8)
    out.write(frame)
out.release()
EOF
    python3 /tmp/gen_video.py
    rm /tmp/gen_video.py

    # Clean corpus
    cat << 'EOF' > /app/corpus/clean/kahan.c
float integrate(float* data, int n) {
    float sum = 0.0f;
    float c = 0.0f;
    for (int i = 0; i < n; i++) {
        float y = data[i] - c;
        float t = sum + y;
        c = (t - sum) - y;
        sum = t;
    }
    return sum;
}
EOF

    cat << 'EOF' > /app/corpus/clean/double_acc.c
float integrate(float* data, int n) {
    double sum = 0.0;
    for (int i = 0; i < n; i++) {
        sum += (double)data[i];
    }
    return (float)sum;
}
EOF

    # Evil corpus
    cat << 'EOF' > /app/corpus/evil/naive.c
float integrate(float* data, int n) {
    float sum = 0.0f;
    for (int i = 0; i < n; i++) {
        sum += data[i];
    }
    return sum;
}
EOF

    cat << 'EOF' > /app/corpus/evil/naive_unrolled.c
float integrate(float* data, int n) {
    float sum = 0.0f;
    int i = 0;
    for (; i <= n - 4; i += 4) {
        sum += data[i] + data[i+1] + data[i+2] + data[i+3];
    }
    for (; i < n; i++) {
        sum += data[i];
    }
    return sum;
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app

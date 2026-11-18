#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        gcc \
        libgl1 \
        libglib2.0-0

    pip3 install pytest numpy opencv-python-headless pandas scipy

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user/src

    cat << 'EOF' > /home/user/src/fast_mse.c
double compute_mse(double* arr1, double* arr2, int length) {
    double sum = 0.0;
    for(int i=0; i<length; i++) {
        double diff = arr1[i] - arr2[i];
        sum += diff * diff;
    }
    return sum / length;
}
EOF

    mkdir -p /app/corpus/clean /app/corpus/evil /app/corpus_hidden_eval/clean /app/corpus_hidden_eval/evil /app/video

    python3 -c "
import os
import random
import cv2
import numpy as np
import math

def make_csv(path, evil=False):
    with open(path, 'w') as f:
        f.write('x,y\n')
        x, y = 100.0, 100.0
        for i in range(20):
            if evil and i == 10:
                x += 60.0
            else:
                x += random.uniform(-5, 5)
                y += random.uniform(-5, 5)
            f.write(f'{x},{y}\n')

for d in ['/app/corpus/clean', '/app/corpus_hidden_eval/clean']:
    for i in range(5):
        make_csv(f'{d}/data_{i}.csv', evil=False)

for d in ['/app/corpus/evil', '/app/corpus_hidden_eval/evil']:
    for i in range(5):
        make_csv(f'{d}/data_{i}.csv', evil=True)

out = cv2.VideoWriter('/app/video/experiment_run.mp4', cv2.VideoWriter_fourcc(*'mp4v'), 30, (640, 480))
for t in range(300):
    img = np.ones((480, 640, 3), dtype=np.uint8) * 255
    x = 320 + 150 * math.cos(0.1047 * t) * math.exp(-0.015 * t)
    y = 240
    cv2.circle(img, (int(x), int(y)), 20, (0, 0, 0), -1)
    out.write(img)
out.release()
"

    chmod -R 777 /home/user
    chmod -R 777 /app

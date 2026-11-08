#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        python3-numpy \
        python3-opencv \
        build-essential \
        libgomp1 \
        ffmpeg

    pip3 install pytest

    mkdir -p /app/corpus/evil /app/corpus/clean /app/sample_data

    cat << 'EOF' > /tmp/gen_data.py
import os
import numpy as np
import cv2

def gen_clean():
    A = np.random.randn(100, 100)
    return np.dot(A, A.T) + np.eye(100)*10

def gen_evil():
    A = np.random.randn(100, 100)
    U, _, V = np.linalg.svd(A)
    S = np.linspace(1e-8, 1, 100)
    M = np.dot(U * S, V)
    return np.dot(M, M.T)

def save_mat(M, path):
    with open(path, 'w') as f:
        f.write("100\n")
        for row in M:
            f.write(" ".join(map(str, row)) + "\n")

clean_mats = []
evil_mats = []

for i in range(50):
    c = gen_clean()
    e = gen_evil()
    clean_mats.append(c)
    evil_mats.append(e)
    save_mat(c, f"/app/corpus/clean/clean_{i}.txt")
    save_mat(e, f"/app/corpus/evil/evil_{i}.txt")
    if i < 5:
        save_mat(c, f"/app/sample_data/clean_{i}.txt")
        save_mat(e, f"/app/sample_data/evil_{i}.txt")

fourcc = cv2.VideoWriter_fourcc(*'mp4v')
out = cv2.VideoWriter('/app/sensor_feed.mp4', fourcc, 10.0, (100, 100), False)

for i in range(45):
    c = clean_mats[i]
    c_min, c_max = c.min(), c.max()
    if c_max > c_min:
        c_norm = ((c - c_min) / (c_max - c_min) * 255)
    else:
        c_norm = np.zeros_like(c)
    out.write(c_norm.astype(np.uint8))

for i in range(15):
    e = evil_mats[i]
    e_min, e_max = e.min(), e.max()
    if e_max > e_min:
        e_norm = ((e - e_min) / (e_max - e_min) * 255)
    else:
        e_norm = np.zeros_like(e)
    out.write(e_norm.astype(np.uint8))

out.release()
EOF

    python3 /tmp/gen_data.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user

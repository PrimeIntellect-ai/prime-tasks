#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip espeak ffmpeg
pip3 install pytest numpy scipy

mkdir -p /app/corpora/clean /app/corpora/evil /app/audio

# Generate audio memo
espeak -w /app/audio/lab_memo.wav "Make sure to set the negative eigenvalue tolerance strictly to one point two times ten to the negative four."

# Generate pdist files
cat << 'EOF' > /tmp/gen_pdist.py
import numpy as np
import os

def generate_clean(filename):
    pts = np.random.rand(10, 3)
    dist = np.linalg.norm(pts[:, None, :] - pts[None, :, :], axis=-1)
    with open(filename, 'w') as f:
        f.write(">Seq1 CLEAN\n")
        for i in range(10):
            for j in range(10):
                if i != j:
                    f.write(f"{i} {j} {dist[i,j]:.6f}\n")

def generate_evil(filename):
    dist = np.random.rand(10, 10) * 10
    dist = (dist + dist.T) / 2
    np.fill_diagonal(dist, 0)
    # Ensure it's not PSD by adding a large value to off-diagonal
    dist[0, 1] += 50.0
    dist[1, 0] += 50.0
    with open(filename, 'w') as f:
        f.write(">Seq2 EVIL\n")
        for i in range(10):
            for j in range(10):
                if i != j:
                    f.write(f"{i} {j} {dist[i,j]:.6f}\n")

for i in range(3):
    generate_clean(f'/app/corpora/clean/clean_{i}.pdist')
    generate_evil(f'/app/corpora/evil/evil_{i}.pdist')
EOF

python3 /tmp/gen_pdist.py

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
chmod -R 777 /app

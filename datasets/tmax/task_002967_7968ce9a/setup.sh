#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    # Install dependencies for setup script and agent
    pip3 install numpy opencv-python-headless scipy matplotlib flask fastapi uvicorn biopython

    # Run setup script to generate files
    python3 -c "
import os
import cv2
import numpy as np

os.makedirs('/app', exist_ok=True)

# Generate FASTA
fasta_content = \"\"\">Seq1_promoter
ATGCGTACGTAGCTAGCTAGCTGATCGATGCTAGCTAGCTAGCTAGCTAGCTAGCTG
>Seq2_enhancer
GGCCGGCCGGCCGGCCGGCCGGCCGGCCGGCCGGCC
>Seq3_terminator
ATATATATATATATATATATATATATATATATATAT
\"\"\"
with open('/app/targets.fasta', 'w') as f:
    f.write(fasta_content)

# Generate Video
V_max = 200.0
K_m = 15.0

fourcc = cv2.VideoWriter_fourcc(*'mp4v')
out = cv2.VideoWriter('/app/assay_video.mp4', fourcc, 10.0, (400, 400), False)

np.random.seed(42)
for t in range(50):
    frame = np.zeros((400, 400), dtype=np.uint8)
    # Background noise
    frame += np.random.randint(0, 10, (400, 400), dtype=np.uint8)

    # Target center mean intensity
    target_mean = (V_max * t) / (K_m + t)

    # Create center with target mean
    center = np.random.normal(target_mean, 5.0, (100, 100))
    center = np.clip(center, 0, 255).astype(np.uint8)

    frame[150:250, 150:250] = center
    out.write(frame)

out.release()
"

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user

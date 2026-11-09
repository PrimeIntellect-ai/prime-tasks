#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip libglib2.0-0
    pip3 install pytest numpy pandas opencv-python-headless
    pip3 install torch --index-url https://download.pytorch.org/whl/cpu

    mkdir -p /app
    cat << 'EOF' > /app/setup.py
import os
import cv2
import numpy as np
import torch
import torch.nn as nn

os.makedirs("/app", exist_ok=True)

# 1. Generate /app/noisy_feed.mp4
width, height = 64, 64
fps = 10
num_frames = 50
out = cv2.VideoWriter('/app/noisy_feed.mp4', cv2.VideoWriter_fourcc(*'mp4v'), fps, (width, height), isColor=False)

np.random.seed(123)
static_bg = np.random.randint(0, 255, (height, width), dtype=np.uint8)

for i in range(num_frames):
    # Moving signal: a simple moving white square
    frame = static_bg.copy().astype(np.float32)
    x = int(i * (width / num_frames))
    y = height // 2
    cv2.rectangle(frame, (x, y-5), (x+10, y+5), 255, -1)
    frame = np.clip(frame, 0, 255).astype(np.uint8)
    out.write(frame)
out.release()

# 2. Generate /app/model.pth
class AnomalyModel(nn.Module):
    def __init__(self):
        super().__init__()
        self.net = nn.Sequential(
            nn.Linear(10, 16),
            nn.ReLU(),
            nn.Linear(16, 1)
        )

model = AnomalyModel()
# Initialize with deterministic weights for reproducibility
torch.manual_seed(123)
for name, param in model.named_parameters():
    nn.init.normal_(param, mean=0.0, std=0.1)

torch.save(model.net.state_dict(), '/app/model.pth')
EOF

    python3 /app/setup.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user

#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg

    pip3 install pytest pandas numpy matplotlib seaborn flask fastapi uvicorn opencv-python-headless
    pip3 install torch torchvision --index-url https://download.pytorch.org/whl/cpu

    mkdir -p /app/output

    # Generate test video
    ffmpeg -f lavfi -i testsrc=duration=10:size=640x480:rate=30 -c:v libx264 /app/traffic.mp4

    # Create sensor logs
    cat << 'EOF' > /app/sensor_logs.csv
time_sec,temperature,humidity,luminosity
0,22.1,45.0,200.5
1,22.2,45.1,201.0
2,22.3,45.2,205.1
3,22.4,45.3,210.0
4,22.5,45.4,215.5
5,22.6,45.5,220.0
6,22.7,45.6,225.2
7,22.8,45.7,230.1
8,22.9,45.8,235.0
9,23.0,45.9,240.5
EOF

    # Generate PyTorch model weights
    cat << 'EOF' > /tmp/gen_model.py
import torch, torch.nn as nn
class SimpleEncoder(nn.Module):
    def __init__(self):
        super().__init__()
        self.conv1 = nn.Conv2d(3, 16, 3, 2, 1)
        self.relu = nn.ReLU()
        self.conv2 = nn.Conv2d(16, 32, 3, 2, 1)
        self.flatten = nn.Flatten()
        self.fc1 = nn.Linear(32*16*16, 16)
        self.fc2 = nn.Linear(16, 4)
    def forward(self, x):
        x = self.relu(self.conv1(x))
        x = self.relu(self.conv2(x))
        x = self.flatten(x)
        x = self.relu(self.fc1(x))
        return self.fc2(x)
torch.manual_seed(42)
model = SimpleEncoder()
torch.save(model.state_dict(), '/app/embedding_model.pth')
EOF
    python3 /tmp/gen_model.py

    # Create plotting script
    cat << 'EOF' > /app/plot_correlations.py
import matplotlib.pyplot as plt
import seaborn as sns
import pandas as pd
import numpy as np

def plot_heatmap(df):
    # BUG: Missing matplotlib.use('Agg') for headless environments
    # This might result in GUI backend issues or blank plots if plt.show() fails.
    # To simulate the exact bug, we just save without closing/setting backend correctly,
    # or the user has to insert import matplotlib; matplotlib.use('Agg')
    fig, ax = plt.subplots()
    sns.heatmap(df.corr(), annot=True, ax=ax)
    # The agent should modify this to save to /app/output/correlation_heatmap.png
    plt.savefig('/app/output/correlation_heatmap.png')
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /app
    chmod -R 777 /home/user

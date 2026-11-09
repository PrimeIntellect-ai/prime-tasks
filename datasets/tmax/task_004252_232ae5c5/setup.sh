#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg

    # Install PyTorch CPU version to save time and space
    pip3 install torch torchvision --index-url https://download.pytorch.org/whl/cpu
    pip3 install pytest pandas numpy matplotlib opencv-python-headless pillow

    mkdir -p /app/model /app/data /app/verifier/clean /app/verifier/evil

    # Generate video
    ffmpeg -y -f lavfi -i testsrc=duration=10:size=640x480:rate=30 -pix_fmt yuv420p /app/dashcam.mp4

    # Generate data using a python script
    cat << 'EOF' > /tmp/setup_data.py
import torch
import torch.nn as nn
import os
import pandas as pd
import numpy as np
import matplotlib.pyplot as plt
from PIL import Image

class VisibilityModel(nn.Module):
    def __init__(self):
        super().__init__()
        self.conv1 = nn.Conv2d(1, 16, 3, padding=1)
        self.fc = nn.Linear(16 * 64 * 64, 1)
    def forward(self, x):
        x = self.conv1(x)
        x = x.view(x.size(0), -1)
        return self.fc(x)

model = VisibilityModel()
torch.save(model.state_dict(), '/app/model/weights.pth')

with open('/app/model/arch.py', 'w') as f:
    f.write('''import torch.nn as nn
class VisibilityModel(nn.Module):
    def __init__(self):
        super().__init__()
        # missing in_channels
        self.conv1 = nn.Conv2d(IN_CHANNELS_HERE, 16, 3, padding=1)
        self.fc = nn.Linear(16 * 64 * 64, 1)
    def forward(self, x):
        x = self.conv1(x)
        x = x.view(x.size(0), -1)
        return self.fc(x)
''')

df_tel = pd.DataFrame({'timestamp_sec': np.arange(0, 10, 0.1), 'speed': np.random.rand(100)})
df_tel.to_csv('/app/data/telemetry.csv', index=False)

df_gps = pd.DataFrame({'timestamp_sec': np.arange(0, 10, 0.2), 'lat': np.random.rand(50), 'lon': np.random.rand(50)})
df_gps.to_csv('/app/data/gps.csv', index=False)

# Clean corpus
plt.figure()
plt.plot([1,2,3], [4,5,6])
plt.savefig('/app/verifier/clean/plot1.png')
plt.close()

# Evil corpus
plt.figure()
plt.savefig('/app/verifier/evil/blank_axes.png')
plt.close()

Image.new('RGB', (100, 100), color='white').save('/app/verifier/evil/white.png')
Image.new('RGB', (100, 100), color='black').save('/app/verifier/evil/black.png')
EOF

    python3 /tmp/setup_data.py
    rm /tmp/setup_data.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app

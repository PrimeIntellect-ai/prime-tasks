#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg

    # Install CPU versions of PyTorch to save time and space
    pip3 install torch torchvision --index-url https://download.pytorch.org/whl/cpu
    pip3 install pytest Pillow numpy

    mkdir -p /app/corpora/clean
    mkdir -p /app/corpora/evil
    mkdir -p /tmp/video_frames

    cat << 'EOF' > /tmp/setup.py
import os
import torch
import torch.nn as nn
from PIL import Image
import numpy as np

class Autoencoder(nn.Module):
    def __init__(self):
        super(Autoencoder, self).__init__()
        self.encoder = nn.Sequential(
            nn.Conv2d(3, 16, 3, stride=2, padding=1),
            nn.ReLU()
        )
        self.decoder = nn.Sequential(
            nn.ConvTranspose2d(16, 3, 3, stride=2, padding=1, output_padding=1),
            nn.Sigmoid()
        )
    def forward(self, x):
        return self.decoder(self.encoder(x))

model = Autoencoder()
optimizer = torch.optim.Adam(model.parameters(), lr=0.05)
criterion = nn.MSELoss()

# Train simple AE to reconstruct solid colors
clean_tensors = [torch.rand(3, 1, 1).expand(3, 64, 64) for _ in range(100)]
clean_data = torch.stack(clean_tensors)

for epoch in range(50):
    optimizer.zero_grad()
    out = model(clean_data)
    loss = criterion(out, clean_data)
    loss.backward()
    optimizer.step()

torch.save(model.state_dict(), '/app/ae_weights.pth')

def save_img(tensor, path):
    arr = (tensor.permute(1, 2, 0).detach().numpy() * 255).astype(np.uint8)
    Image.fromarray(arr).save(path)

# Generate corpora
for i in range(20):
    c = torch.rand(3, 1, 1).expand(3, 64, 64)
    save_img(c, f'/app/corpora/clean/{i:03d}.png')

    e = torch.rand(3, 64, 64)
    save_img(e, f'/app/corpora/evil/{i:03d}.png')

# Generate video frames
# 10 frames total. 3, 7, 8 are evil
for i in range(1, 11):
    if i in [3, 7, 8]:
        t = torch.rand(3, 64, 64)
    else:
        t = torch.rand(3, 1, 1).expand(3, 64, 64)
    save_img(t, f'/tmp/video_frames/{i:03d}.png')

EOF

    python3 /tmp/setup.py
    ffmpeg -framerate 1 -i /tmp/video_frames/%03d.png -c:v libx264 -r 1 -pix_fmt yuv420p /app/unlabeled_video.mp4

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app

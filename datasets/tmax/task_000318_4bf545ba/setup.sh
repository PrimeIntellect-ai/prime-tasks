#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr
    pip3 install pytest pandas numpy Pillow pytesseract fastapi uvicorn flask requests
    pip3 install torch --index-url https://download.pytorch.org/whl/cpu

    useradd -m -s /bin/bash user || true

    python3 -c "
import os
import torch
import torch.nn as nn
import pandas as pd
import numpy as np
from PIL import Image, ImageDraw

os.makedirs('/home/user/data', exist_ok=True)
os.makedirs('/home/user/model', exist_ok=True)
os.makedirs('/app', exist_ok=True)

data = {
    'id': [1, 2, 3, 4, 5, 6, 7],
    'temperature': [25.0, 150.0, 20.0, -30.0, 22.0, 24.0, 26.0],
    'humidity': [50.0, 45.0, np.nan, 55.0, np.nan, 48.0, 52.0],
    'pressure': [1013.0, 1010.0, 1012.0, 1005.0, 1011.0, 1014.0, 1013.0]
}
df = pd.DataFrame(data)
df.to_csv('/home/user/data/raw_sensor_data.csv', index=False)

class SimpleMLP(nn.Module):
    def __init__(self):
        super().__init__()
        self.net = nn.Sequential(
            nn.Linear(3, 16),
            nn.ReLU(),
            nn.Linear(16, 8),
            nn.ReLU(),
            nn.Linear(8, 1)
        )

    def forward(self, x):
        return self.net(x)

torch.manual_seed(42)
model = SimpleMLP()
torch.save(model.state_dict(), '/home/user/model/weights.pth')

img = Image.new('RGB', (600, 200), color = (255, 255, 255))
d = ImageDraw.Draw(img)
text = 'PROTOCOL:\n1. Drop rows where temperature > 100 or temperature < -20.\n2. Impute missing humidity with the median.\n3. Model Hidden Layers: 16, 8.'
d.text((10,10), text, fill=(0,0,0))
img.save('/app/cleaning_rules.png')
"

    chmod -R 777 /home/user
    chmod -R 777 /app

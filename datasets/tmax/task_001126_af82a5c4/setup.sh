#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg python3-numpy cargo rustc
    pip3 install pytest gTTS

    cat << 'EOF' > /tmp/setup.py
import os
import numpy as np
from gtts import gTTS

os.makedirs('/app/data/clean', exist_ok=True)
os.makedirs('/app/data/evil', exist_ok=True)

tts = gTTS(text="Set the gradient descent learning rate to exactly zero point zero zero three and the maximum iterations to two hundred.", lang='en')
tts.save('/app/field_notes.mp3')
os.system('ffmpeg -y -i /app/field_notes.mp3 -ar 16000 /app/field_notes.wav 2>/dev/null')
os.remove('/app/field_notes.mp3')

np.random.seed(42)

for i in range(20):
    x = np.random.uniform(-1, 1, 100)
    y = 2.5 * x + 1.0 + np.random.normal(0, 0.1, 100)
    with open(f'/app/data/clean/data_{i}.csv', 'w') as f:
        f.write("x,y\n")
        for xi, yi in zip(x, y):
            f.write(f"{xi},{yi}\n")

for i in range(20):
    x = np.random.uniform(-20, 20, 100)
    y = 2.5 * x + 1.0 + np.random.normal(0, 5.0, 100)
    with open(f'/app/data/evil/data_{i}.csv', 'w') as f:
        f.write("x,y\n")
        for xi, yi in zip(x, y):
            f.write(f"{xi},{yi}\n")
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app

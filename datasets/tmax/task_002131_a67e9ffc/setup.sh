#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr
    pip3 install pytest pytesseract scipy numpy pandas pillow

    mkdir -p /app/data/training_good
    mkdir -p /app/data/training_corrupted
    mkdir -p /app/data/eval_clean
    mkdir -p /app/data/eval_evil

    cat << 'EOF' > /tmp/setup_data.py
import os
import numpy as np
import pandas as pd
from scipy.integrate import odeint
from PIL import Image, ImageDraw

text = """Reaction Kinetics Model:
dA/dt = -k1 * A * B
dB/dt = -k1 * A * B - k2 * B
dC/dt = k1 * A * B + k2 * B
Constants:
k1 = 0.08
k2 = 0.15
Conservation Law:
A + B + C = 15.0"""

img = Image.new('RGB', (400, 300), color = (255, 255, 255))
d = ImageDraw.Draw(img)
d.text((10,10), text, fill=(0,0,0))
img.save('/app/system_specs.png')

def model(y, t, k1, k2):
    A, B, C = y
    dAdt = -k1 * A * B
    dBdt = -k1 * A * B - k2 * B
    dCdt = k1 * A * B + k2 * B
    return [dAdt, dBdt, dCdt]

t = np.linspace(0, 10, 100)
k1, k2 = 0.08, 0.15

def gen_good(filename):
    A0 = np.random.uniform(5, 10)
    B0 = np.random.uniform(2, 5)
    C0 = 15.0 - A0 - B0
    y0 = [A0, B0, C0]
    sol = odeint(model, y0, t, args=(k1, k2))
    noise = np.random.normal(0, 0.02, sol.shape)
    sol += noise
    df = pd.DataFrame(sol, columns=['A', 'B', 'C'])
    df.insert(0, 'time', t)
    df.to_csv(filename, index=False)

def gen_bad(filename, bad_type):
    A0 = np.random.uniform(5, 10)
    B0 = np.random.uniform(2, 5)
    C0 = 15.0 - A0 - B0
    y0 = [A0, B0, C0]
    sol = odeint(model, y0, t, args=(k1, k2))

    if bad_type == 0:
        noise = np.random.uniform(-0.05, 0.05, sol.shape)
        sol += noise
    elif bad_type == 1:
        noise = np.random.normal(0, 0.02, sol.shape)
        sol += noise
        sol[50:, 2] += 2.0
    else:
        noise = np.random.normal(0, 0.02, sol.shape)
        sol += noise
        sol[:, 0] += np.linspace(0, 1, 100)

    df = pd.DataFrame(sol, columns=['A', 'B', 'C'])
    df.insert(0, 'time', t)
    df.to_csv(filename, index=False)

for i in range(10):
    gen_good(f'/app/data/training_good/sim_{i}.csv')
    gen_bad(f'/app/data/training_corrupted/sim_{i}.csv', i % 3)

for i in range(20):
    gen_good(f'/app/data/eval_clean/sim_{i}.csv')
    gen_bad(f'/app/data/eval_evil/sim_{i}.csv', i % 3)
EOF

    python3 /tmp/setup_data.py
    rm /tmp/setup_data.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user

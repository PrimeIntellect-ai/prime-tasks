#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip python3-venv tesseract-ocr
    pip3 install pytest numpy scipy pandas pillow

    # Generate data
    cat << 'EOF' > /tmp/setup_data.py
import os
import numpy as np
import pandas as pd
from scipy.integrate import odeint
from PIL import Image, ImageDraw

os.makedirs('/app', exist_ok=True)
img = Image.new('RGB', (400, 200), color=(255, 255, 255))
d = ImageDraw.Draw(img)
text = "LOTKA-VOLTERRA PARAMS:\nalpha=1.2\nbeta=0.4\ndelta=0.1\ngamma=0.8"
d.text((10,10), text, fill=(0,0,0))
img.save('/app/lab_notes_scan.png')

alpha, beta, delta, gamma = 1.2, 0.4, 0.1, 0.8
y0 = [10.0, 5.0]
t = np.linspace(0, 50, 500)

def lv_system(y, t, alpha, beta, delta, gamma):
    prey, pred = y
    return [alpha * prey - beta * prey * pred, delta * prey * pred - gamma * pred]

clean_dir = '/app/corpora/clean'
evil_dir = '/app/corpora/evil'
os.makedirs(clean_dir, exist_ok=True)
os.makedirs(evil_dir, exist_ok=True)

sol = odeint(lv_system, y0, t, args=(alpha, beta, delta, gamma))

for i in range(20):
    noise = np.random.normal(0, 0.5, sol.shape)
    noisy_sol = np.maximum(sol + noise, 0)
    pd.DataFrame({'time': t, 'prey': noisy_sol[:, 0], 'predator': noisy_sol[:, 1]}).to_csv(f'{clean_dir}/clean_{i}.csv', index=False)

for i in range(5):
    evil_sol = sol.copy() - 5.0
    pd.DataFrame({'time': t, 'prey': evil_sol[:, 0], 'predator': evil_sol[:, 1]}).to_csv(f'{evil_dir}/evil_neg_{i}.csv', index=False)

for i in range(5):
    prey_exp = 10.0 * np.exp(0.2 * t)
    pred_exp = 5.0 * np.exp(-0.8 * t)
    pd.DataFrame({'time': t, 'prey': prey_exp, 'predator': pred_exp}).to_csv(f'{evil_dir}/evil_exp_{i}.csv', index=False)

sol_freq = odeint(lv_system, y0, t, args=(3.0, beta, delta, gamma))
for i in range(5):
    pd.DataFrame({'time': t, 'prey': sol_freq[:, 0], 'predator': sol_freq[:, 1]}).to_csv(f'{evil_dir}/evil_freq_{i}.csv', index=False)

for i in range(5):
    pd.DataFrame({'time': t, 'prey': np.random.uniform(0, 20, len(t)), 'predator': np.random.uniform(0, 20, len(t))}).to_csv(f'{evil_dir}/evil_rand_{i}.csv', index=False)
EOF

    python3 /tmp/setup_data.py
    rm /tmp/setup_data.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app

#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg bc
    pip3 install pytest papermill jupyter numpy scipy nbformat pandas

    mkdir -p /app/corpus/clean
    mkdir -p /app/corpus/evil

    cat << 'EOF' > /tmp/setup.py
import subprocess
import numpy as np
import nbformat as nbf
import os
import pandas as pd

# 1. Generate video
width, height = 64, 64
fps = 30
duration = 10
total_frames = fps * duration

frames = np.zeros((total_frames, height, width, 3), dtype=np.uint8)
frames[:42, :, :, 0] = 255  # Red channel

process = subprocess.Popen([
    'ffmpeg', '-y', '-f', 'rawvideo', '-vcodec', 'rawvideo',
    '-s', f'{width}x{height}', '-pix_fmt', 'rgb24', '-r', str(fps),
    '-i', '-', '-c:v', 'libx264', '-pix_fmt', 'yuv420p', '/app/calibration.mp4'
], stdin=subprocess.PIPE, stderr=subprocess.DEVNULL)

for frame in frames:
    process.stdin.write(frame.tobytes())
process.stdin.close()
process.wait()

# 2. Generate notebook
nb = nbf.v4.new_notebook()
code1 = "C = 1"
cell1 = nbf.v4.new_code_cell(code1)
cell1.metadata['tags'] = ['parameters']

code2 = """import numpy as np
import pandas as pd
from scipy.integrate import odeint
def model(y, t): return -C * y
t = np.linspace(0, 10, 100)
y = odeint(model, 1.0, t)
df = pd.DataFrame({'time': t, 'value': y.flatten()})
df.to_csv('/tmp/reference_solution.csv', index=False)
"""
cell2 = nbf.v4.new_code_cell(code2)
nb['cells'] = [cell1, cell2]
nbf.write(nb, '/app/solve_ode.ipynb')

# 3. Generate corpus
t = np.linspace(0, 10, 100)
y_ref = np.exp(-42 * t)

for i in range(5):
    y_clean = y_ref + np.random.uniform(-0.2, 0.2, size=100)
    pd.DataFrame({'time': t, 'value': y_clean}).to_csv(f'/app/corpus/clean/clean_{i}.csv', index=False)

for i in range(5):
    y_evil = y_ref + np.random.uniform(-0.2, 0.2, size=100)
    y_evil[np.random.randint(0, 100)] += 0.8
    pd.DataFrame({'time': t, 'value': y_evil}).to_csv(f'/app/corpus/evil/evil_{i}.csv', index=False)
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app

#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip python3-venv libgl1 libglib2.0-0
    pip3 install pytest opencv-python-headless numpy scipy pandas

    cat << 'EOF' > /tmp/setup.py
import cv2
import numpy as np
from scipy.integrate import solve_ivp
import os

os.makedirs('/app', exist_ok=True)

# Physics setup
g = 9.81
L = 2.5
b = 0.15
theta0 = 1.0
omega0 = 0.0
fps = 30
duration = 10
frames = fps * duration
t_eval = np.linspace(0, duration, frames, endpoint=False)

def pendulum_ode(t, y):
    theta, omega = y
    dtheta = omega
    domega = -(g/L)*np.sin(theta) - b*omega
    return [dtheta, domega]

sol = solve_ivp(pendulum_ode, [0, duration], [theta0, omega0], t_eval=t_eval, method='RK45', rtol=1e-8, atol=1e-8)

# Video generation
width, height = 640, 480
fourcc = cv2.VideoWriter_fourcc(*'mp4v')
out = cv2.VideoWriter('/app/pendulum.mp4', fourcc, fps, (width, height))

pivot = (320, 0)
pix_per_meter = 100
length_px = L * pix_per_meter

for theta in sol.y[0]:
    frame = np.zeros((height, width, 3), dtype=np.uint8)
    x = int(pivot[0] + length_px * np.sin(theta))
    y = int(pivot[1] + length_px * np.cos(theta))

    # Draw rod
    cv2.line(frame, pivot, (x, y), (255, 255, 255), 2)
    # Draw bob (Red)
    cv2.circle(frame, (x, y), 20, (0, 0, 255), -1)

    out.write(frame)

out.release()
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user

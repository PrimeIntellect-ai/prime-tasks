#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip libgl1 libglib2.0-0
    pip3 install pytest numpy scipy opencv-python fastapi uvicorn requests

    mkdir -p /app

    # Generate the oscillator video
    cat << 'EOF' > /app/generate_video.py
import cv2
import numpy as np
from scipy.integrate import solve_ivp

c = 0.5
k = 25.0
fps = 30
duration = 5
frames = fps * duration

def ode(t, y):
    return [y[1], -c*y[1] - k*y[0]]

sol = solve_ivp(ode, [0, duration], [600.0, 0.0], t_eval=np.linspace(0, duration, frames))
x_vals = sol.y[0]

out = cv2.VideoWriter('/app/oscillator.mp4', cv2.VideoWriter_fourcc(*'mp4v'), fps, (800, 600))
for x in x_vals:
    frame = np.zeros((600, 800, 3), dtype=np.uint8)
    cx = int(x)
    # Draw circle at the true x coordinate; if it goes off-screen, it gets clipped
    cv2.circle(frame, (cx, 300), 20, (0, 255, 0), -1)
    out.write(frame)
out.release()
EOF

    python3 /app/generate_video.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app

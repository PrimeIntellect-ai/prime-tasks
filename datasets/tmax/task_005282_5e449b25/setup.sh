#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip libgl1 libglib2.0-0
    pip3 install pytest numpy opencv-python-headless scipy

    mkdir -p /app
    mkdir -p /home/user

    # Generate the video
    cat << 'EOF' > /app/generate_video.py
import cv2
import numpy as np

k1 = 0.5
k2 = 0.2
dt = 0.1
steps = 49

A = 1.0
B = 0.0
A_sim = [A]
for _ in range(steps):
    dA1 = -k1 * A
    dB1 = k1 * A - k2 * B

    A2 = A + 0.5 * dt * dA1
    B2 = B + 0.5 * dt * dB1
    dA2 = -k1 * A2
    dB2 = k1 * A2 - k2 * B2

    A3 = A + 0.5 * dt * dA2
    B3 = B + 0.5 * dt * dB2
    dA3 = -k1 * A3
    dB3 = k1 * A3 - k2 * B3

    A4 = A + dt * dA3
    B4 = B + dt * dB3
    dA4 = -k1 * A4
    dB4 = k1 * A4 - k2 * B4

    A += (dt / 6.0) * (dA1 + 2*dA2 + 2*dA3 + dA4)
    B += (dt / 6.0) * (dB1 + 2*dB2 + 2*dB3 + dB4)
    A_sim.append(A)

out = cv2.VideoWriter('/app/experiment.mp4', cv2.VideoWriter_fourcc(*'mp4v'), 10, (200, 200))
for a in A_sim:
    frame = np.zeros((200, 200, 3), dtype=np.uint8)
    r = int(a * 255)
    frame[:, :] = (0, 0, r)  # BGR format: Blue, Green, Red
    out.write(frame)
out.release()
EOF

    python3 /app/generate_video.py

    # Create the oracle
    cat << 'EOF' > /app/oracle_evaluate_ll
#!/usr/bin/env python3
import sys

def rk4(k1, k2, dt, steps):
    A = 1.0
    B = 0.0
    A_sim = [A]
    for _ in range(steps):
        dA1 = -k1 * A
        dB1 = k1 * A - k2 * B

        A2 = A + 0.5 * dt * dA1
        B2 = B + 0.5 * dt * dB1
        dA2 = -k1 * A2
        dB2 = k1 * A2 - k2 * B2

        A3 = A + 0.5 * dt * dA2
        B3 = B + 0.5 * dt * dB2
        dA3 = -k1 * A3
        dB3 = k1 * A3 - k2 * B3

        A4 = A + dt * dA3
        B4 = B + dt * dB3
        dA4 = -k1 * A4
        dB4 = k1 * A4 - k2 * B4

        A += (dt / 6.0) * (dA1 + 2*dA2 + 2*dA3 + dA4)
        B += (dt / 6.0) * (dB1 + 2*dB2 + 2*dB3 + dB4)
        A_sim.append(A)
    return A_sim

def main():
    if len(sys.argv) != 3:
        sys.exit(1)
    k1 = float(sys.argv[1])
    k2 = float(sys.argv[2])

    try:
        with open('/home/user/signal.csv', 'r') as f:
            data = f.read().strip().split(',')
            A_exp = [float(x) for x in data]
    except Exception:
        # Fallback if agent didn't create signal.csv properly
        A_exp = rk4(0.5, 0.2, 0.1, 49)
        A_exp = [float(int(a * 255))/255.0 for a in A_exp]

    A_sim = rk4(k1, k2, 0.1, len(A_exp) - 1)

    LL = -0.5 * sum((sim - exp)**2 / 0.0025 for sim, exp in zip(A_sim, A_exp))
    print(LL)

if __name__ == '__main__':
    main()
EOF

    chmod +x /app/oracle_evaluate_ll

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user

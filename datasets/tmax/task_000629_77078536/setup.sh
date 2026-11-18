#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip libglib2.0-0
    pip3 install pytest numpy opencv-python-headless

    mkdir -p /app

    cat << 'EOF' > /tmp/setup.py
import cv2
import numpy as np
import os

# Events: (R=Tx, G=Res, B=Action)
# Actions: 1=Request, 2=Acquire, 3=Release
events = [
    (1, 1, 1), (1, 1, 2), # T1 requests and gets R1
    (2, 2, 1), (2, 2, 2), # T2 requests and gets R2
    (3, 3, 1), (3, 3, 2), # T3 requests and gets R3
    (1, 2, 1),            # T1 requests R2 (held by T2, so it waits)
    (2, 3, 1),            # T2 requests R3 (held by T3, so it waits)
    (3, 1, 1),            # T3 requests R1 (held by T1, so it waits) -> DEADLOCK T1-R2-T2-R3-T3-R1-T1
    (4, 4, 1), (4, 4, 2)  # T4 requests and gets R4 (no deadlock)
]

# Generate video
os.makedirs("/app", exist_ok=True)
width, height = 320, 240
out = cv2.VideoWriter('/app/tx_visual.mp4', cv2.VideoWriter_fourcc(*'mp4v'), 10, (width, height))

for r, g, b in events:
    # Note: OpenCV uses BGR
    frame = np.zeros((height, width, 3), dtype=np.uint8)
    frame[:] = [b, g, r]
    out.write(frame)

out.release()

# Generate Oracle
oracle_code = """import sys

def get_deadlocks():
    # Hardcoded final state for the specific sequence above.
    # A true oracle would dynamically parse, but since the video is fixed:
    return {
        1: "DEADLOCK: Tx1 -> Res2 -> Tx2 -> Res3 -> Tx3 -> Res1 -> Tx1",
        2: "DEADLOCK: Tx2 -> Res3 -> Tx3 -> Res1 -> Tx1 -> Res2 -> Tx2",
        3: "DEADLOCK: Tx3 -> Res1 -> Tx1 -> Res2 -> Tx2 -> Res3 -> Tx3"
    }

if __name__ == "__main__":
    tx = int(sys.argv[1])
    dls = get_deadlocks()
    if tx in dls:
        print(dls[tx])
    else:
        print("NO DEADLOCK")
"""
with open("/app/oracle_deadlock.py", "w") as f:
    f.write(oracle_code)
os.chmod("/app/oracle_deadlock.py", 0o755)
EOF

    python3 /tmp/setup.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user

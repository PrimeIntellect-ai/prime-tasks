#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg
    pip3 install --default-timeout=100 pytest

    mkdir -p /app
    # Create a 10-second black video at 30 fps (300 frames total)
    ffmpeg -f lavfi -i color=c=black:s=640x480:d=10 -r 30 -c:v libx264 /app/surveillance.mp4

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/api.py
import cv2
import math
import numpy as np
from fastapi import FastAPI, Header, HTTPException

app = FastAPI()

def calculate_naive_std(frames):
    if len(frames) < 2: return 0.0
    diffs = []
    for i in range(1, len(frames)):
        # Convert to float32 to cause precision issues on small diffs
        prev = frames[i-1].astype(np.float32)
        curr = frames[i].astype(np.float32)
        diff = np.abs(curr - prev)

        # Naive variance calculation: E[X^2] - E[X]^2
        # This is numerically unstable and can yield negative results
        mean_sq = np.mean(diff ** 2)
        sq_mean = np.mean(diff) ** 2
        variance = mean_sq - sq_mean

        # BUG: No assertion or clamping here. math.sqrt fails on negative variance.
        std_dev = math.sqrt(variance)
        diffs.append(std_dev)

    return sum(diffs) / len(diffs)

@app.get("/analyze")
def analyze_video(start_frame: int, end_frame: int, x_ops_token: str = Header(None)):
    if x_ops_token != "triage-2024":
        raise HTTPException(status_code=401, detail="Unauthorized")

    cap = cv2.VideoCapture("/app/surveillance.mp4")
    cap.set(cv2.CAP_PROP_POS_FRAMES, start_frame)

    frames = []
    for _ in range(end_frame - start_frame):
        ret, frame = cap.read()
        if not ret: break
        frames.append(cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY))
    cap.release()

    if not frames:
        return {"motion_index": 0.0}

    motion_index = calculate_naive_std(frames)
    return {"motion_index": motion_index}

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8080)
EOF

    chmod -R 777 /home/user
    chmod -R 777 /app

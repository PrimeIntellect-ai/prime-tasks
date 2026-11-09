#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg
    pip3 install pytest pandas numpy scipy

    mkdir -p /app

    # Generate a dummy traffic video
    ffmpeg -y -f lavfi -i testsrc=duration=10:size=320x240:rate=25 -pix_fmt yuv420p /app/traffic.mp4

    # Generate the reference report
    cat << 'EOF' > /tmp/gen_ref.py
import subprocess
import numpy as np
import pandas as pd
import scipy.stats

cmd = ['ffmpeg', '-i', '/app/traffic.mp4', '-f', 'image2pipe', '-pix_fmt', 'gray', '-vcodec', 'rawvideo', '-']
proc = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
raw_video = proc.stdout.read()

frames = np.frombuffer(raw_video, dtype=np.uint8).reshape(-1, 240, 320)
motion_scores = []
for i in range(len(frames)):
    if i == 0:
        motion_scores.append(0.0)
    else:
        diff = np.abs(frames[i].astype(np.int32) - frames[i-1].astype(np.int32))
        motion_scores.append(np.mean(diff))

windows = []
for i in range(0, len(motion_scores), 25):
    window = motion_scores[i:i+25]
    if len(window) == 25:
        avg_motion = np.mean(window)
        prior_c1 = 0.3
        prior_c0 = 0.7
        lik_c0 = scipy.stats.norm.pdf(avg_motion, loc=2.0, scale=1.5)
        lik_c1 = scipy.stats.norm.pdf(avg_motion, loc=15.0, scale=5.0)
        post_c1 = (lik_c1 * prior_c1) / (lik_c1 * prior_c1 + lik_c0 * prior_c0)
        windows.append({
            'window_id': i // 25,
            'avg_motion': avg_motion,
            'p_congested': round(post_c1, 4)
        })

df = pd.DataFrame(windows)
df.to_csv('/app/reference_report.csv', index=False)
EOF

    python3 /tmp/gen_ref.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app

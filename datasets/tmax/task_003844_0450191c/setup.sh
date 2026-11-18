#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip libglib2.0-0 libgl1-mesa-glx
    pip3 install pytest pandas numpy opencv-python-headless scipy

    mkdir -p /app

    cat << 'EOF' > /app/generate_assets.py
import cv2
import numpy as np
import pandas as pd

# Generate Video
out = cv2.VideoWriter('/app/experiment_video.mp4', cv2.VideoWriter_fourcc(*'mp4v'), 10, (100, 100), isColor=False)
for i in range(150):
    frame = np.zeros((100, 100), dtype=np.uint8)
    val = int(127 + 127 * np.sin(i / 10.0))
    frame[0:50, 0:50] = val
    out.write(frame)
out.release()

# Generate Telemetry CSV
times = np.arange(0, 15.0, 0.1)
vals = np.random.rand(len(times)) * 255
df = pd.DataFrame({'time': times, 'telemetry_val': vals})
df.to_csv('/app/telemetry.csv', index=False)
EOF

    python3 /app/generate_assets.py

    cat << 'EOF' > /app/oracle_fusion_pipeline
#!/usr/bin/env python3
import argparse
import pandas as pd
import numpy as np
import json

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--video_in')
    parser.add_argument('--telemetry_in')
    parser.add_argument('--out_csv')
    parser.add_argument('--out_log')
    parser.add_argument('--window', type=int)
    parser.add_argument('--threshold', type=float)
    args = parser.parse_args()

    df_vid = pd.read_csv(args.video_in)
    df_tel = pd.read_csv(args.telemetry_in)

    df_vid['time'] = df_vid['time'].round(1)
    df_tel['time'] = df_tel['time'].round(1)

    df = pd.merge(df_vid, df_tel, on='time', how='outer')
    df = df.sort_values('time').reset_index(drop=True)

    df['telemetry_val'] = df['telemetry_val'].ffill().bfill()
    df['video_val'] = df['video_val'].interpolate(method='linear')

    w = args.window
    half_w = w // 2

    rolling_med = df['video_val'].rolling(window=w, center=True).median()

    outliers_replaced = 0
    for i in range(len(df)):
        if i < half_w or i >= len(df) - half_w:
            continue
        val = df.loc[i, 'video_val']
        med = rolling_med.iloc[i]
        if pd.notna(val) and pd.notna(med) and abs(val - med) > args.threshold:
            df.loc[i, 'video_val'] = med
            outliers_replaced += 1

    corr = df['video_val'].corr(df['telemetry_val'])

    df['time'] = df['time'].map(lambda x: f"{x:.4f}")
    df['video_val'] = df['video_val'].map(lambda x: f"{x:.4f}")
    df['telemetry_val'] = df['telemetry_val'].map(lambda x: f"{x:.4f}")

    df.to_csv(args.out_csv, index=False)

    log_data = {
        "correlation": round(corr, 4),
        "outliers_replaced": outliers_replaced
    }
    with open(args.out_log, 'w') as f:
        json.dump(log_data, f)

if __name__ == '__main__':
    main()
EOF

    chmod +x /app/oracle_fusion_pipeline

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user

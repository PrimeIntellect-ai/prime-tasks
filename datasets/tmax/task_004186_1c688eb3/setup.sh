#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg
    pip3 install pytest numpy

    mkdir -p /app

    cat << 'EOF' > /app/oracle_video_etl.py
import sys
import subprocess
import numpy as np

def run_oracle(video_path):
    cmd = [
        'ffmpeg', '-i', video_path, '-vf', 'fps=1', 
        '-f', 'image2pipe', '-vcodec', 'rawvideo', '-pix_fmt', 'gray', '-'
    ]
    proc = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)

    # Assume 320x240 for testsrc synthetic videos, but we should parse dynamically ideally.
    # For bit-exact oracle on testsrc, we will read until EOF.
    # We will use ffprobe to get exact dimensions to be safe.
    probe_cmd = ['ffprobe', '-v', 'error', '-select_streams', 'v:0', '-show_entries', 'stream=width,height', '-of', 'csv=s=x:p=0', video_path]
    dim = subprocess.check_output(probe_cmd).decode('utf-8').strip().split('x')
    w, h = int(dim[0]), int(dim[1])
    frame_size = w * h

    frames = []
    while True:
        raw = proc.stdout.read(frame_size)
        if not raw or len(raw) < frame_size:
            break
        arr = np.frombuffer(raw, dtype=np.uint8)
        frames.append(np.mean(arr) / 255.0)

    for i in range(0, len(frames), 5):
        window = frames[i:i+5]
        avg = sum(window) / len(window)
        start = i
        end = i + 4
        print(f"INSERT INTO video_metrics (window_start, window_end, avg_brightness) VALUES ({start}, {end}, {avg:.3f}) ON CONFLICT (window_start) DO UPDATE SET avg_brightness = EXCLUDED.avg_brightness;")

if __name__ == '__main__':
    run_oracle(sys.argv[1])
EOF

    ffmpeg -f lavfi -i testsrc=duration=15:size=320x240:rate=24 -c:v libx264 /app/sample_stream.mp4

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user

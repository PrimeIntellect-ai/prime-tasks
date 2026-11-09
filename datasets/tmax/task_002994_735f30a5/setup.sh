#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg
    pip3 install pytest pandas numpy Pillow

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user/videophysics
    mkdir -p /app

    # Create main.py
    cat << 'EOF' > /home/user/videophysics/main.py
import os
import subprocess
import concurrent.futures
from math_utils import calculate_entropy
from PIL import Image

VIDEO_PATH = "/app/experiment.mp4"
FRAMES_DIR = "/tmp/frames"
OUTPUT_CSV = "/home/user/final_output.csv"

def extract_frames():
    os.makedirs(FRAMES_DIR, exist_ok=True)
    subprocess.run(["ffmpeg", "-i", VIDEO_PATH, "-vf", "format=gray", f"{FRAMES_DIR}/frame_%04d.png"], check=True)

def process_frame(frame_file):
    filepath = os.path.join(FRAMES_DIR, frame_file)
    frame_idx = int(frame_file.split('_')[1].split('.')[0])

    img = Image.open(filepath)
    histogram = img.histogram()
    total_pixels = sum(histogram)
    probabilities = [count / total_pixels for count in histogram]

    entropy = calculate_entropy(probabilities)

    # Bug 1: Race condition writing to file
    with open(OUTPUT_CSV, "a") as f:
        f.write(f"{frame_idx},{entropy}\n")

def main():
    if not os.path.exists(FRAMES_DIR):
        extract_frames()

    with open(OUTPUT_CSV, "w") as f:
        f.write("frame_index,entropy\n")

    frames = [f for f in os.listdir(FRAMES_DIR) if f.endswith('.png')]

    # Threads cause interleaved writes and unhandled exceptions crash threads silently
    with concurrent.futures.ThreadPoolExecutor(max_workers=8) as executor:
        executor.map(process_frame, frames)

if __name__ == "__main__":
    main()
EOF

    # Create math_utils.py
    cat << 'EOF' > /home/user/videophysics/math_utils.py
import math

def calculate_entropy(probabilities):
    entropy = 0.0
    for p in probabilities:
        # Bug 2: Numerical instability when p == 0
        entropy -= p * math.log(p, 2)
    return entropy
EOF

    # Generate video and ground truth
    cat << 'EOF' > /tmp/generate_data.py
import os
import subprocess
import random
from PIL import Image
import math

os.makedirs('/tmp/gen_frames', exist_ok=True)
random.seed(42)

for i in range(1, 151):
    if 45 <= i <= 50:
        img = Image.new('L', (100, 100), color=0)
    else:
        data = [random.randint(0, 255) for _ in range(10000)]
        img = Image.new('L', (100, 100))
        img.putdata(data)
    img.save(f'/tmp/gen_frames/frame_{i:04d}.png')

subprocess.run(["ffmpeg", "-y", "-framerate", "30", "-i", "/tmp/gen_frames/frame_%04d.png", "-c:v", "libx264", "-crf", "0", "-pix_fmt", "yuv420p", "/app/experiment.mp4"], check=True)

os.makedirs('/tmp/frames_gt', exist_ok=True)
subprocess.run(["ffmpeg", "-i", "/app/experiment.mp4", "-vf", "format=gray", "/tmp/frames_gt/frame_%04d.png"], check=True)

truth = []
for i in range(1, 151):
    img = Image.open(f'/tmp/frames_gt/frame_{i:04d}.png')
    histogram = img.histogram()
    total = sum(histogram)
    probs = [c / total for c in histogram if c > 0]
    ent = -sum(p * math.log(p, 2) for p in probs)
    truth.append((i, ent))

with open('/tmp/ground_truth.csv', 'w') as f:
    f.write("frame_index,entropy\n")
    for i, ent in truth:
        f.write(f"{i},{ent}\n")
EOF

    python3 /tmp/generate_data.py
    rm -rf /tmp/gen_frames /tmp/frames_gt /tmp/generate_data.py

    chown -R user:user /home/user
    chmod -R 777 /home/user
    chmod -R 777 /app

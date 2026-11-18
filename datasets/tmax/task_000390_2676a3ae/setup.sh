#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip python3-opencv python3-numpy ffmpeg
    pip3 install pytest

    cat << 'EOF' > /tmp/setup.py
import os
import cv2
import numpy as np

# 1. Create the video
os.makedirs('/app', exist_ok=True)
video_path = '/app/signal.mp4'

truth_text = "OPTICAL_SYNC_ESTABLISHED: Hello minimal container environment! The state machine works."
bits = []

for char in truth_text:
    # Append Start bit (Red)
    bits.append('R')
    # Append 8 bits
    bin_str = format(ord(char), '08b')
    for b in bin_str:
        bits.append('G' if b == '0' else 'B')

fps = 30
width, height = 100, 100
fourcc = cv2.VideoWriter_fourcc(*'mp4v')
out = cv2.VideoWriter(video_path, fourcc, fps, (width, height))

# Colors in BGR for OpenCV
colors = {
    'R': (0, 0, 255),
    'G': (0, 255, 0),
    'B': (255, 0, 0)
}

# Add some initial black frames
for _ in range(5):
    out.write(np.zeros((height, width, 3), dtype=np.uint8))

for b in bits:
    frame = np.zeros((height, width, 3), dtype=np.uint8)
    # Fill top-left 20x20 block to ensure the x=5,y=5 pixel is covered
    frame[0:20, 0:20] = colors[b]
    # Write 2 frames per bit to simulate frame duplication requiring deduplication logic
    out.write(frame)
    out.write(frame)

# Add ending black frames
for _ in range(5):
    out.write(np.zeros((height, width, 3), dtype=np.uint8))

out.release()

# 2. Create the legacy codebase
code_dir = '/home/user/opti-decode'
os.makedirs(code_dir, exist_ok=True)

with open(os.path.join(code_dir, 'registry.py'), 'w') as f:
    f.write("""
from decoder import StateMachine

PLUGIN_REGISTRY = {}

def register(name):
    def decorator(cls):
        PLUGIN_REGISTRY[name] = cls
        return cls
    return decorator
""")

with open(os.path.join(code_dir, 'decoder.py'), 'w') as f:
    f.write("""
from registry import register

@register('optical_decoder')
class StateMachine:
    def __init__(self):
        self.state = 'WAIT'
        self.current_bits = ""
        self.last_color = None
        self.decoded_chars = []

    def process_pixel(self, r, g, b):
        # Determine color
        color = None
        if r > 200 and g < 50 and b < 50: color = 'R'
        elif g > 200 and r < 50 and b < 50: color = 'G'
        elif b > 200 and r < 50 and g < 50: color = 'B'
        else: color = 'BLK'

        # Deduplicate continuous colors
        if color == self.last_color:
            return
        self.last_color = color

        # Buggy state machine logic
        if color == 'R':
            if len(self.current_bits) == 8:
                self.decoded_chars.append(chr(int(self.current_bits, 2)))
            self.current_bits = ""
        elif color == 'G':
            self.current_bits += '0'
        elif color == 'B':
            self.current_bits += '1'

    def finalize(self):
        # Missing the flush of the last byte!
        return "".join(self.decoded_chars)
""")

with open(os.path.join(code_dir, 'cli.py'), 'w') as f:
    f.write("""
import os
import subprocess
from registry import PLUGIN_REGISTRY

def extract_frames(video_path, out_dir):
    subprocess.run(['ffmpeg', '-i', video_path, '-vf', 'fps=30', f'{out_dir}/%04d.png'], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

# main logic omitted for brevity, agent has to fix import and implement image reading
""")
EOF

    python3 /tmp/setup.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user

#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg
    pip3 install pytest numpy h5py opencv-python-headless Pillow

    mkdir -p /app/corpora/train/clean
    mkdir -p /app/corpora/train/evil
    mkdir -p /app/corpora/test/clean
    mkdir -p /app/corpora/test/evil

    python3 -c "
import cv2
import numpy as np
import os

# Create video
out = cv2.VideoWriter('/app/dashcam_raw.mp4', cv2.VideoWriter_fourcc(*'mp4v'), 1, (1280, 720))
for i in range(60):
    img = np.zeros((720, 1280, 3), dtype=np.uint8)
    if i in [14, 27, 42, 51]:
        img[10:20, 10:20] = [0, 0, 255] # OpenCV uses BGR
    out.write(img)
out.release()

# Create corpora
def create_images(dir_path, count, evil=False):
    img = np.zeros((100, 100, 3), dtype=np.uint8)
    if evil:
        img[10:20, 10:20] = [0, 0, 255]
    for i in range(count):
        cv2.imwrite(os.path.join(dir_path, f'{i}.png'), img)

create_images('/app/corpora/train/clean', 50, False)
create_images('/app/corpora/train/evil', 50, True)
create_images('/app/corpora/test/clean', 200, False)
create_images('/app/corpora/test/evil', 200, True)
"

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user

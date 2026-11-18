#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg libsm6 libxext6 libgl1
    pip3 install pytest opencv-python numpy

    mkdir -p /app/corpora/clean /app/corpora/evil

    # Generate video and zip files using Python
    python3 -c '
import cv2
import numpy as np
import zipfile
import os

# 1. Generate video
out = cv2.VideoWriter("/app/test_run.mp4", cv2.VideoWriter_fourcc(*"mp4v"), 30, (100, 100))
for i in range(60):
    frame = np.zeros((100, 100, 3), dtype=np.uint8)
    if i == 42:
        frame[:] = (255, 0, 0) # BGR
    out.write(frame)
out.release()

# 2. Generate zip files
valid_log = "[EVENT]\nStatus: SUCCESS\nSync-Frame: 42\n"
wrong_frame_log = "[EVENT]\nStatus: SUCCESS\nSync-Frame: 15\n"
malformed_log = "[EVENT]\nSync-Frame: 42\n"

def create_zip(path, files):
    with zipfile.ZipFile(path, "w") as zf:
        for arcname, content in files.items():
            zf.writestr(arcname, content)

create_zip("/app/corpora/clean/clean1.zip", {
    "build.log": valid_log,
    "safe_file.txt": "hello"
})

create_zip("/app/corpora/clean/clean2.zip", {
    "build.log": valid_log,
    "nested/dir/file.txt": "nested"
})

create_zip("/app/corpora/evil/evil_zipslip.zip", {
    "build.log": valid_log,
    "../../etc/passwd": "root:x:0:0:"
})

create_zip("/app/corpora/evil/evil_absolute.zip", {
    "build.log": valid_log,
    "/var/tmp/hacked.txt": "hacked"
})

create_zip("/app/corpora/evil/evil_wrongframe.zip", {
    "build.log": wrong_frame_log,
    "safe_file.txt": "hello"
})

create_zip("/app/corpora/evil/evil_missinglog.zip", {
    "safe_file.txt": "hello"
})

create_zip("/app/corpora/evil/evil_malformedlog.zip", {
    "build.log": malformed_log,
    "safe_file.txt": "hello"
})
'

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user

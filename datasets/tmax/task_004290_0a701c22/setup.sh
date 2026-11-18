#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg zip bzip2 tar python3-opencv python3-numpy
    pip3 install pytest

    # Generate video
    mkdir -p /app
    python3 -c "
import cv2
import numpy as np
out = cv2.VideoWriter('/app/disk_monitor.mp4', cv2.VideoWriter_fourcc(*'mp4v'), 30, (320, 240))
for i in range(300):
    frame = np.zeros((240, 320, 3), dtype=np.uint8)
    if (50 <= i <= 75) or (180 <= i <= 220):
        frame[0:10, 0:10] = (0, 0, 255)
    out.write(frame)
out.release()
"

    # Generate nested archive
    mkdir -p /tmp/archive_setup
    cd /tmp/archive_setup
    echo "ELOOP: Too many levels of symbolic links: /home/user/data/loop1" > error.log
    echo "ELOOP: Too many levels of symbolic links: /home/user/data/sub/loop2" >> error.log
    tar -cjf inner.tar.bz2 error.log
    zip middle.zip inner.tar.bz2
    mkdir -p /home/user/backups
    tar -czf /home/user/backups/incident_logs.tar.gz middle.zip

    # Generate data directory
    mkdir -p /home/user/data/sub
    dd if=/dev/urandom of=/home/user/data/file1.bin bs=1M count=5
    cp /home/user/data/file1.bin /home/user/data/file2.bin
    cp /home/user/data/file1.bin /home/user/data/file3.bin
    dd if=/dev/urandom of=/home/user/data/sub/file4.bin bs=1M count=5
    cp /home/user/data/sub/file4.bin /home/user/data/sub/file5.bin

    ln -s /home/user/data/loop1 /home/user/data/loop1
    ln -s /home/user/data/sub/loop2 /home/user/data/sub/loop2

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app

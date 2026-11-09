#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg
    pip3 install pytest

    mkdir -p /app
    ffmpeg -y -f lavfi -i color=c=red:s=320x240:d=1 \
        -f lavfi -i color=c=black:s=320x240:d=0.5 \
        -f lavfi -i color=c=green:s=320x240:d=1.5 \
        -filter_complex "[0:v][1:v][2:v]concat=n=3:v=1:a=0[outv]" \
        -map "[outv]" -r 10 /app/disk_monitor.mp4

    mkdir -p /home/user/storage_dump/dir_a/dir_b
    mkdir -p /home/user/storage_dump/dir_c

    ln -s /home/user/storage_dump/dir_a /home/user/storage_dump/dir_a/dir_b/loop_link
    ln -s /home/user/storage_dump/dir_a/dir_b /home/user/storage_dump/dir_c/loop_link2

    python3 -c '
with open("/home/user/storage_dump/file1.dat", "wb") as f: f.write(b"\xDE\xAD\xBE\xEFsomeotherdata")
with open("/home/user/storage_dump/dir_a/file2.dat", "wb") as f: f.write(b"\xCA\xFE\xBA\xBEdata2")
with open("/home/user/storage_dump/dir_a/dir_b/file3.dat", "wb") as f: f.write(b"\x00\x11\x22\x33data3")
'

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user

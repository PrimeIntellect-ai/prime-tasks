#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg
    pip3 install pytest

    # Create directories
    mkdir -p /app/corpora/clean
    mkdir -p /app/corpora/evil

    # Generate video
    ffmpeg -f lavfi -i testsrc=duration=15:size=320x240:rate=1 -c:v libx264 /app/camera_01.mp4

    # Generate clean tarballs
    mkdir -p /tmp/clean_tmp
    for i in {1..5}; do
        echo "clean $i" > /tmp/clean_tmp/file_$i.txt
        tar -czf /app/corpora/clean/clean$i.tar.gz -C /tmp/clean_tmp file_$i.txt
    done

    # Generate evil tarballs
    # 1. Absolute symlink
    mkdir -p /tmp/evil1
    ln -s /etc/passwd /tmp/evil1/link
    tar -czf /app/corpora/evil/evil1.tar.gz -C /tmp/evil1 link

    # 2. Relative symlink
    mkdir -p /tmp/evil2
    ln -s ../../../etc/passwd /tmp/evil2/link
    tar -czf /app/corpora/evil/evil2.tar.gz -C /tmp/evil2 link

    # 3. File named lock
    mkdir -p /tmp/evil3
    touch /tmp/evil3/lock
    tar -czf /app/corpora/evil/evil3.tar.gz -C /tmp/evil3 lock

    # 4. Directory named .lock
    mkdir -p /tmp/evil4/.lock
    touch /tmp/evil4/.lock/file
    tar -czf /app/corpora/evil/evil4.tar.gz -C /tmp/evil4 .lock

    # 5. Malformed gzip
    head -c 100 /dev/urandom > /app/corpora/evil/evil5.tar.gz

    # Cleanup tmp
    rm -rf /tmp/clean_tmp /tmp/evil1 /tmp/evil2 /tmp/evil3 /tmp/evil4

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user

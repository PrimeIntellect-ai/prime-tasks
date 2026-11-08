#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg
    pip3 install pytest

    # Create directories
    mkdir -p /home/user/dataset/frames
    mkdir -p /app/corpora/clean/subdir
    mkdir -p /app/corpora/evil/subdir

    # Generate synthetic video
    ffmpeg -f lavfi -i testsrc=duration=12:size=640x480:rate=30 -c:v libx264 /app/experiment.mp4

    # Setup Clean Corpus
    touch /app/corpora/clean/file1.txt
    touch /app/corpora/clean/subdir/file2.txt
    ln -s subdir/file2.txt /app/corpora/clean/safe_link_relative
    ln -s /app/corpora/clean/file1.txt /app/corpora/clean/subdir/safe_link_absolute

    # Setup Evil Corpus
    touch /app/corpora/evil/valid_file.txt
    # Loop 1: Direct self-reference
    ln -s loop1 /app/corpora/evil/loop1
    # Loop 2: Mutual reference
    ln -s loop3 /app/corpora/evil/loop2
    ln -s loop2 /app/corpora/evil/loop3
    # Loop 3: Directory loop
    mkdir -p /app/corpora/evil/loop_dir
    ln -s ../loop_dir /app/corpora/evil/loop_dir/cyclic_sub
    # Escape: Links to /etc/passwd
    ln -s /etc/passwd /app/corpora/evil/escape_root
    # Escape: Links to parent dir escaping the base path
    ln -s ../../ /app/corpora/evil/escape_relative

    chmod -R 755 /app/corpora

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user

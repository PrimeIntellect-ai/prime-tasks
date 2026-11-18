#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang-go espeak ffmpeg curl
    pip3 install pytest

    # Create the audio file
    mkdir -p /app
    espeak -w /app/artifact_memo.wav "Attention team, the repository migration is complete. Please note that the new master server IP is 10.42.15.99 and should be updated in all clients."

    # Create repository structure
    mkdir -p /home/user/repo_data/v1/bin
    mkdir -p /home/user/repo_data/v2/bin

    # Create regular files
    dd if=/dev/urandom of=/home/user/repo_data/v1/bin/artifact-a.bin bs=1K count=1
    dd if=/dev/urandom of=/home/user/repo_data/v1/bin/artifact-b.bin bs=1K count=1
    dd if=/dev/urandom of=/home/user/repo_data/v2/bin/artifact-c.bin bs=1K count=1
    dd if=/dev/urandom of=/home/user/repo_data/v2/bin/artifact-d.bin bs=1K count=1
    dd if=/dev/urandom of=/home/user/repo_data/readme.txt bs=100 count=1

    # Create valid symlink
    ln -s /home/user/repo_data/v2/bin/artifact-c.bin /home/user/repo_data/latest-c

    # Create infinite loop symlink
    ln -s /home/user/repo_data /home/user/repo_data/v1/loop_dir

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user

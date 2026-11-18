#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip espeak gcc
    pip3 install pytest

    # Create directories and files
    mkdir -p /home/user/live_data/folder1
    echo "Important data 1" > /home/user/live_data/file1.txt
    echo "Important data 2" > /home/user/live_data/folder1/file2.txt

    # Create the symlink loop
    ln -s /home/user/live_data /home/user/live_data/folder1/loop_link

    # Generate the audio directive
    mkdir -p /app
    espeak -w /app/directive.wav "The secret authentication token is gamma ray burst. Ensure the network transmission uses a chunk size of 1024 bytes."

    # Create user
    useradd -m -s /bin/bash user || true

    # Set permissions
    chown -R user:user /home/user/live_data
    chmod -R 777 /home/user

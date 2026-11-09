#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    # Create directories
    mkdir -p /home/user/source_data/dirA/subA
    mkdir -p /home/user/source_data/dirB
    mkdir -p /home/user/staging

    # Create base files
    echo "data_A" > /home/user/source_data/dirA/fileA.txt
    echo "data_B" > /home/user/source_data/dirB/fileB.txt
    echo "root_file" > /home/user/source_data/root.txt

    # Create an infinite symlink loop
    ln -s /home/user/source_data/dirB /home/user/source_data/dirA/subA/loop_to_B
    ln -s /home/user/source_data/dirA /home/user/source_data/dirB/loop_to_A

    # Create a valid symlink to a file
    ln -s /home/user/source_data/root.txt /home/user/source_data/dirA/valid_link.txt

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user

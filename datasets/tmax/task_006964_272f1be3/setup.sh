#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    # Create the user
    useradd -m -s /bin/bash user || true

    # Setup project directories
    mkdir -p /home/user/project_data/src
    mkdir -p /home/user/project_data/assets
    mkdir -p /home/user/project_data/links

    # Create regular files
    echo "Hello World" > /home/user/project_data/src/hello.txt
    echo "Configuration Data" > /home/user/project_data/src/config.txt
    echo "Fixed seed binary" > /home/user/project_data/assets/blob.bin

    # Create valid symlinks
    ln -s ../src/hello.txt /home/user/project_data/links/hello_link.txt
    ln -s ../assets/blob.bin /home/user/project_data/links/blob_link.bin

    # Create circular symlinks
    ln -s loop_b /home/user/project_data/links/loop_a
    ln -s loop_c /home/user/project_data/links/loop_b
    ln -s loop_a /home/user/project_data/links/loop_c

    # Another self-loop
    ln -s self_loop /home/user/project_data/links/self_loop

    # Ensure correct permissions
    chmod -R 777 /home/user

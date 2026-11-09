#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install --default-timeout=100 pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/source_data/dirA/dirB
    mkdir -p /home/user/source_data/dirC

    echo "file1 contents" > /home/user/source_data/file1.txt
    echo "file2 contents" > /home/user/source_data/dirA/file2.txt
    echo "file3 contents" > /home/user/source_data/dirC/file3.txt

    # Create safe symlinks
    ln -s /home/user/source_data/dirA/file2.txt /home/user/source_data/dirA/dirB/safe_link1.txt
    cd /home/user/source_data/dirC && ln -s ../file1.txt safe_link2.txt

    # Create an external file to act as a target for unsafe links
    echo "secret" > /home/user/secret.txt

    # Create unsafe symlinks
    ln -s /etc/passwd /home/user/source_data/unsafe_link1.txt
    cd /home/user/source_data/dirA && ln -s ../../secret.txt unsafe_link2.txt

    chmod -R 777 /home/user

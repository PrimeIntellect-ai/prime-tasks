#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make tar coreutils
    pip3 install pytest

    mkdir -p /home/user/legacy_archives
    mkdir -p /home/user/source_project/project/dirA
    mkdir -p /home/user/source_project/project/dirB
    mkdir -p /home/user/source_project/project/dirC

    # Create some files
    echo -n "Hello World" > /home/user/source_project/project/file1.txt
    echo -n "Testing 123" > /home/user/source_project/project/dirA/file2.txt

    # Create symlinks
    # 1. Valid symlink to a file
    ln -s ../file1.txt /home/user/source_project/project/dirB/link_to_file1.txt
    # 2. Circular symlink (infinite loop)
    ln -s ../dirC /home/user/source_project/project/dirC/loop

    # Create the archive and split it
    cd /home/user/source_project
    tar -czf /home/user/legacy_archives/backup.tar.gz project
    cd /home/user/legacy_archives
    # Split into smaller chunks so that at least part-aa and part-ab are created
    split -b 100 backup.tar.gz backup.tar.gz.part-
    rm backup.tar.gz
    rm -rf /home/user/source_project
    mkdir -p /home/user/extracted_project

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user

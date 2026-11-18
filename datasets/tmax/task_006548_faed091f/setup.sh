#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user/docs_root/dir1
    mkdir -p /home/user/docs_root/dir2
    mkdir -p /home/user/docs_root/dir3

    echo "\n\n# Welcome to docs" > /home/user/docs_root/intro.md
    touch -m -d "2024-01-05 12:00:00" /home/user/docs_root/intro.md

    echo "Old notes\nIgnore me" > /home/user/docs_root/old_notes.txt
    touch -m -d "2023-12-01 12:00:00" /home/user/docs_root/old_notes.txt

    echo "# Setup Instructions\nStep 1" > /home/user/docs_root/dir1/setup.md
    touch -m -d "2024-01-10 12:00:00" /home/user/docs_root/dir1/setup.md

    echo "# Configuration\nPort 8080" > /home/user/docs_root/dir2/config.md
    touch -m -d "2024-01-15 12:00:00" /home/user/docs_root/dir2/config.md

    echo "Binary data here" > /home/user/docs_root/dir3/data.bin
    touch -m -d "2024-01-20 12:00:00" /home/user/docs_root/dir3/data.bin

    ln -s /home/user/docs_root/dir2 /home/user/docs_root/dir1/link_to_2
    ln -s /home/user/docs_root/dir1 /home/user/docs_root/dir2/link_to_1
    ln -s /home/user/docs_root/intro.md /home/user/docs_root/dir3/intro_link.md

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user

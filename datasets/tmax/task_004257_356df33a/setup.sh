#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make tar gzip
    pip3 install pytest

    mkdir -p /home/user/docs_raw
    mkdir -p /home/user/docs_flat

    cat << 'EOF' > /home/user/docs_raw/intro.md
# Introduction
DOC_ID: 001
Welcome to the documentation.
EOF

    cat << 'EOF' > /home/user/docs_raw/setup.md
# Setup Guide
DOC_ID: 005
How to install.
EOF

    cat << 'EOF' > /home/user/docs_raw/legacy.md
# Old stuff
Just some text without an ID.
EOF

    # Create symlinks
    ln -s /home/user/docs_raw/intro.md /home/user/docs_raw/start_here.md
    # Create broken link
    ln -s /home/user/docs_raw/missing.md /home/user/docs_raw/broken_link.md
    # Create an infinite loop
    ln -s /home/user/docs_raw/loop2.md /home/user/docs_raw/loop1.md
    ln -s /home/user/docs_raw/loop3.md /home/user/docs_raw/loop2.md
    ln -s /home/user/docs_raw/loop1.md /home/user/docs_raw/loop3.md

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user/docs_raw /home/user/docs_flat
    chmod -R 777 /home/user

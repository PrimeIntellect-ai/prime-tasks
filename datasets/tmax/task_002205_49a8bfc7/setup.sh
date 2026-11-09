#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tar gzip coreutils grep sed gawk
    pip3 install pytest

    # Create directories
    mkdir -p /home/user/data/docs
    mkdir -p /home/user/data/images
    mkdir -p /home/user/data/loop_a
    mkdir -p /home/user/data/loop_b

    # Create normal files
    echo "doc1" > /home/user/data/docs/file1.txt
    echo "doc2" > /home/user/data/docs/file2.txt
    echo "img1" > /home/user/data/images/pic.jpg

    # Create symlink loops
    ln -s /home/user/data/loop_a /home/user/data/loop_a/link_back
    ln -s /home/user/data/loop_b /home/user/data/loop_b/link_back

    # Create the multi-line log file
    cat << 'EOF' > /home/user/backup.log
--BEGIN--
Target: /home/user/data/docs
Status: OK
Details: Successfully archived 2 files
--END--
--BEGIN--
Target: /home/user/data/loop_a
Status: ERROR
Details: Fatal: Symlink loop detected during traversal
--END--
--BEGIN--
Target: /home/user/data/images
Status: OK
Details: Successfully archived 1 files
--END--
--BEGIN--
Target: /home/user/data/loop_b
Status: ERROR
Details: Fatal: Symlink loop encountered! Aborting target.
--END--
--BEGIN--
Target: /home/user/data/broken_link
Status: ERROR
Details: File not found
--END--
EOF

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user

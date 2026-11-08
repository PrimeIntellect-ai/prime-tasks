#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip zip
    pip3 install pytest

    # Create workspace for setup
    mkdir -p /home/user/setup_workspace/docs/sub
    mkdir -p /home/user/setup_workspace/docs/api

    # File 1: Needs update
    echo "# Welcome to OldCorp." > /home/user/setup_workspace/docs/file1.md
    echo "Here we use [DEPRECATED_MACRO] for formatting." >> /home/user/setup_workspace/docs/file1.md

    # File 2: Contains OldCorp but no macro, should NOT be updated
    echo "# OldCorp History" > /home/user/setup_workspace/docs/file2.md
    echo "OldCorp was founded long ago." >> /home/user/setup_workspace/docs/file2.md

    # File 3: Needs update, in subdir
    echo "Using [DEPRECATED_MACRO] in OldCorp API." > /home/user/setup_workspace/docs/sub/file3.md

    # File 4: Wrong extension, should not be updated even if it contains the macro
    echo "This text file has [DEPRECATED_MACRO] and OldCorp" > /home/user/setup_workspace/docs/file4.txt

    # Create archives
    cd /home/user/setup_workspace
    tar -czvf docs_archive.tar.gz docs/
    zip legacy_docs.zip docs_archive.tar.gz
    mv legacy_docs.zip /home/user/
    cd /home/user
    rm -rf /home/user/setup_workspace

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user

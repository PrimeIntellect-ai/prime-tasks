#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc coreutils findutils
    pip3 install pytest

    mkdir -p /home/user/docs_repo/v1
    mkdir -p /home/user/docs_repo/v2
    mkdir -p /home/user/docs_repo/assets

    echo "Welcome to version 1." > /home/user/docs_repo/v1/intro.md
    echo "Setup instructions go here." > /home/user/docs_repo/v1/setup.md
    echo "Draft notes for setup" > /home/user/docs_repo/v1/notes.draft

    echo "Welcome to version 1." > /home/user/docs_repo/v2/intro.md
    echo "Advanced configurations." > /home/user/docs_repo/v2/advanced.md
    echo "Draft notes for advanced" > /home/user/docs_repo/v2/advanced.draft

    echo "FAKE_PNG_DATA" > /home/user/docs_repo/assets/logo.png

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user

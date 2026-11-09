#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip zip unzip tar gzip coreutils
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/incoming_docs
    cd /home/user/incoming_docs

    # Create valid tar.gz 1
    mkdir -p docset1
    echo "Old doc" > docset1/old.md
    touch -d "2021-05-05 12:00:00" docset1/old.md
    echo "New doc" > docset1/new1.md
    touch -d "2023-05-05 12:00:00" docset1/new1.md
    tar -czf valid1.tar.gz docset1
    rm -rf docset1

    # Create valid tar.gz 2
    mkdir -p docset2
    echo "Another new doc" > docset2/new2.md
    touch -d "2024-01-01 10:00:00" docset2/new2.md
    tar -czf valid2.tar.gz docset2
    rm -rf docset2

    # Create valid zip 1
    mkdir -p docset3
    echo "Old doc zip" > docset3/old2.md
    touch -d "2022-12-31 23:59:59" docset3/old2.md
    echo "New doc zip" > docset3/new3.md
    touch -d "2023-01-01 00:00:01" docset3/new3.md
    zip -q -r valid3.zip docset3
    rm -rf docset3

    # Create corrupted tar.gz
    echo "This is not a tar archive" > corrupt1.tar.gz
    dd if=/dev/urandom of=corrupt2.tar.gz bs=1024 count=1 2>/dev/null

    # Create corrupted zip
    echo "This is not a zip archive" > corrupt3.zip

    chmod -R 777 /home/user

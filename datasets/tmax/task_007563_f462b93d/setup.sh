#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang zip unzip tar
    pip3 install pytest

    mkdir -p /home/user/legacy_docs/folder1
    mkdir -p /home/user/legacy_docs/folder2/sub

    # Create files with ISO-8859-1 encoding using printf
    printf 'Caf\xe9 and R\xe9sum\xe9\n' > "/home/user/legacy_docs/folder1/doc 1.txt"
    printf 'Jalape\xf1o peppers\n' > "/home/user/legacy_docs/folder2/sub/doc 2.txt"

    # Create the tar archive
    cd /home/user/legacy_docs
    tar -cf /home/user/legacy_archive.tar .
    cd /home/user
    rm -rf /home/user/legacy_docs

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user

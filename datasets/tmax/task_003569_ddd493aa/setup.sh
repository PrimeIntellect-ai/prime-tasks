#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang zip gzip
    pip3 install pytest

    mkdir -p /home/user/project_files/subdir
    echo "Just a normal file" > /home/user/project_files/normal.txt
    echo "Another text" > /home/user/project_files/subdir/data.bin

    echo "compressed data" | gzip > /home/user/project_files/hidden_gzip.dat

    echo "zip content" > /tmp/temp.txt
    cd /tmp && zip archive.zip temp.txt
    mv /tmp/archive.zip /home/user/project_files/subdir/fake_document.pdf

    echo "more zip" > /tmp/temp2.txt
    cd /tmp && zip archive2.zip temp2.txt
    mv /tmp/archive2.zip /home/user/project_files/no_extension_file

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user

#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip zip tar coreutils
    pip3 install pytest

    mkdir -p /home/user
    cd /home/user

    # Create source files for valid1.zip
    mkdir -p /tmp/zip1
    echo "Experiment 1: [OBSOLETE_TAG] recorded at dawn." | iconv -f UTF-8 -t WINDOWS-1252 > /tmp/zip1/alpha_data.txt
    echo "[OBSOLETE_TAG] is no longer used. [OBSOLETE_TAG]" | iconv -f UTF-8 -t WINDOWS-1252 > /tmp/zip1/beta_data.txt
    cd /tmp/zip1 && zip /tmp/valid1.zip *.txt

    # Create source files for valid2.zip
    mkdir -p /tmp/zip2
    echo "Gamma results with [OBSOLETE_TAG] present." | iconv -f UTF-8 -t WINDOWS-1252 > /tmp/zip2/gamma_data.txt
    cd /tmp/zip2 && zip /tmp/valid2.zip *.txt

    # Create a corrupted zip
    dd if=/dev/urandom of=/tmp/corrupt.zip bs=1024 count=5

    # Create the outer tarball
    cd /tmp
    tar -cvf /home/user/research_data.tar valid1.zip corrupt.zip valid2.zip

    # Clean up tmp
    rm -rf /tmp/zip1 /tmp/zip2 /tmp/valid1.zip /tmp/valid2.zip /tmp/corrupt.zip

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user

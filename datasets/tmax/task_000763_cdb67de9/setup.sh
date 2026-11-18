#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        g++ \
        imagemagick \
        fonts-dejavu-core \
        tar \
        gzip

    pip3 install pytest

    mkdir -p /app
    mkdir -p /home/user/raw_data
    mkdir -p /home/user/safe_data
    mkdir -p /app/verifier_corpus/evil
    mkdir -p /app/verifier_corpus/clean

    # Create the policy scan image
    convert -background white -fill black -font DejaVu-Sans -pointsize 18 label:"BACKUP EXCLUSION POLICY:\n1. Reject any file that begins with the magic bytes 'EVIL' (0x45 0x56 0x49 0x4C) at offset 0.\n2. Reject any file that contains the exact ASCII string 'DO_NOT_BACKUP' anywhere in its contents." /app/policy_scan.png

    # Create clean files
    echo "This is a completely normal and safe file." > /app/verifier_corpus/clean/clean_text.txt
    dd if=/dev/urandom of=/app/verifier_corpus/clean/clean_binary.bin bs=1K count=5 status=none

    # Create evil files
    printf "EVIL_magic_bytes_at_start" > /app/verifier_corpus/evil/evil_magic.bin
    echo "This file contains the string DO_NOT_BACKUP which is forbidden." > /app/verifier_corpus/evil/evil_string.txt
    printf "EVIL_and_also_DO_NOT_BACKUP" > /app/verifier_corpus/evil/evil_both.bin

    # Populate raw_data
    cp /app/verifier_corpus/clean/* /home/user/raw_data/
    cp /app/verifier_corpus/evil/* /home/user/raw_data/

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app

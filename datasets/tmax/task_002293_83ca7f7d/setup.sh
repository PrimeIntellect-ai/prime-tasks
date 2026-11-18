#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gzip bzip2 coreutils xxd
    pip3 install pytest

    mkdir -p /home/user/legacy_archive/backup_alpha
    mkdir -p /home/user/legacy_archive/backup_beta
    mkdir -p /home/user/new_archive

    # Generate dummy text data
    dd if=/dev/urandom bs=1M count=1 | base64 > /tmp/alpha_raw.txt
    dd if=/dev/urandom bs=1M count=1 | base64 > /tmp/beta_raw.txt

    # Compress with gzip
    gzip -c /tmp/alpha_raw.txt > /tmp/alpha_body.gz
    gzip -c /tmp/beta_raw.txt > /tmp/beta_body.gz

    # Create headers using python to ensure correct byte values
    python3 -c 'open("/tmp/alpha_header.bin", "wb").write(b"\x11\x22\x33\x44\x55\x66\x77\x88")'
    python3 -c 'open("/tmp/beta_header.bin", "wb").write(b"\xAA\xBB\xCC\xDD\xEE\xFF\x00\x11")'

    # Concatenate header and body
    cat /tmp/alpha_header.bin /tmp/alpha_body.gz > /tmp/alpha_full.bin
    cat /tmp/beta_header.bin /tmp/beta_body.gz > /tmp/beta_full.bin

    # Split into legacy chunks
    cd /home/user/legacy_archive/backup_alpha && split -b 100K /tmp/alpha_full.bin chunk_
    cd /home/user/legacy_archive/backup_beta && split -b 100K /tmp/beta_full.bin chunk_

    # Clean up tmp files
    rm /tmp/alpha_raw.txt /tmp/beta_raw.txt /tmp/alpha_body.gz /tmp/beta_body.gz /tmp/alpha_header.bin /tmp/beta_header.bin /tmp/alpha_full.bin /tmp/beta_full.bin

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user

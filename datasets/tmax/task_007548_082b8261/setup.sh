#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang tar coreutils
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/dataset_raw
    mkdir -p /home/user/extracted
    mkdir -p /home/user/organized

    # Create Set 1 (Valid)
    mkdir -p /tmp/set1
    echo "ID: X99\nCategory: RNA" > /tmp/set1/sample_alpha.txt
    dd if=/dev/urandom of=/tmp/set1/sample_alpha.dat bs=1K count=5 2>/dev/null
    tar -czf /tmp/set1.tar.gz -C /tmp set1
    split -b 2K /tmp/set1.tar.gz /home/user/dataset_raw/set1.tar.gz.

    # Create Set 2 (Valid)
    mkdir -p /tmp/set2
    echo "ID: M01\nCategory: DNA" > /tmp/set2/sample_beta.txt
    dd if=/dev/urandom of=/tmp/set2/sample_beta.dat bs=1K count=5 2>/dev/null
    tar -czf /tmp/set2.tar.gz -C /tmp set2
    split -b 2K /tmp/set2.tar.gz /home/user/dataset_raw/set2.tar.gz.

    # Create Set 3 (Corrupted)
    mkdir -p /tmp/set3
    echo "ID: B44\nCategory: Protein" > /tmp/set3/sample_gamma.txt
    dd if=/dev/urandom of=/tmp/set3/sample_gamma.dat bs=1K count=5 2>/dev/null
    tar -czf /tmp/set3.tar.gz -C /tmp set3
    # Corrupt the tarball by overwriting a chunk in the middle
    dd if=/dev/zero of=/tmp/set3.tar.gz bs=1K count=1 seek=1 conv=notrunc 2>/dev/null
    split -b 2K /tmp/set3.tar.gz /home/user/dataset_raw/set3.tar.gz.

    chmod -R 777 /home/user

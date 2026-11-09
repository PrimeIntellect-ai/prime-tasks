#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip coreutils libc-bin
    pip3 install pytest

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user

    # Create the initial random data (4096 bytes)
    dd if=/dev/urandom of=/home/user/artifacts.bin bs=1 count=4096 2>/dev/null

    # Create the metadata text
    cat << 'EOF' > /tmp/meta_raw.txt
pkg-alpha-1.0.tar.gz
pkg-beta-2.1.tar.gz REJECTED
pkg-gamma-1.5.tar.gz
pkg-delta-3.0.tar.gz OBSOLETE
pkg-epsilon-2.0.tar.gz
pkg-zeta-1.1.tar.gz
EOF

    # Convert to UTF-16LE
    iconv -f UTF-8 -t UTF-16LE /tmp/meta_raw.txt > /tmp/meta.utf16

    # Create a 512-byte zero-filled file
    dd if=/dev/zero of=/tmp/meta_512.utf16 bs=1 count=512 2>/dev/null

    # Overwrite the beginning of the 512-byte file with our UTF-16 text
    dd if=/tmp/meta.utf16 of=/tmp/meta_512.utf16 bs=1 conv=notrunc 2>/dev/null

    # Append the 512-byte block to the artifacts file at offset 4096
    cat /tmp/meta_512.utf16 >> /home/user/artifacts.bin

    # Append some trailing random data
    dd if=/dev/urandom bs=1 count=2048 2>/dev/null >> /home/user/artifacts.bin

    rm -f /tmp/meta_raw.txt /tmp/meta.utf16 /tmp/meta_512.utf16

    chmod -R 777 /home/user

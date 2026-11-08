#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    mkdir -p /home/user/data/setA/nested
    mkdir -p /home/user/data/setB

    # Create valid RLE: "AAACCCCT" -> 03 'A' 04 'C' 01 'T' + [08 00 00 00]
    printf "\x03A\x04C\x01T\x08\x00\x00\x00" > /home/user/data/setA/sample1.rle

    # Create valid RLE: "G" x 255 -> 255 'G' + [255 00 00 00]
    printf "\xFFG\xFF\x00\x00\x00" > /home/user/data/setA/nested/sample2.rle

    # Create corrupt RLE: "AA" -> 02 'A' + [05 00 00 00] (length mismatch)
    printf "\x02A\x05\x00\x00\x00" > /home/user/data/setB/sample3.rle

    # Create corrupt RLE: Too short (only 3 bytes)
    printf "\x01A\x00" > /home/user/data/setB/sample4.rle

    # Create directories.conf
    cat << 'EOF' > /home/user/directories.conf
/home/user/data/setA
/home/user/data/setB
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user/data /home/user/directories.conf
    chmod -R 777 /home/user

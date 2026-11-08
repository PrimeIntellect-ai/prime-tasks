#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tar gzip coreutils
    pip3 install pytest

    mkdir -p /home/user/datasets
    mkdir -p /tmp/v1 /tmp/v2

    # Create valid archive 1
    printf "\xde\xad\xbe\xef\x01\x02\x03\x04" > /tmp/v1/alpha.bin
    printf "\x11\x22\x33\x44\x55\x66\x77\x88" > /tmp/v1/beta.bin
    cd /tmp/v1 && tar -czf /home/user/datasets/sample1.tar.gz alpha.bin beta.bin

    # Create corrupt archive
    echo "This is a corrupted tarball missing the correct headers and gzip compression." > /home/user/datasets/broken_data.tar.gz

    # Create valid archive 2
    printf "\xca\xfe\xba\xbe\x99\x88\x77\x66" > /tmp/v2/gamma.bin
    printf "Not a bin file" > /tmp/v2/readme.txt
    cd /tmp/v2 && tar -czf /home/user/datasets/sample2.tar.gz gamma.bin readme.txt

    # Create config file
    cat << 'EOF' > /home/user/dataset_rules.conf
ARCHIVE_DIR=/home/user/datasets
MAGIC_BYTES_COUNT=4
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user

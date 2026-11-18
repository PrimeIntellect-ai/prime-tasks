#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl nginx tar gzip cargo rustc
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/data/archives
    mkdir -p /home/user/data/chunks
    mkdir -p /home/user/data/active

    # Create a valid tarball (approx 1MB)
    dd if=/dev/urandom of=/tmp/dummy_file bs=1024 count=1024
    tar -czf /home/user/data/archives/app-v1.tar.gz -C /tmp dummy_file

    # Create a corrupt tarball
    echo "This is a corrupted archive file." > /home/user/data/archives/corrupt-v2.tar.gz

    SIZE1=$(stat -c%s /home/user/data/archives/app-v1.tar.gz)
    SIZE2=$(stat -c%s /home/user/data/archives/corrupt-v2.tar.gz)

    cat <<EOF > /home/user/data/sync.log
[START UPLOAD]
File: app-v1.tar.gz
Expected-Size: $SIZE1
[END UPLOAD]
[START UPLOAD]
File: corrupt-v2.tar.gz
Expected-Size: $SIZE2
[END UPLOAD]
EOF

    chmod -R 777 /home/user

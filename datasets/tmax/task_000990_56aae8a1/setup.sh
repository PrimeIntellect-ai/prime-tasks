#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip rustc
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/dataset.txt
The quick brown fox jumps over the lazy dog
A quick brown dog jumps over the log
The fast fox jumps high
Lazy dog sleeps all day
The quick brown fox is very quick
EOF

    chmod -R 777 /home/user

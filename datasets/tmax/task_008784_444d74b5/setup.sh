#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/input.tsv
A	Hello, World!
B	Python is great.
A	Data engineering 101.
A	Sample text!
B	More data, please.
A	Ignore this one.
B	Just enough text here.
B	Extra line.
EOF

    chmod -R 777 /home/user

#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user/data/raw
    cat << 'EOF' > /home/user/data/raw/equations.txt
2x + 3.1 = 7
y = m*x + c
What is this ?
func(x) = x * 2
invalid_line_due_to_underscore = 5
10.5 / 2 = 5.25
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user

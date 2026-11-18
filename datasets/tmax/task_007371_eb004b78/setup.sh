#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk
    pip3 install pytest

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user

    cat << 'EOF' > /home/user/alignments.txt
85
90
88
92
85
95
89
91
87
86
EOF

    python3 -c '
import random
random.seed(42)
with open("/home/user/random_indices.txt", "w") as f:
    for _ in range(10000):
        f.write(str(random.randint(1, 10)) + "\n")
'

    chmod -R 777 /home/user

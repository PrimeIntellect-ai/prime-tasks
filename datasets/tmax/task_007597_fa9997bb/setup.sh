#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk coreutils
    pip3 install pytest

    mkdir -p /home/user
    cat << 'EOF' > /home/user/dataset.csv
1|Hello world|0
2|Bash is great for text processing|1
3|Data science in the shell|1
invalid row without delimiters
4|Too many|columns|here|0
5|Another valid row|0
6|Short text|1
7|A very very long text string for testing|0
8|Testing dataset|1
9|More data|0
10|Final row|1
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user

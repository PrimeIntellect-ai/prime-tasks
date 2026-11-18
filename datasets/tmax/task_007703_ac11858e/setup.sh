#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/data
    mkdir -p /home/user/output

    cat << 'EOF' > /home/user/data/chats.txt
3600|en|Hello world
3605|es|Hola mundo
3610|en|Hello world
3650|fr|Bonjour
7200|en|Hello world
7215|zh|你好
7220|zh|你好
7300|zh|你好吗
EOF

    chmod -R 777 /home/user

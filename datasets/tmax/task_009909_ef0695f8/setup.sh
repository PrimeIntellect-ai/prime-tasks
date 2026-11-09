#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang
    pip3 install pytest

    mkdir -p /home/user
    cat << 'EOF' > /home/user/polygraph.txt
init : : 2 * 3 + 4
build_db : init : 10 - 2 * 3
build_web : init : 15 / 3 + 1
link_all : build_db,build_web : 8 + 2 * 2
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user

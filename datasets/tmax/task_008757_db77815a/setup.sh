#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install --no-cache-dir pytest jupyter nbconvert networkx matplotlib

    mkdir -p /home/user
    cat << 'EOF' > /home/user/sequences.txt
AAACTAG
TAGCCCA
TAGGGGA
TAGTTTA
GATTACA
ACAGCTA
CTAGGAC
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user

#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libssl-dev
    pip3 install pytest

    mkdir -p /home/user/raw_data
    mkdir -p /home/user/backup

    cat << 'EOF' > /home/user/rules.cfg
.png=img_
.txt=doc_
.c=src_
EOF

    echo "Image data" > /home/user/raw_data/test.png
    echo "Log data" > /home/user/raw_data/info.txt
    echo "int main(){}" > /home/user/raw_data/app.c
    echo "Unknown" > /home/user/raw_data/file.bin

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user

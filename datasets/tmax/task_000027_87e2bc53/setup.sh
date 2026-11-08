#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user
    cat << 'EOF' > /home/user/network.tsv
A	B
A	C
A	D
B	E
C	E
D	E
B	F
C	F
E	G
F	G
G	H
A	I
I	E
I	J
J	K
EOF
    chmod 644 /home/user/network.tsv

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user

#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk coreutils
    pip3 install pytest

    mkdir -p /home/user
    cat << 'EOF' > /home/user/ppi_network.tsv
A	B	0.8
A	C	0.5
B	C	0.9
B	D	0.3
C	A	0.4
C	E	0.7
D	E	0.6
D	A	0.5
E	B	0.2
E	D	0.8
EOF
    chmod 644 /home/user/ppi_network.tsv

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user

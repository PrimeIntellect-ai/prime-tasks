#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest

    mkdir -p /home/user
    cat << 'EOF' > /home/user/raw_data.tsv
ATGC	TACG	1.0,2.1;2.0,4.0;3.0,6.2
GCTA	GCTA	1.0,1.1;2.0,2.0;3.0,3.1
AAAA	ATAT	1.0,5.0;2.0,10.0;3.0,15.0
TCGATC	TCGTTC	2.5,10.2;4.5,15.1;6.0,18.8
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user

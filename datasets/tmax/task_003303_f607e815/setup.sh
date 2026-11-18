#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libc6-dev
    pip3 install pytest

    mkdir -p /home/user
    cat << 'EOF' > /home/user/raw_sequences.txt
2018-R01:AAAAAGGGGGCCCCCTTTTT
2018-R02:AATTCCGG
2019-R01:GGGGGGGGGGAA
2020-R03:TTTTTAAAAAACCCCCCGGG
2020-R01:ATCG
2021-R02:AAAAAAAAAAAAAAAAT
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod 644 /home/user/raw_sequences.txt

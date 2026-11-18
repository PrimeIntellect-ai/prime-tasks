#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libc6-dev make
    pip3 install pytest

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user/data

    cat << 'EOF' > /home/user/data/seq1.fasta
>sequence_1
AAAAA AAAAA AAAAA AAAAA
CCCCC CCCCC CCCCC CCCCC CCCCC CCCCC
GGGGG GGGGG GGGGG GGGGG GGGGG GGGGG GGGGG GGGGG
TTTTT TTTTT
EOF

    cat << 'EOF' > /home/user/data/seq2.fasta
>sequence_2
AAAAA AAAAA AAAAA AAAAA AAAAA AAAAA AAAAA AAAAA
CCCCC CCCCC
GGGGG GGGGG GGGGG GGGGG
TTTTT TTTTT TTTTT TTTTT TTTTT TTTTT
EOF

    chmod -R 777 /home/user

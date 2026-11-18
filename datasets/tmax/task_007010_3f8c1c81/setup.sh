#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libgomp1
    pip3 install pytest

    mkdir -p /home/user/data /home/user/src /home/user/bin /home/user/output

    cat << 'EOF' > /home/user/data/sequences.fasta
>seq001
ATGCGTACGTAGCTAGCTAGCATCGATCGA
>seq002
GGCCTTAATTCGGCC
>seq003
AAAAAGGGGGCCCCCTTTTT
>seq004
ATATATATATATATATATAT
>seq005
GCGCGCGCGCGCGCGCGCGC
EOF

    cat << 'EOF' > /home/user/data/observational.tsv
seq001	0.98
seq002	0.45
seq003	1.23
seq004	0.11
seq005	0.76
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user/data /home/user/src /home/user/bin /home/user/output
    chmod -R 777 /home/user

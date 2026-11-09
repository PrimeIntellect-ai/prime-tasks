#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang-go
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/sequences.fasta
>seq1_linear
ACGT
>seq2_polyA
AAAA
>seq3_oscillating
CGCG
>seq4_mixed
ACGTGCTAAC
>seq5_multiline
ACGT
ACGT
EOF

    chmod -R 777 /home/user

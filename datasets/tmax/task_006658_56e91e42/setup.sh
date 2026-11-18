#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk grep sed coreutils
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user
    cat << 'EOF' > /home/user/sequences.fasta
>Seq1_HighGC
GGGCCCGGGCCC
>Seq2_LowGC
ATATATATAT
>Seq3_BorderlineHigh
GGGCCCGGGAT
>Seq4_BorderlineLow
GGGCCCATATAT
>Seq5_ExtremeGC
CGCGCGCGCGCGCA
>Seq6_Stable
GCGCATAT
EOF

    chmod -R 777 /home/user

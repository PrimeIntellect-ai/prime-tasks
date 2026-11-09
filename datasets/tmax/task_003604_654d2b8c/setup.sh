#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libc6-dev make
    pip3 install pytest

    mkdir -p /app/corpus/clean
    mkdir -p /app/corpus/evil

    cat << 'EOF' > /app/corpus/clean/seq1.fasta
>clean1
ACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGT
EOF

    cat << 'EOF' > /app/corpus/clean/seq2.fasta
>clean2
ATGCGCATATGCGCTAGCTAGCATCGATCGATCGATCGACTAGCTAGCTAGC
EOF

    cat << 'EOF' > /app/corpus/evil/seq1.fasta
>evil1_motif
ATGCATGCGGGGATGGGGATGCATGCATGCATGC
EOF

    cat << 'EOF' > /app/corpus/evil/seq2.fasta
>evil2_skew
AAAAAAAAAAAAAAAAAAAAATTTTTTTTTTTTTTTTTTTTAAAAAAAAAAAAAAAAAAAAA
EOF

    # Create dummy video file
    echo "dummy video content" > /app/stiff_ode_debug.mp4

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app

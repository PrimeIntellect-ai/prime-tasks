#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip espeak
    pip3 install pytest

    mkdir -p /app/corpus/clean /app/corpus/evil

    # Generate instructions audio
    espeak -w /app/instructions.wav "A sequence is considered evil and unstable if it contains any characters in the sequence body other than uppercase A, C, G, and T. Even a single lowercase letter, a space, an N, or any other invalid character in the sequence lines means it will crash the Monte Carlo simulator and must be rejected. The header line starting with greater-than can contain any characters and should be ignored for this check."

    # Create clean FASTA files
    cat << 'EOF' > /app/corpus/clean/clean1.fasta
>clean1
ACGTACGT
ACGT
EOF

    cat << 'EOF' > /app/corpus/clean/clean2.fasta
>clean2
GATTACA
GATTACA
EOF

    cat << 'EOF' > /app/corpus/clean/clean3.fasta
>clean3
CCCGGG
AAATTT
EOF

    cat << 'EOF' > /app/corpus/clean/clean4.fasta
>clean4
A
C
G
T
EOF

    cat << 'EOF' > /app/corpus/clean/clean5.fasta
>clean5
ACGT
EOF

    # Create evil FASTA files
    cat << 'EOF' > /app/corpus/evil/evil1.fasta
>evil1
ACGTNCGT
ACGT
EOF

    cat << 'EOF' > /app/corpus/evil/evil2.fasta
>evil2
ACGTaCGT
ACGT
EOF

    cat << 'EOF' > /app/corpus/evil/evil3.fasta
>evil3
ACGT CGT
ACGT
EOF

    cat << 'EOF' > /app/corpus/evil/evil4.fasta
>evil4
ACGTXCGT
ACGT
EOF

    cat << 'EOF' > /app/corpus/evil/evil5.fasta
>evil5
ACGT1CGT
ACGT
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app

#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip espeak ffmpeg cargo rustc
    pip3 install pytest

    mkdir -p /app/corpus/evil /app/corpus/clean

    espeak -w /app/issue_report.wav "Hi, this is Dr. Aris. We have traced the core dump in our genetic optimization pipeline. It is failing during matrix factorization because of near singular inputs. We found the exact trigger: it happens when the input FASTA sequences have highly artificial, uniform amino acid composition distributions. To build a filter, you need to parse the FASTA file, calculate the empirical amino acid frequency distribution, and then use a Monte Carlo bootstrap. Specifically, sample characters from the sequence with replacement to form a sequence of the same length, and calculate the Total Variation Distance between this bootstrap samples amino acid distribution and a perfectly uniform distribution of the twenty standard amino acids. Repeat this for five hundred bootstrap iterations. Calculate the ninety-five percent confidence interval of these Total Variation Distances. If the width of this confidence interval, meaning the 97.5th percentile minus the 2.5th percentile, is strictly less than 0.02, it means the sequence is artificially constrained and will cause a singular matrix. Flag those as EVIL. Everything else is CLEAN."

    cat << 'EOF' > /app/corpus/clean/seq1.fasta
>clean_1
MKVIFLKDVKGMGKKGEIKNVADGYANNFLFKQGLAIEATPANWKAAENFKAWIKEKVKE
QNKDKIEIEKLYELNKQGFINLKTYNPEKIEYQVLKAQKKLEEKGLLR
EOF

    cat << 'EOF' > /app/corpus/clean/seq2.fasta
>clean_2
MADQLTEEQIAEFKEAFSLFDKDGDGTITTKELGTVMRSLGQNPTEAELQDMINEVDADG
NGTIDFPEFLTMMARKMKDTDSEEEIREAFRVFDKDGNGYISAAELRHVMTNLGEKLTDE
EVDEMIREADIDGDGQVNYEEFVQMMTAK
EOF

    cat << 'EOF' > /app/corpus/evil/seq1.fasta
>evil_1
ACDEFGHIKLMNPQRSTVWYACDEFGHIKLMNPQRSTVWYACDEFGHIKLMNPQRSTVWY
ACDEFGHIKLMNPQRSTVWYACDEFGHIKLMNPQRSTVWYACDEFGHIKLMNPQRSTVWY
ACDEFGHIKLMNPQRSTVWYACDEFGHIKLMNPQRSTVWYACDEFGHIKLMNPQRSTVWY
ACDEFGHIKLMNPQRSTVWYACDEFGHIKLMNPQRSTVWYACDEFGHIKLMNPQRSTVWY
ACDEFGHIKLMNPQRSTVWYACDEFGHIKLMNPQRSTVWYACDEFGHIKLMNPQRSTVWY
EOF

    cat << 'EOF' > /app/corpus/evil/seq2.fasta
>evil_2
YWVTSRQPNMLKIHGFEDCAYWVTSRQPNMLKIHGFEDCAYWVTSRQPNMLKIHGFEDCA
YWVTSRQPNMLKIHGFEDCAYWVTSRQPNMLKIHGFEDCAYWVTSRQPNMLKIHGFEDCA
YWVTSRQPNMLKIHGFEDCAYWVTSRQPNMLKIHGFEDCAYWVTSRQPNMLKIHGFEDCA
YWVTSRQPNMLKIHGFEDCAYWVTSRQPNMLKIHGFEDCAYWVTSRQPNMLKIHGFEDCA
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app

#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip imagemagick tesseract-ocr
    pip3 install pytest

    mkdir -p /app/evil /app/clean

    # Clean corpus
    cat << 'EOF' > /app/clean/seq1.fasta
>clean_1
ATCGATCGATCGATCG
EOF

    cat << 'EOF' > /app/clean/seq2.fasta
>clean_2
GGCCTTAAGGCCTTAA
EOF

    # Evil corpus
    cat << 'EOF' > /app/evil/seq1.fasta
>evil_1
AAAAAAAATCGAAAAA
EOF

    cat << 'EOF' > /app/evil/seq2.fasta
>evil_2
GGGGGGGGGGGGATCG
EOF

    # Generate the image fixture
    convert -background white -fill black -pointsize 24 label:"Threshold rule: REJECT sequence if the frequency of ANY single nucleotide (A, C, G, or T) strictly exceeds T, where T is the real root of 8x^3 - 1 = 0." /app/threshold.png

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app

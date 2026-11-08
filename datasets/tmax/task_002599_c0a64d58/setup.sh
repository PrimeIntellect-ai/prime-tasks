#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/target.fasta
>target_sequence
ATGCGTAACGTAGCTAGCTATTTTCCCCCCAAAAAAGGGGGGCCTTCGAATTCGCATCGA
EOF

    cat << 'EOF' > /home/user/reference.fasta
>reference_genome
GATCGATCGATCGATCGATCATGCGTAACGTAGCTAGCTAGATCGATCGATCGATCGATC
GATCGATCGATCGATCGATCTCGATGCGAATTCGAAGGCCGATCGATCGATCGATCGATC
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user

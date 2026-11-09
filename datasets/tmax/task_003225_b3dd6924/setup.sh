#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy scipy h5py matplotlib biopython

    mkdir -p /home/user
    cat << 'EOF' > /home/user/viral_sequences.fasta
>Strain_Alpha
ATGCGCGTACGCGT
>Strain_Beta
ATATATATATATAT
>Strain_Gamma
GCGCGCGCGCGCGC
>Strain_Delta
ATGCCGTA
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user

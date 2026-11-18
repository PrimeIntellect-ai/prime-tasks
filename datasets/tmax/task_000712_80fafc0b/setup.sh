#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    # Install required python packages
    pip3 install jupyter papermill nbconvert scipy matplotlib biopython

    # Create the home directory and user
    useradd -m -s /bin/bash user || true

    # Create sequences.fasta
    cat << 'EOF' > /home/user/sequences.fasta
>WT_strain
ATGCATGCATGCATGCATGC
>Mutant_A
GCGCGCGCGCGCGCGCGCAT
>Mutant_B
ATATATATATATATATATGC
EOF

    # Ensure permissions
    chmod -R 777 /home/user

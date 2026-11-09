#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy scipy

    mkdir -p /home/user/data
    mkdir -p /home/user/output

    cat << 'EOF' > /home/user/data/sequences.fasta
>Seq_Reference
ATGCGTACGTAGCTAGATGCGTACGTAGCTAG
>Seq_Mutant_1
ATGCGTACGTAGCTAAATGCGTACGTAGCTAA
>Seq_Poly_G
GGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGG
>Seq_Poly_T
TTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTT
>Seq_Random
ACGTACGTACGTACGTACGTACGTACGTACGT
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user

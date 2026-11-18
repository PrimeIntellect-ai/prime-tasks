#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy pandas scipy biopython

    mkdir -p /home/user/data /home/user/output

    cat << 'EOF' > /home/user/data/sequences.fasta
>SeqA
ATGCCGTAGCTACGTAA
>SeqB
AAAAAATTTTTT
>SeqC
CGCGCGCGCGCGCGCGCGTAGCTACGCGCG
>SeqD
CGTAGCTACG
>SeqE
TTTCGTAGCTACGGGG
EOF

    cat << 'EOF' > /home/user/data/signals.csv
SeqID,wavenumber,intensity
SeqA,1,0.0
SeqA,2,2.0
SeqA,3,5.0
SeqA,4,2.0
SeqA,5,0.0
SeqB,1,1.0
SeqB,2,1.0
SeqB,3,1.0
SeqB,4,1.0
SeqB,5,1.0
SeqC,1,0.0
SeqC,2,1.0
SeqC,3,1.5
SeqC,4,1.0
SeqC,5,0.0
SeqD,1,0.0
SeqD,2,3.0
SeqD,3,0.0
SeqD,4,3.0
SeqD,5,0.0
SeqE,1,2.0
SeqE,2,4.0
SeqE,3,6.0
SeqE,4,4.0
SeqE,5,2.0
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user

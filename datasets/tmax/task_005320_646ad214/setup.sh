#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/sequences.fasta
>Seq_01
ATGCATGCATGCATGC
>Seq_02
ATCGGGTACCTAGCGAT
>Seq_03
GGCCTTAAGGCCTTAA
EOF

    cat << 'EOF' > /home/user/spectra.txt
Seq_01|10.0:1.5,12.0:1.0,11.0:2.0
Seq_02|300.3:6.1000000001,300.1:5.5000000002,300.2:4.2000000003
Seq_03|50.0:1.0,51.0:1.0
EOF

    chmod -R 777 /home/user

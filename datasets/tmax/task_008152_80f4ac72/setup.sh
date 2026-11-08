#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest biopython

    mkdir -p /home/user/data

    cat << 'EOF' > /home/user/data/sequences.fasta
>A
MKTAY
>B
MKTAAYYY
>A
MKT
>C
A
>D
MMMMMMMMMM
EOF

    cat << 'EOF' > /home/user/data/structure.pdb
ATOM      1  N   ALA A   1      11.104  13.727  15.684  1.00  0.00           N  
ATOM      2  CA  ALA A   1      10.104  13.727  15.684  1.00  0.00           C  
ATOM      3  C   ALA A   1       9.104  13.727  15.684  1.00  0.00           C  
ATOM      4  CA  GLY A   2      10.104  14.727  15.684  1.00  0.00           C  
ATOM      5  N   ALA B   1      11.104  13.727  15.684  1.00  0.00           N  
ATOM      6  CA  ALA B   1      10.104  13.727  15.684  1.00  0.00           C  
ATOM      7  CA  GLY B   2      10.104  14.727  15.684  1.00  0.00           C  
ATOM      8  CA  TYR B   3      10.104  15.727  15.684  1.00  0.00           C  
ATOM      9  CA  MET E   1      10.104  15.727  15.684  1.00  0.00           C  
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user

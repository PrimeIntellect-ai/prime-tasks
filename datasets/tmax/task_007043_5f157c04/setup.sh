#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy scipy biopython

    mkdir -p /home/user/data

    cat << 'EOF' > /home/user/data/input.fasta
>seq1_protein
ACDEFGHIKLMNPQRSTVWY
>seq2_protein
ACDEFGHIKLMNP
>seq3_protein
ACDEFGHIKLMNPQRSTVWYACDEF
>seq4_protein
ACDE
>seq5_protein
ACDEFGHIKLMNPQRSTVWYACDEFGHIKL
EOF

    cat << 'EOF' > /home/user/data/protein.pdb
ATOM      1  N   ALA A   1      11.104   6.134  -6.504  1.00 10.50           N  
ATOM      2  CA  ALA A   1      11.639   6.071  -5.147  1.00 12.20           C  
ATOM      3  C   ALA A   1      10.655   6.570  -4.086  1.00 15.00           C  
ATOM      4  O   ALA A   1       9.489   6.162  -4.148  1.00 14.50           O  
ATOM      5  N   CYS A   2      11.144   7.447  -3.149  1.00 18.20           N  
ATOM      6  CA  CYS A   2      10.334   8.026  -2.072  1.00 20.50           C  
ATOM      7  C   CYS A   2       9.544   9.231  -2.585  1.00 22.10           C  
ATOM      8  O   CYS A   2       8.318   9.183  -2.730  1.00 23.00           O  
ATOM      9  N   ASP A   3      10.237  10.323  -2.842  1.00 25.50           N  
ATOM     10  CA  ASP A   3       9.638  11.564  -3.328  1.00 28.30           C  
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user

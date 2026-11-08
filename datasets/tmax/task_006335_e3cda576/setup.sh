#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy

    mkdir -p /home/user

    cat << 'EOF' > /home/user/eiip.tsv
A	0.0373
C	0.0829
D	0.1263
E	0.0058
F	0.0946
G	0.0050
H	0.0242
I	0.0000
K	0.0371
L	0.0000
M	0.0823
N	0.0036
P	0.0198
Q	0.0761
R	0.0959
S	0.0829
T	0.0941
V	0.0057
W	0.0548
Y	0.0516
EOF

    cat << 'EOF' > /home/user/proteins.fasta
>SeqA_kinase
AAAAACCCCCDDDDDEEEEEFFFFFGGGGGHHHHIIIIKKKKLLLLMMMMNNNNPPPPQQQQRRRRSSSSTTTTVVVVWWWWYYYY
>SeqB_mutant
ACDEFGHIKLMNPQRSTVWYACDEFGHIKLMNPQRSTVWYACDEFGHIKLMNPQRSTVWYACDEFGHIKLMNPQRSTVWY
>SeqC_short
ACDEFGHIKLMNPQRSTVWY
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user

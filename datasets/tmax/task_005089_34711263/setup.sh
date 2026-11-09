#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip rustc cargo
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/input.fasta
>seq1
ACDEFGHIKLMNPQRSTVWY
>seq2
ACDEFGHIKLMNPQRSTV
EOF

    cat << 'EOF' > /home/user/background.csv
A,0.05
C,0.05
D,0.05
E,0.05
F,0.05
G,0.05
H,0.05
I,0.05
K,0.05
L,0.05
M,0.05
N,0.05
P,0.05
Q,0.05
R,0.05
S,0.05
T,0.05
V,0.05
W,0.05
Y,0.05
EOF

    chmod -R 777 /home/user

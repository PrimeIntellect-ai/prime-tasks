#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip build-essential libfftw3-dev
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/mass_table.txt
A 71.0
C 103.0
D 115.0
E 129.0
F 147.0
G 57.0
H 137.0
I 113.0
K 128.0
L 113.0
M 131.0
N 114.0
P 97.0
Q 128.0
R 156.0
S 87.0
T 101.0
V 99.0
W 186.0
Y 163.0
EOF

    python3 -c "
seq = 'ACDEFGH' * 100
with open('/home/user/protein.fasta', 'w') as f:
    f.write('>synthetic_coiled_coil\n')
    for i in range(0, len(seq), 70):
        f.write(seq[i:i+70] + '\n')
"

    chmod -R 777 /home/user

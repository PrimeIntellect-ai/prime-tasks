#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/sequences.fasta
>seq1
ARNDCQEGHILKMFPSTWYV
>seq2
AAAA
EOF

    cat << 'EOF' > /home/user/structure.pdb
ATOM      1  N   ALA A   1      11.104   6.134  -6.504  1.00  0.00           N
ATOM      2  CA  ALA A   1      11.639   6.071  -5.147  1.00  0.00           C
ATOM      3  C   ALA A   1      13.115   6.438  -5.146  1.00  0.00           C
ATOM      4  O   ALA A   1      13.560   7.165  -6.040  1.00  0.00           O
ATOM      5  N   CYS A   2      13.858   5.940  -4.155  1.00  0.00           N
ATOM      6  CA  CYS A   2      15.295   6.166  -3.951  1.00  0.00           C
ATOM      7  C   CYS A   2      16.331   5.056  -4.182  1.00  0.00           C
ATOM      8  O   CYS A   2      17.514   5.289  -3.945  1.00  0.00           O
ATOM      9  N   GLY A   3      15.892   3.851  -4.634  1.00  0.00           N
ATOM     10  CA  GLY A   3      16.805   2.723  -4.843  1.00  0.00           C
ATOM     11  C   GLY A   3      17.653   2.455  -3.606  1.00  0.00           C
ATOM     12  O   GLY A   3      18.882   2.355  -3.693  1.00  0.00           O
ATOM     13  N   ALA A   4      17.009   2.368  -2.450  1.00  0.00           N
ATOM     14  CA  ALA A   4      17.728   2.180  -1.201  1.00  0.00           C
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user

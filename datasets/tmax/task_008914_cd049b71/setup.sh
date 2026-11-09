#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make
    pip3 install pytest

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user

    cat << 'EOF' > /home/user/protein.pdb
ATOM      1  N   ALA A   1      11.104   6.134  -6.504  1.00  0.00           N
ATOM      2  CA  ALA A   1      11.639   6.071  -5.147  1.00  0.00           C
ATOM      3  C   ALA A   1      13.151   5.965  -5.267  1.00  0.00           C
ATOM      4  O   ALA A   1      13.821   6.996  -5.321  1.00  0.00           O
ATOM      5  N   CYS A   2      13.684   4.739  -5.312  1.00  0.00           N
ATOM      6  CA  CYS A   2      15.132   4.492  -5.419  1.00  0.00           C
ATOM      7  C   CYS A   2      15.772   3.785  -4.225  1.00  0.00           C
ATOM      8  O   CYS A   2      15.340   2.684  -3.882  1.00  0.00           O
ATOM      9  N   ASP A   3      16.804   4.414  -3.606  1.00  0.00           N
ATOM     10  CA  ASP A   3      17.491   3.840  -2.454  1.00  0.00           C
EOF

    chmod -R 777 /home/user

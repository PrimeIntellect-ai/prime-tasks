#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ make wget tar
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/data /home/user/workspace /home/user/output

    cat << 'EOF' > /home/user/data/sequence.fasta
>test_protein
ACDEFGHIKL
EOF

    cat << 'EOF' > /home/user/data/protein.pdb
ATOM      1  N   ALA A   1      10.000  10.000  10.000  1.00  0.00           N  
ATOM      2  CA  ALA A   1      11.000  10.000  10.000  1.00  0.00           C  
ATOM      3  C   ALA A   1      11.000  11.000  10.000  1.00  0.00           C  
ATOM      4  O   ALA A   1      11.000  12.000  10.000  1.00  0.00           O  
ATOM      5  N   CYS A   2      12.000  11.000  10.000  1.00  0.00           N  
ATOM      6  CA  CYS A   2      13.000  11.000  11.000  1.00  0.00           C  
ATOM      7  C   CYS A   2      13.000  12.000  11.000  1.00  0.00           C  
ATOM      8  O   CYS A   2      13.000  13.000  11.000  1.00  0.00           O  
ATOM      9  N   ASP A   3      14.000  12.000  11.000  1.00  0.00           N  
ATOM     10  CA  ASP A   3      15.000  12.000  12.000  1.00  0.00           C  
ATOM     11  C   ASP A   3      15.000  13.000  12.000  1.00  0.00           C  
ATOM     12  O   ASP A   3      15.000  14.000  12.000  1.00  0.00           O  
ATOM     13  N   GLU A   4      16.000  13.000  12.000  1.00  0.00           N  
ATOM     14  CA  GLU A   4      17.000  13.000  13.000  1.00  0.00           C  
ATOM     15  C   GLU A   4      17.000  14.000  13.000  1.00  0.00           C  
ATOM     16  O   GLU A   4      17.000  15.000  13.000  1.00  0.00           O  
ATOM     17  N   PHE A   5      18.000  14.000  13.000  1.00  0.00           N  
ATOM     18  CA  PHE A   5      19.000  14.000  14.000  1.00  0.00           C  
ATOM     19  C   PHE A   5      19.000  15.000  14.000  1.00  0.00           C  
ATOM     20  O   PHE A   5      19.000  16.000  14.000  1.00  0.00           O  
ATOM     21  N   GLY A   6      20.000  15.000  14.000  1.00  0.00           N  
ATOM     22  CA  GLY A   6      21.000  15.000  15.000  1.00  0.00           C  
ATOM     23  C   GLY A   6      21.000  16.000  15.000  1.00  0.00           C  
ATOM     24  O   GLY A   6      21.000  17.000  15.000  1.00  0.00           O  
ATOM     25  N   HIS A   7      22.000  16.000  15.000  1.00  0.00           N  
ATOM     26  CA  HIS A   7      23.000  16.000  16.000  1.00  0.00           C  
ATOM     27  C   HIS A   7      23.000  17.000  16.000  1.00  0.00           C  
ATOM     28  O   HIS A   7      23.000  18.000  16.000  1.00  0.00           O  
ATOM     29  N   ILE A   8      24.000  17.000  16.000  1.00  0.00           N  
ATOM     30  CA  ILE A   8      25.000  17.000  17.000  1.00  0.00           C  
ATOM     31  C   ILE A   8      25.000  18.000  17.000  1.00  0.00           C  
ATOM     32  O   ILE A   8      25.000  19.000  17.000  1.00  0.00           O  
ATOM     33  N   LYS A   9      26.000  18.000  17.000  1.00  0.00           N  
ATOM     34  CA  LYS A   9      27.000  18.000  18.000  1.00  0.00           C  
ATOM     35  C   LYS A   9      27.000  19.000  18.000  1.00  0.00           C  
ATOM     36  O   LYS A   9      27.000  20.000  18.000  1.00  0.00           O  
ATOM     37  N   LEU A  10      28.000  19.000  18.000  1.00  0.00           N  
ATOM     38  CA  LEU A  10      29.000  19.000  19.000  1.00  0.00           C  
ATOM     39  C   LEU A  10      29.000  20.000  19.000  1.00  0.00           C  
ATOM     40  O   LEU A  10      29.000  21.000  19.000  1.00  0.00           O  
EOF

    chmod -R 777 /home/user

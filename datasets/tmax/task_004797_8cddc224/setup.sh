#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip redis-server golang curl
    pip3 install pytest

    mkdir -p /app/data /app/scripts

    # Create a dummy PDB file for 1XYZ
    cat << 'EOF' > /app/data/1XYZ.pdb
ATOM      1  N   ALA A   1      11.104   6.134  -6.504  1.00  0.00           N  
ATOM      2  CA  ALA A   1      11.639   6.071  -5.147  1.00  0.00           C  
ATOM      3  C   ALA A   1      10.601   6.512  -4.120  1.00  0.00           C  
ATOM      4  O   ALA A   1       9.516   5.945  -4.084  1.00  0.00           O  
ATOM      5  CB  ALA A   1      12.871   6.963  -5.068  1.00  0.00           C  
ATOM      6  N   CYS A   2      10.929   7.530  -3.305  1.00  0.00           N  
ATOM      7  CA  CYS A   2      10.023   8.056  -2.298  1.00  0.00           C  
ATOM      8  C   CYS A   2      10.456   9.479  -1.942  1.00  0.00           C  
ATOM      9  O   CYS A   2      11.637   9.790  -1.849  1.00  0.00           O  
ATOM     10  CB  CYS A   2      10.021   7.172  -1.045  1.00  0.00           C  
ATOM     11  SG  CYS A   2       8.354   7.070  -0.301  1.00  0.00           S  
ATOM     12  N   ASP A   3       9.489  10.355  -1.745  1.00  0.00           N  
ATOM     13  CA  ASP A   3       9.789  11.758  -1.428  1.00  0.00           C  
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app

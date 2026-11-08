#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc build-essential
    pip3 install pytest

    mkdir -p /home/user/data

    cat << 'EOF' > /home/user/data/input.pdb
ATOM      1  N   THR A   1      17.047  14.099   3.625  1.00 13.79           N  
ATOM      2  CA  THR A   1      16.967  12.784   4.338  1.00 10.80           C  
ATOM      3  C   THR A   1      15.685  12.755   5.133  1.00  9.19           C  
ATOM      4  O   THR A   1      15.268  13.825   5.594  1.00  9.85           O  
ATOM      5  CB  THR A   1      18.170  12.703   5.337  1.00 13.02           C  
ATOM      6  OG1 THR A   1      19.334  12.829   4.463  1.00 15.06           O  
ATOM      7  CG2 THR A   1      18.150  11.546   6.304  1.00 14.23           C  
ATOM      8  N   PRO A   2      15.115  11.555   5.265  1.00  7.81           N  
ATOM      9  CA  PRO A   2      13.856  11.469   6.066  1.00  8.31           C  
ATOM     10  C   PRO A   2      14.164  10.785   7.379  1.00  5.80           C  
ATOM     11  O   PRO A   2      15.285  10.375   7.641  1.00  5.65           O  
ATOM     12  CB  PRO A   2      12.921  10.596   5.226  1.00  9.12           C  
ATOM     13  CG  PRO A   2      13.811   9.500   4.685  1.00 10.01           C  
ATOM     14  CD  PRO A   2      15.111  10.322   4.569  1.00  7.40           C  
ATOM     15  N   ASN A   3      13.161  10.669   8.196  1.00  4.96           N  
ATOM     16  CA  ASN A   3      13.310  10.081   9.531  1.00  5.37           C  
ATOM     17  C   ASN A   3      12.062   9.336   9.998  1.00  5.49           C  
ATOM     18  O   ASN A   3      10.985   9.897   9.889  1.00  5.35           O  
ATOM     19  CB  ASN A   3      14.520   9.141   9.593  1.00  7.19           C  
ATOM     20  CG  ASN A   3      14.249   7.747   9.055  1.00  9.17           C  
ATOM     21  OD1 ASN A   3      13.181   7.514   8.486  1.00  9.62           O  
ATOM     22  ND2 ASN A   3      15.216   6.822   9.231  1.00 11.23           N  
ATOM     23  N   CYS A   4      12.215   8.067  10.511  1.00  4.73           N  
ATOM     24  CA  CYS A   4      11.119   7.260  11.026  1.00  5.33           C  
ATOM     25  C   CYS A   4      11.517   5.793  10.999  1.00  5.45           C  
ATOM     26  O   CYS A   4      12.673   5.450  11.196  1.00  6.86           O  
ATOM     27  CB  CYS A   4      10.781   7.653  12.463  1.00  5.29           C  
ATOM     28  SG  CYS A   4       9.142   7.017  12.915  1.00  6.58           S  
ATOM     29  N   GLN A   5      10.551   4.928  10.742  1.00  5.53           N  
ATOM     30  CA  GLN A   5      10.817   3.491  10.706  1.00  6.09           C  
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user

#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk
    pip3 install pytest papermill jupyter

    mkdir -p /home/user/data /home/user/templates

    cat << 'EOF' > /home/user/data/input.fasta
>seq1
MVLSPADKTNVKAAWGKVGAHAGEYGAEALERMFLSFPTTKTYFPHF
>seq2
DLSHGSAQVKGHGKKVADALTNAVAHVDDMPNALSALSDLHAHKL
>seq3
RVDPVNFKLLSHCLLVTLAAHLPAEFTPAVHASLDKFLASVSTVLTSKYR
EOF

    cat << 'EOF' > /home/user/data/structure.pdb
ATOM      1  N   ALA A   1      11.104   6.134  -6.504  1.00  0.00           N  
ATOM      2  CA  ALA A   1      10.160   5.050  -6.195  1.00  0.00           C  
ATOM      3  C   ALA A   1       8.773   5.642  -5.918  1.00  0.00           C  
ATOM      4  O   ALA A   1       8.607   6.862  -5.856  1.00  0.00           O  
ATOM      5  CB  ALA A   1      10.640   4.120  -5.086  1.00  0.00           C  
ATOM      6  N   GLY A   2       7.780   4.766  -5.748  1.00  0.00           N  
ATOM      7  CA  GLY A   2       6.398   5.201  -5.503  1.00  0.00           C  
ATOM      8  C   GLY A   2       5.602   4.041  -4.908  1.00  0.00           C  
ATOM      9  O   GLY A   2       6.155   2.949  -4.733  1.00  0.00           O  
EOF

    cat << 'EOF' > /home/user/templates/report.ipynb
{
 "cells": [
  {
   "cell_type": "code",
   "execution_count": null,
   "metadata": {
    "tags": [
     "parameters"
    ]
   },
   "outputs": [],
   "source": [
    "ca_count = 0\n",
    "pi_estimate = 0.0"
   ]
  },
  {
   "cell_type": "code",
   "execution_count": null,
   "metadata": {},
   "outputs": [],
   "source": [
    "print(f\"CA Count: {ca_count}\")\n",
    "print(f\"Pi Estimate: {pi_estimate}\")"
   ]
  }
 ],
 "metadata": {
  "kernelspec": {
   "display_name": "Python 3",
   "language": "python",
   "name": "python3"
  },
  "language_info": {
   "codemirror_mode": {
    "name": "ipython",
    "version": 3
   },
   "file_extension": ".py",
   "mimetype": "text/x-python",
   "name": "python",
   "nbconvert_exporter": "python",
   "pygments_lexer": "ipython3",
   "version": "3.10.6"
  }
 },
 "nbformat": 4,
 "nbformat_minor": 5
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user

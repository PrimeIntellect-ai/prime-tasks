#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip espeak
    pip3 install pytest papermill nbconvert ipykernel

    mkdir -p /app

    # Generate audio file
    espeak -w /app/lab_notes.wav "Extract the sequence for gene YFG1. The primer length must be twenty. The target annealing temperature is sixty. Run fifty Monte Carlo iterations."

    # Create genome.fasta
    cat << 'EOF' > /app/genome.fasta
>gene_YFG1
ATGCGTACGTAGCTAGCTAGCTGATCGATCGTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCT
>gene_OTHER
ATGCATGCATGCATGCATGCATGCATGCATGCATGCATGCATGCATGC
EOF

    # Create simulate_pcr.ipynb
    cat << 'EOF' > /app/simulate_pcr.ipynb
{
 "cells": [
  {
   "cell_type": "code",
   "execution_count": null,
   "metadata": {
    "tags": ["parameters"]
   },
   "outputs": [],
   "source": [
    "fwd_primer = ''\n",
    "rev_primer = ''\n",
    "iterations = 0\n"
   ]
  },
  {
   "cell_type": "code",
   "execution_count": null,
   "metadata": {},
   "outputs": [],
   "source": [
    "print(f'Simulating {iterations} iterations for {fwd_primer} and {rev_primer}')\n"
   ]
  }
 ],
 "metadata": {
  "kernelspec": {
   "display_name": "Python 3",
   "language": "python",
   "name": "python3"
  }
 },
 "nbformat": 4,
 "nbformat_minor": 4
}
EOF

    # Create eval.py
    cat << 'EOF' > /app/eval.py
import sys

def calculate_score(fwd, rev):
    def calc_tm(seq):
        return 2*(seq.count('A')+seq.count('T')) + 4*(seq.count('G')+seq.count('C'))

    if len(fwd) != 20 or len(rev) != 20: return 0.0
    if calc_tm(fwd) != 60 or calc_tm(rev) != 60: return 0.0

    score = 0.5
    if fwd[-1] in 'GC': score += 0.2
    if rev[-1] in 'GC': score += 0.2

    return min(1.0, score)

with open(sys.argv[1], 'r') as f:
    fwd, rev = f.read().strip().split(',')

score = calculate_score(fwd, rev)
print(f"Efficiency Score: {score}")
if score >= 0.85:
    sys.exit(0)
else:
    sys.exit(1)
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app

#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip espeak gcc ffmpeg
    pip3 install pytest

    mkdir -p /app/corpora/clean
    mkdir -p /app/corpora/evil

    # Generate the audio file
    espeak -w /app/lab_dictation.wav "The target primer is G A C T C G A T and the decay constant is zero point two five."

    # Generate FASTA files
    python3 -c '
import os
import random

random.seed(42)
bases = ["A", "C", "G", "T"]

# Clean corpus: random sequences, no GACTCGAT
for i in range(10):
    seq = "".join(random.choices(bases, k=1000))
    seq = seq.replace("GACTCGAT", "AAAAAAAA")
    with open(f"/app/corpora/clean/clean_{i}.fasta", "w") as f:
        f.write(f">clean_{i}\n")
        f.write(seq + "\n")

# Evil corpus: back-to-back GACTCGAT to maximize matches
for i in range(10):
    # Repeat GACTCGAT to fill 1000 bases
    seq = ("GACTCGAT" * 125)
    with open(f"/app/corpora/evil/evil_{i}.fasta", "w") as f:
        f.write(f">evil_{i}\n")
        f.write(seq + "\n")
'

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app

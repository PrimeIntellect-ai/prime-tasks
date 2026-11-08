#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        imagemagick \
        tesseract-ocr \
        fonts-liberation \
        gawk \
        coreutils

    pip3 install pytest

    mkdir -p /app/corpora/clean /app/corpora/evil

    python3 -c "
import os
import random

os.makedirs('/app/corpora/clean', exist_ok=True)
os.makedirs('/app/corpora/evil', exist_ok=True)

bases = ['A', 'C', 'G', 'T']
gc = ['G', 'C']
at = ['A', 'T']

for i in range(500):
    clean_seq = ''.join(random.choice(bases) for _ in range(300))
    with open(f'/app/corpora/clean/seq_{i}.txt', 'w') as f:
        f.write(clean_seq)

    evil_seq = []
    for j in range(300):
        if j % 3 == 0:
            if random.random() < 0.8:
                evil_seq.append(random.choice(gc))
            else:
                evil_seq.append(random.choice(at))
        else:
            evil_seq.append(random.choice(bases))
    with open(f'/app/corpora/evil/seq_{i}.txt', 'w') as f:
        f.write(''.join(evil_seq))
"

    # Fix ImageMagick policy if needed (sometimes required for ghostscript/fonts, but label: usually works)
    convert -background white -fill black -pointsize 18 label:"NULL_MODEL: Length 300, equal ACGT probability.\nMETRIC: Max difference between GC counts at positions (i%3=0), (i%3=1), (i%3=2). (0-indexed)\nREJECT_THRESHOLD: 99th percentile of NULL_MODEL (N=1000)." /app/lab_notes.png

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app

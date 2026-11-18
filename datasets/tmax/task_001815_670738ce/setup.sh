#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ make
    pip3 install pytest Pillow

    mkdir -p /app

    cat << 'EOF' > /tmp/generate_data.py
import random
from PIL import Image, ImageDraw

# Generate Image
text = """Scoring Model v3.1
Match: +5
Transition (A<->G or C<->T): -1
Transversion (A/G <-> C/T): -3"""

img = Image.new('RGB', (400, 150), color=(255, 255, 255))
d = ImageDraw.Draw(img)
d.text((10, 10), text, fill=(0, 0, 0))
img.save('/app/scoring_rules.png')

# Generate FASTA
motif = "ATGCGATCGATCGTA"
random.seed(42)

def mutate(m):
    res = ""
    for c in m:
        if random.random() < 0.15:
            if random.random() < 0.7:
                # Transition
                if c == 'A': res += 'G'
                elif c == 'G': res += 'A'
                elif c == 'C': res += 'T'
                elif c == 'T': res += 'C'
            else:
                # Transversion
                choices = [x for x in 'ACGT' if x != c and not ({x, c} == {'A', 'G'} or {x, c} == {'C', 'T'})]
                res += random.choice(choices)
        else:
            res += c
    return res

with open('/app/sequences.fasta', 'w') as f:
    for i in range(100):
        f.write(f">seq{i}\n")
        seq = "".join(random.choices("ACGT", k=200))
        pos = random.randint(0, 200 - 15)
        mutated_motif = mutate(motif)
        seq = seq[:pos] + mutated_motif + seq[pos+15:]
        f.write(seq + "\n")
EOF

    python3 /tmp/generate_data.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app

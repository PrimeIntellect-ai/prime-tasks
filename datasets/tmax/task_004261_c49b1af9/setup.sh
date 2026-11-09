#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libc6-dev
    pip3 install pytest Pillow

    mkdir -p /app

    # Generate /app/data.fasta
    cat << 'EOF' > /tmp/gen_fasta.py
import random

random.seed(42)
with open('/app/data.fasta', 'w') as f:
    for i in range(150):
        # Generate lengths that cluster to form a good connected component
        # Cluster 1 around length 50, Cluster 2 around length 100
        if i < 100:
            length = random.randint(45, 55)
        else:
            length = random.randint(90, 110)

        # GC bias
        seq = []
        for _ in range(length):
            if random.random() < 0.6:
                seq.append(random.choice(['G', 'C']))
            else:
                seq.append(random.choice(['A', 'T']))

        f.write(f">seq{i}\n{''.join(seq)}\n")
EOF
    python3 /tmp/gen_fasta.py

    # Generate /app/protocol.png
    cat << 'EOF' > /tmp/gen_img.py
from PIL import Image, ImageDraw, ImageFont

text = """Analytical Protocol:
1. Graph Construction: 
   Nodes = sequences. 
   Edge = absolute length difference between two sequences is <= 2.
2. Filtering: 
   Find the Largest Connected Component (LCC) in this graph.
3. Feature Extraction (for nodes in LCC only):
   x = sequence length
   y = GC count (number of 'G' and 'C' characters)
4. Statistics:
   Calculate Pearson correlation coefficient (r) between x and y.
   Calculate the t-statistic for this correlation: 
   t = r * sqrt(N - 2) / sqrt(1 - r^2)
   where N is the number of nodes in the LCC.
5. Output:
   Write the absolute value of t to /app/result.txt
"""

img = Image.new('RGB', (600, 400), color = (255, 255, 255))
d = ImageDraw.Draw(img)
# Using default font
d.text((10,10), text, fill=(0,0,0))
img.save('/app/protocol.png')
EOF
    python3 /tmp/gen_img.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /app
    chmod -R 777 /home/user

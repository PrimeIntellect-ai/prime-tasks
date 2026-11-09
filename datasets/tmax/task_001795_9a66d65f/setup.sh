#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas numpy scipy scikit-learn

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/generate_data.py
import pandas as pd
import numpy as np
import random

np.random.seed(123)
random.seed(123)

categories = ['Physics', 'Biology', 'CS']
vocab_physics = ['quantum', 'mechanics', 'relativity', 'mass', 'energy', 'particle', 'field', 'force', 'gravity']
vocab_biology = ['cell', 'dna', 'protein', 'evolution', 'gene', 'species', 'organism', 'mutation', 'genetics']
vocab_common = ['the', 'of', 'and', 'to', 'a', 'in', 'is', 'that', 'for', 'it', 'as', 'was', 'with', 'be', 'by', 'on', 'not', 'he', 'i', 'this', 'are', 'or', 'his', 'from', 'at', 'which', 'but', 'have', 'an', 'had', 'they', 'you', 'were', 'their', 'one', 'all', 'we', 'can', 'her', 'has', 'there', 'been', 'if', 'more', 'when', 'will', 'would', 'who', 'so', 'no']

data = []
for i in range(500):
    cat = random.choice(categories)
    if cat == 'Physics':
        words = random.choices(vocab_physics, k=5) + random.choices(vocab_common, k=25)
    elif cat == 'Biology':
        words = random.choices(vocab_biology, k=5) + random.choices(vocab_common, k=25)
    else:
        words = random.choices(vocab_physics + vocab_biology, k=5) + random.choices(vocab_common, k=25)

    random.shuffle(words)
    text = " ".join(words) + ("," if random.random()>0.5 else "") + "."

    if cat == 'Biology':
        citations = int(np.random.negative_binomial(10, 0.5))
    else:
        citations = int(np.random.negative_binomial(5, 0.5))

    data.append({
        'id': i+1,
        'category': cat,
        'text': text,
        'citations': citations
    })

df = pd.DataFrame(data)
df.to_csv('/home/user/abstracts.csv', index=False)
EOF

    python3 /tmp/generate_data.py
    rm /tmp/generate_data.py

    chmod -R 777 /home/user
